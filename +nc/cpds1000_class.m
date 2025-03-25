% cpds1000_class.m
% NuCrypt Proprietary
% Matlab API for cpds1000
% version 2.1


% member variables ("properties") -- read only
%
%   cpds.devinfo: structure of device specifications & supported features
%      devinfo.hwver: hardware version.  1xn vector of integers
%      devinfo.fwver: firmware version.  1xn vector of integers
%      devinfo.num_det  : number of detectors in this CPDS. typically 0,2,or 4
%      devinfo.num_corr_chan : number of correlator channels. typically 4 or 8
%      devinfo.num_thresh : number of analog input thresholders
%      devinfo.num_chan : number of "channels". A rather vague concept now.
%                         preferrably, use num_det, num_corr_chan, etc.
%      devinfo.dly13_only: 0=normal.  1=delay only implemented on correlator chans 1 and 3
%                                       (for ancient cpds)
%      devinfo.has_rxlpm_rst: bug workaround for old firmware. 1=has, 0=hasnt
%      devinfo.has_t_cmd: firmware features "t" command, "manual mode for gui", rather obsolete
%      devinfo.has_timebin_mode: whether can correlate delayed version of same channel.
%                                0 for all cpds1000 so far
%      devinfo.has_maxc_cmd  
%      devinfo.gate_scan_len: resolution of setting the gate phase. subdivision of gate period.
%      devinfo.possible_chansrcs: cell array indexed by channel number.  Indexed cell is
%                   itself a channel array of strings, listing all possible channel sources
%                   for that channel.  For the latest firmware on a 2-detector CPDS this is:
%                      {{'d' 's' '0' '1'};
%                       {'d' 's' '0' '1'};
%                       {'s' '0' '1'};
%                       {'s' '0' '1'};
%                       {'r'};
%                       {'r'};
%                       {'r'};
%                       {'r'}};
%                   Where 'd'=detector, 's'=simulation signal, '0'=all zeros, '1'=all ones,
%                         'r'=remote.
%
%   cpds.settings: structure of current settings of device. automatically read when device opened.
%      settings.measlen  integer  The number of gate pulses over which one measurement
%                                 (of correlation statistics) is taken.
%                                 The temporal duration of one measurement will be measlen*clkdiv/clkfreq
%      settings.masklen  integer  Whether afterpulses are being masked. 0=unmasked, 1=masked.
%      settings.clkdiv: The downsampling rate.  The front-panel clock frequency is divided by the
%                       clkdiv to determine the gate frequency.
%      settings.bias: 1xn vector  indexed by detector id.  APD bias in dac units.
%      settings.dly: 1xn vector.  indexed by correlator channel.
%                                 The post-downsampling delay for each correlator channel
%      settings.gate_ph: 1xn vector  indexed by detector id.   Each detector’s gate phase in DAC units.
%      settings.thresh: 1xn vector indexed by detector or channel id. Each detector's compartor threshold in DAC units
%      settings.num_clks: integer How many front panel clock inputs are being used.  1 means  front panel clock 1 is used
%                                 for all detectors, 2 means clk1 is used for detectors 1 and 3 while clock2 is used for detectors
%                                 2 and 4. 
%      settings.clkfreq_Hz: integer.  So far, always 50e6 for a cpds1000
%      settings.refclk_Hz: integer.  so far, always 50e6
%      settings.chansrc{}: cell array indexed by channel number.  Contains strings.
%                          Possible channel sources are one of devinfo.possible_chansrcs{chan}
%      settings.chansrc_fid:  vector indexed by channel number.  Contains "fids".
%                          An "fid" is the 1-based flink index.  0 means does not apply.
%                          An RCS can have multiple flinks, but the CPDS can have only one.
%                          So on a cpds, settings.chansrc_fid=[0 0 0 0 1 1 1 1];
%
% Example use of some member functions:
%   cpds=cpds1000_class(port);  % CONSTRUCTOR. calls open, then get_settings.
%   if (~cpds.isopen()) return; end
%   cpds.gate_scan(detid, measlen, set_to_max);
%   cpds.set_measlen(1000000);
%   cpds.set_masklen(1,1);
%   errmsg = cpds.meas_counts_start(chanmsk, 1);
%   cpds.close();




% in general:
%   set_* - change a setting on device
%   meas_* - measure something using device
%   cal_* - function intended for calibration only, not for general use




classdef cpds1000_class < nc.cpds_class

  properties (Constant=true)
  end

  % instance members
  properties
    dbg  % 0=none, 1=debug cpds reads
    dbg_ctr
    port
    ser
    idn
    devinfo
    settings
%      settings.measlen
%      settings.masklen
%      settings.clkdiv
%      settings.clkfreq_Hz
%      settings.refclk_Hz
%      settings.bias(detid)
%      settings.dly(detid)
%      settings.gate_ph(detid)
%      settings.thresh(detid)
    expected % for internal use
    abort_flag
  end
  
  methods (Access = private, Static=true)

      function v=safeidx(map, idx)
	if ((idx<1)||(idx>length(map)))
	  v=0;
	else
	  v = map(idx);
	end
      end
      
      function idx=safe_find(map, id)
        idx = find(id==map,1);
        if (isempty(idx))
          idx=0;
        end
      end
      
      function n=safe_str2num(str)
        % Did you know that matlab's str2num() actually executes arbitrary code?
        % Try this: str2num('cos(1)').  That is crazy!  Do not use str2num().
        [n ct]=sscanf(str, '%g', 1);
        if (ct<1)
          n=0;
        end
      end
      
      function n=safe_hex2dec(str)
        [n nc]=sscanf(str,'%x',1);
        if (nc~=1)
          n=0;
        end
      end
      
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function str = chan_idx2str(idx)
    % idx: channel index base 1, which is the matlab "way".
      str=sprintf('%d',idx);
    end
    
    function str = corrstat_id2str(id)
      if (bitand(id,nc.cpds_class.ACCID))
	id = bitand(id,bitcmp(nc.cpds_class.ACCID));
	str='a';
      elseif (nc.util.bitcnt(id)==1)
	str='s';
      else
	str='c';
      end
      for pci=1:8
	if (bitget(id, pci))
	  str = [str '1'+pci-1];
	end
      end
    end

    function init_corrstat_map()
      global CPDS1000_G;
      import nc.*
      
      %                     s1 s2 c12  a12   ap1   ap2
      map.idx2id_f2=uint32([ 1  2   3  a(3)  a(1)  a(2)]);
      
      %                      s1 s2 s3 s4  c12 a12  c34 a34  c13 a13  c24 a24  c14 a14  c23 a23   c1234 a1234  ap1 ap2 ap3 ap4
      map.idx2id_f4=[ uint32(1)  2  4  8   3  a(3) 12 a(12)  5 a(5)  10 a(10) 9 a(9)   6 a(6)   15 a(15) a(1) a(2) a(4) a(8) ];
      [map.c_id2idx_f2  map.a_id2idx_f2] = invmap(map.idx2id_f2);
      [map.c_id2idx_f4  map.a_id2idx_f4] = invmap(map.idx2id_f4);
       
      CPDS1000_G.map = map;

      % nested  
      function [map_c map_a] = invmap(idx2id)
	map_c = zeros(1,16);
	map_a = zeros(1,16);
	for ii=1:length(idx2id)
	  id = idx2id(ii);
	  if (bitand(id,nc.cpds_class.ACCID))
            map_a(bitand(id,bitcmp(nc.cpds_class.ACCID)))=ii;
	  else
            map_c(id) = ii;
	  end
	end
      end

      % nested
      function id = a(id)
	id = bitor(uint32(id),nc.cpds_class.ACCID);
      end

    end





    function temp_c = apd_temp_v2c(v)
      d= 0.0001;
      a= 0.00146785;
      b= 0.000238244;
      c= 1.02221e-007;
      r=v/d; % v/ibias
%	  // oprintf(" R=%g\n", r);
      r=log(r);
%	  // oprintf(" lnR=%g\n", r);
%	  // d=(a+b*r+c*r*r*r);
%	  // oprintf(" d=%g\n", d);
      temp_c = (1./(a+b*r+c*r*r*r)-273.15);
    end

    function V = bias_dac2V(detid, d)
      % Note: typical, but actual devices may vary
      V = 2.048 * d / (2^16); % output of DAC in Volts
      V = 71.289 - 22.079 * (2.048-V);
    end
    
    function dac = bias_V2dac(detid, V)
      % Note: typical, but actual devices may vary
      V = 2.048 - (71.289 - V)/22.079; % output of DAC
      dac = min(max(0,round(V / 2.048 * 2^16)),2^16-1);
    end

    function mV = thresh_dac2mV(detid, dac)
      mV = (dac-32768) * 505 / 8192;
    end
    
    function dac = thresh_mV2dac(detid, mV)
      dac = round(mV*8192 / 505 + 32768);
    end
    

    
    
%    function v = idn_rsp_ok(idn_rsp) % static
%      import nc.*
%      flds=ser_class.parse_idn_rsp(idn_rsp);
%      v = (length(flds)>2)&& strcmpi(flds{1},'CPDS') && strcmp(flds{2},'1000');
%    end

    function m = parse_gate_scan(str)
      m=[];
      str = regexprep(str, [char(27) '[\d+m' ], '');
      idxs=regexp(str, '\n');
      is=idxs(1)+1; % skip first line which is echo
      ll=0;
      ph=0;
      for k=2:length(idxs)
        ie=idxs(k)-1;
	[r ct] = sscanf(str(is:ie), '%x', 1);
        if ((ct>0) && (r==ph))
%	  uio.print_all(str(is:ie));
          r = sscanf(str(is+4:ie), '%d'); % returns ver vec
          ph = ph + length(r);
          m = [m r.'];
        end
        is = ie+1;
      end
    end

    function devinfo = parse_idn(idn)
    % input: idn structure returned from ser_class.get_idn_rsp.  This structure has
    %        the following significant fields:
    %      .irsp      : string of idn rsp (case preserved)
    %      .name      : string name (all lowercased)
    %      .model     : model number as a number
    %      .hwver     : row vector of firmware version
    %      .fwver     : row vector of firmware version
    %      .sn        : lowcase string serial number (WITHOUT SN PREFIX)
    %
    % returns a structure with these fields:
    %      devinfo.num_det
    %      devinfo.num_chan
    %      devinfo.num_corr_chan
    %      devinfo.con
    %      devinfo.ser
      import nc.*
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      model=0;
      if (num_flds>=2)
        model = parse_word(flds{2}, '%d', model);
      end

      devinfo = idn; % inherit what was already parsed

      for_fwver = [5 2 0];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: cpds2000_class(): This software was written for CPDS/RCS firmwares %s and below\n', util.ver_vect2str(for_fwver));
        fprintf('      but %s is has firmware %s and might not work with this +nc package\n', ...
                devinfo.name, util.ver_vect2str(devinfo.fwver));
      end
      
      % default CPDS 1000
      devinfo.num_det  = 2;
      devinfo.num_chan = 2;
      devinfo.num_corr_chan = 2;
      devinfo.con = 's'; % std
      devinfo.ser = 's'; % std
      devinfo.can_set_refclk = 0;
      devinfo.can_set_clkfreq = 0;
      devinfo.can_set_outclk = 0;
      devinfo.can_set_flink_baud = 0;
      devinfo.masklens = [0 1]; % possible masklens
      devinfo.num_flink = 0;
      devinfo.num_bridge_chans = 0;
      devinfo.refclk_can_be_rxclk = 0;
      devinfo.is_fallback = 0;

      % correct for 5.1 but not earlier
      dly_w = [16 16 16 16 8 8 8 8];      
      devinfo.dly_max = (2.^dly_w)-1;
      
      if (3 <= num_flds) % C1
        devinfo.num_det    = parse_word(flds{3}, '%d', 2);
      end

      devinfo.num_thresh = devinfo.num_det;
      devinfo.num_chan      = devinfo.num_det;
      devinfo.num_corr_chan = devinfo.num_det;
      devinfo.num_dly       = devinfo.num_det;
      devinfo.has_simsig    = nc.util.ver_is_gte(devinfo.fwver,[4 0]);
      devinfo.has_txrx_rdy_indic = 0;
      
      devinfo.is_rcs = (devinfo.num_chan==0);
      if (devinfo.is_rcs)
	devinfo.num_thresh = 4;
        devinfo.num_chan = 4;
        devinfo.num_corr_chan = 4;
        devinfo.num_dly      = 4;
      end

      % set of possible channel sources for each channel
      if (devinfo.has_simsig)
        fabricated_srcs = {'s' '0' '1'};
      else
        fabricated_srcs = {'0'};
      end
      devinfo.possible_chansrcs=cell(8,1);
      for k=1:4
        if (k<=devinfo.num_det)
          devinfo.possible_chansrcs{k} = [{'d'} fabricated_srcs];
        else
          devinfo.possible_chansrcs{k} = fabricated_srcs;
        end
      end
      for k=5:8
        devinfo.possible_chansrcs{k} = {'flink'};
      end
      

      % anyway, old fimwares should be updated!
      
      % correct old mistaken version system
      if (util.ver_is(devinfo.hwver,[3 6]) && util.ver_is(devinfo.fwver,[1 2]))
        devinfo.fwver = [3 7];
        devinfo.hwver = [1 0];
      elseif (~nc.util.ver_is_gte(devinfo.fwver,[3 9]))
        devinfo.fwver = devinfo.hwver;
        devinfo.hwver = [1 0];
      elseif (~nc.util.ver_is_gte(devinfo.fwver,[3 16]))
        devinfo.hwver = [1 0];
      end


      devinfo.meas_apul_with_sings = nc.util.ver_is_gte(devinfo.fwver, [3 11]);
      devinfo.dly13_only = ~nc.util.ver_is_gte(devinfo.fwver, [3 12]);

      % compute expected values for this fwver/variation
      devinfo.has_rxlpm_rst = nc.util.ver_is_gte(devinfo.fwver, [4 1 0]);
      devinfo.has_t_cmd     = nc.util.ver_is_gte(devinfo.fwver, [3 7]); % t = manual mode for gui
      devinfo.has_timebin_mode = 0;
      devinfo.has_maxc_cmd  = nc.util.ver_is_gte(devinfo.fwver, [3 11]);
      devinfo.has_free_run_always = nc.util.ver_is_gte(devinfo.fwver, [5 2]);

      if (devinfo.fwver(1)<4) % avnetv5 board
        devinfo.gate_scan_len = 256;
      else % ac701 board
        devinfo.gate_scan_len = 280;
      end


      % C2
      if (4<=num_flds)
        devinfo.con = lower(flds{4}(1));
      end
      if (devinfo.con=='c')
        devinfo.num_flink = 1;
        devinfo.num_corr_chan = 8;
        devinfo.num_dly       = 8;
        devinfo.num_bridge_chans = util.ifelse(nc.util.ver_is_gte(devinfo.fwver,[5 2]),1,0);
      end

      % to convert numeric status to meaningful phrases
      devinfo.cmpr_stopreason_map = {0, 'ok';
                                     1, 'cmprovf';
                                     2, 'txovld';
                                     3, 'dstop';
                                     4, 'noack'};
      devinfo.dcmpr_stopreason_map = {0, 'ok';
                                      1, 'badclk';
                                      2, 'badcrc';
                                      3, 'rxcrcovf';
                                      4, 'rxuflow';
                                      5, 'rxovf';
                                      6, 'stop'};
      devinfo.dcmpr_state_map = {0, 'idl';
                                 1, 'go';
                                 2, 'term'};
      devinfo.cmpr_state_map = {0, 'idl';
                                1, 'start';
                                2, 'go';
                                3, 'term'};


                             
      
      % C3
      if(5<=num_flds)
        devinfo.ser = flds{5}(1);
      end

      
      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
         v = default;
        end
      end
      
    end


    % STATIC    
    function dst = backslash_plain2code(src)
      dst=strrep(src, char(13), '\r');
      dst=strrep(dst, '>', '\076');
      dst=strrep(dst, '\', '\\');
    end
    
    % STATIC
    function dst = backslash_code2plain(src)
      s_i=1;
      s_l=length(src);
      d_i=1;
      dst=char(zeros(1,s_l));
      while(s_i<=s_l)
        c=src(s_i);
        s_i=s_i+1;
        if ((c=='\')&&(s_i<=s_l))
          c=src(s_i);
          s_i=s_i+1;
          if ((c>='0')&&(c<='9'))
            n=0;
            for h=1:3
              n=n*8+c-'0';
              if (h==3)
                break;
              end
              c=src(s_i);
              s_i=s_i+1;
              if ((c<'0')||(c>'9')||(s_i>s_l))
                break;
              end
            end
            c=char(n);
          else
            if (c=='r')
              c=char(13);
            elseif (c=='n')
              c=char(10);
            end
          end
        end
        dst(d_i)=c;
        d_i=d_i+1;
      end
      dst=dst(1:(d_i-1));
    end

    
  end


  methods

    function b=fwver_is_gte(me, ver)
      import nc.*
      b = nc.util.ver_is_gte(me.devinfo.fwver, ver);
    end

    
    % CONSTRUCTOR
    function me = cpds1000_class(arg1, opt)
    % desc: constructor
      % use:
      %   obj = cpds2000_class(ser, opt)
      %           ser: a ser_class object
      %   obj = cpds2000_class(port, opt)
      % inputs: port: windows port name that cpds is attached to. a string.
      %         opt: optional structure. optional fields are:
      %           opt.dbg: 0=normal, 1=print all low level IO
      %           opt.baud: baud rate to use
      %
      import nc.*
      me.ser = [];
      me.idn = [];
      me.devinfo = [];

      if (nargin<1)
	arg1='';
      end
      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'baud', 115200);
      me.dbg = opt.dbg;

      me.expected.freerun=0;      
      me.expected.maxc_st=0;
      me.expected.pending_clk_bad_ctrs=[0 0];

      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.idn = me.ser.idn;
        me.devinfo = me.parse_idn(me.idn);
        me.set_nomenu(1);
        me.get_settings();
      elseif (ischar(arg1))
        me.ser=nc.ser_class(arg1, opt);
        me.open();
      else
        error('first param must be portname or ser_class');
      end
      me.expected.meas_counts_active=0;
    end % constructor

    % DESTRUCTOR
    function me = delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function close(me)
      if (me.isopen())
        % me.set_nomenu(0);
        me.ser.close;
      end
    end

    function b = isopen(me)
      b = me.ser.isopen();
    end
    
    function set_free_run_always(me, en)
      if (me.devinfo.has_free_run_always)
        me.ser.do_cmd('2');
        me.ser.do_cmd('r');
        me.ser.do_cmd([char('0'+logical(en)) char(13)]);
        me.ser.do_cmd('e');
        me.settings.free_run_always = en;
      end
    end

    function set_flink_cmpr_pwr(me, pwr)
      if (nc.util.ver_is_gte(me.devinfo.fwver, [5 2]))
        me.ser.do_cmd('f');
        me.ser.do_cmd('p');
        [m err] = me.ser.do_cmd_get_matrix([num2str(pwr) char(13)]);
        if (~isempty(m) && ~err)
          me.settings.flink_cmpr_pwr = m(1);
        else
          me.settings.flink_cmpr_pwr = pwr;
        end
        me.ser.do_cmd('e');
      end
    end
    
    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end
    
    function open(me, portname, opt)
    % cpds1000_class.open()
    % use:
    %   cpds.open()
    %   cpds.open(portname)
    %   cpds.open(opt)
    %   cpds.open(portname, opt)
    % desc:
    %   opens device and gets identity and current settings
    % inputs:
    %   portname: string. if omitted or '', uses prior
    %   opt: optional structure of options
    %     opt.portname: optional string.  If omitted, or '', uses prior
    %     opt.baud
    %     opt.dbg
      import nc.*
      if (nargin==1)
        portname='';
        opt.dbg = me.dbg;
      elseif (nargin==2)
        if (isstruct(portname))
          opt = util.set_field_if_undef(portname, 'dbg', 0);
          portname=util.getfield_or_dflt(opt,'portname','');
          me.dbg = opt.dbg;
        else
          opt.dbg=me.dbg;
        end
      end
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      else
        if (~me.ser.isopen())
%          'cpds1000: set dbg 1'
%          me.ser.dbg=1;
          me.ser.open(portname, opt);
        end
      end
      if (me.ser.isopen)
        me.idn = me.ser.get_idn_rsp; % identity structure
        me.devinfo = me.parse_idn(me.idn);
        me.set_nomenu(1);
        me.get_settings();
      end
    end

    function ns = dly_dac2ns(me, dac)
    % desc: converts correlator delay from dac units to ns
      ns = 1e9*dac/me.settings.clkfreq_Hz;
    end
    
    function dac = dly_ns2dac(me, ns)
    % desc: converts correlator delay from units of ns to dac units
      dac = round(ns/1e9*me.settings.clkfreq_Hz);
    end

    function m = gate_scan(me, detid, measlen, set_to_max)
      % desc: ramps the gate phase of specified detector and measures
      %     singles counts at each setting
      % inputs:
      %    detid: detector to observe
      %    measlen: number of gate pulses to measure over
      %    set_to_max: 1=set gate phase to phase that resulted in max singles.
      %                0=after ramp, restore gate phase to prior setting
      % returns: m: matrix containing response.  empty if there was an error
      [rsp errp] = me.ser.do_cmd('6');
      [rsp errp] = me.ser.do_cmd(char('0'+detid));
      [rsp errp] = me.ser.do_cmd('6');
      % it doesn't print prompt after gate scan, instead a semicolon
      me.ser.write([sprintf('%x', measlen) char(13)]);
      [rsp fk to] = me.ser.read(4000, 2000, ';');
      if (fk)
        m = me.parse_gate_scan(rsp);
      else
        m=[];
      end  
      if (set_to_max)
        [rsp errp] = me.ser.do_cmd('m');
      else
        [rsp errp] = me.ser.do_cmd('e');
      end
    end

    function ps = gate_ph_dac2ps(me, detid, dac)
    % desc: converts gate phase from dac units to ps
    % dac: may be vector
      if (nc.util.ver_is_gte(me.devinfo.fwver, [4 1 0]))
        ps = dac/280 * 20000;
      else
        ps = dac/256 * 20000;
      end
    end
    
    function dac = gate_ph_ps2dac(me, detid, ps)
    % desc: converts gate phase from ps to dac units
      if (nc.util.ver_is_gte(me.devinfo.fwver, [4 1 0]))
        dac = round(ps * 280 / 20000);
      else
        dac = round(ps * 256 / 20000);
      end
    end

    
    function set_nomenu(me, nomenu)
    % desc: control over "nomenu mode", which decreases unnecessary IO between CPDS1000 and host
    %       by not printing the menus.
    % inputs: nomenu=0 turns off "nomenu mode".  nonmenu=1 turns on "nomenu mode".
      me.settings.nomenu = 0;
      if (nc.util.ver_is_gte(me.devinfo.fwver, [4 2 1]))
        me.settings.nomenu = nomenu;
        if (nomenu)
          me.ser.do_cmd('n'); % nomenus
        else
          if (nc.util.ver_is_gte(me.devinfo.fwver, [5 2 0]))
            me.ser.do_cmd('i'); % nomenus
          else
            % prior to 5.1 there was no > response to the i command, so dont wait for it.
            % note this old cpds is never bridged, so we can just write.
            me.ser.write('i');
          end
        end
      end
    end

    function rxlpm_rst(me)
    % desc: control over a bug work-around
      if (me.devinfo.has_rxlpm_rst)
        me.ser.do_cmd('R');
      end
    end


    function set_num_clks(me, num_clks)
      % desc: sets num_clks, which is How many front panel clock inputs are being used. 
      % inputs: num_clks=1 means front panel clock 1 is used for all detectors
      %         num_clks=2 means clk1 is used for detectors 1 and 3 while clk2 is used for detectors 2 and 4.
      me.ser.do_cmd('2');
      me.ser.do_cmd('m');
      me.ser.do_cmd([char('0'+num_clks) char(13)]);
      me.ser.do_cmd('e');
      me.settings.num_clks = num_clks;
    end
    
    function set_chansrc(me, chanid, src)
      if ((chanid<1)||(chanid>me.devinfo.num_corr_chan))
        error(sprintf('cpds1000_class.set_chansrc(%d,%s): invalid chanid', chanid, src));
      end
      vld=any(cellfun(@(x) strcmp(x,src),me.devinfo.possible_chansrcs{chanid}));
      if (~vld)
        error(sprintf('cpds1000_class.set_chansrc(%d,%s): invalid channel source', chanid, src));
      end
      if (strcmp(src,'0')) % zeros
        s='6';
      elseif (strcmp(src,'1')) % ones
        s='5';
      elseif (strcmp(src,'d')) % detector
        s='0';
      elseif (strcmp(src,'s')) % simsig
        s='8';
      elseif (strcmp(src,'flink')) % remote source
        % it is always this. cannot be changed.
        me.settings.chansrc{chanid}=src;
        return;
      else
        error(sprintf('BUG: cpds1000_class.set_chansrc(%d,%s): valid channel source, but just not implemented yet.', chanid, src));
      end
      me.ser.do_cmd('2');
      me.ser.do_cmd('I');
      me.ser.do_cmd(num2str(chanid));
      me.ser.do_cmd(s);
      me.ser.do_cmd('e');
      me.ser.do_cmd('e');
      me.settings.chansrc{chanid}=src;
     end
    
    function set_clkdiv(me, clkdiv)
    % desc: sets clkdiv, the downsampling rate.
    %       The detectors are gated synchronously with an external 50MHz clk, but this
    %       is divided by clkdiv to determine the gate frequency.
      me.ser.do_cmd('2'); % 2 = go into "set parameters" sub-menu
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 4]))
        % TODO: explain this. it is so wierd. why is it like this? is it a bug?
        % it is a very old version though.  Our in-house cpds4 is version 3.11
        n = clkdiv*2-1;
        me.ser.do_cmd(['4' dec2hex(n) 13]); % 4 = set clk div
        %   if (err)
        %    msg_red_nl('WARN: cpds gave bad rsp to 4 (set optical rep rate) cmd');
        % end
      else
        [rsp err] = me.ser.do_cmd('4','div','');
        if (~err)
          [rsp err] = me.ser.do_cmd([dec2hex(clkdiv) 13]);
        end
      end
      me.ser.do_cmd('E'); % E = go back to main menu
      me.settings.clkdiv = clkdiv;
    end

    function err = set_timebin_mode(me, en, use_remote)
      % timebin mode not supported by cpds1000 at all
      err = en;
    end
    
    function set_measlen(me, measlen)
      % desc: sets the number of gate pulses over which one measurement (of correlation statistics) is taken.
      %   The temporal duration of one measurement will be measlen*clkdiv/clkfreq
      me.ser.do_cmd('2'); % 2 = go into "set parameters" sub-menu
      me.ser.do_cmd('2'); % 2 = go to "set num pulses per capture" submenu
      % 7/27/18 - must use lower(dec2hex()) or sprintf('%x') because cpds V 3.16
      %           at Binghamton U (AFRL) only parses lowercase hex for measlen.
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 4]))
        me.ser.do_cmd(sprintf('6%x\r', measlen)); % the old ATT cpds
      else
        me.ser.do_cmd('6'); % manual entry in hex
        me.ser.do_cmd(sprintf('%x\r', measlen)); % manual entry in hex
      end
      me.ser.do_cmd('e'); % return to main menu
      me.settings.measlen = measlen;
    end

    function set_masklen(me, chan, masklen)
      % desc: sets the mask length in units of optical pulses.
      %       updates settings.masklen, which might be different
      % inputs: measlen: mask length in units of gates
      % inputs: chan: currenltly ignored
      %
      % Note: The cpds1000 does not currently have per-channel
      % masking. The cpds2000 has per-channel masking, and each
      % channel can mask for a different length.  This accomodates the
      % use of detectors of different qualities when using an RCS.  We
      % attempt to unify the functional interfaces of cpds1000_class.m
      % and cpds2000_class.m.  So for the cpds1000, the chan input is
      % ignored.
      %
      if (nargin<3)
        error('cpds100.set_masklen() not enough args');
      end
      masklen = (masklen~=0);
      [rsp errp] = me.ser.do_cmd('2'); % 2 = go into "set parameters" sub-menu
      if (masklen) cmd='p'; else cmd='q'; end
      % NOTE: at one point, one cpds had old C code that did not have
      % the p or q commands, while another cpds had them.
      [rsp errp] = me.ser.do_cmd(cmd);
      [rsp errp] = me.ser.do_cmd('e'); % return to main menu
      me.settings.masklen = masklen;
    end


    function m = set_bias(me, detid, bias)
      % desc: sets the APD bias in dac units
      % inputs: detid: 1 to 4
      [rsp errp] = me.ser.do_cmd('2');
      [rsp errp] = me.ser.do_cmd(char('5'+detid));
      [rsp errp] = me.ser.do_cmd(sprintf('%x\r', bias));
      [rsp errp] = me.ser.do_cmd('e'); % return to main menu      
      me.settings.bias(detid) = bias;
    end

    function m = set_thresh(me, detid, thresh)
      % desc: in a CPDS, sets a detector's compartor threshold.  In an RCS with front-end
      %   analog thresholding, sets the input comparator's voltage threshold.
      % thresh: threshold in DAC units.
      [rsp errp] = me.ser.do_cmd('2');
      [rsp errp] = me.ser.do_cmd(char('a'+detid-1));
      [rsp errp] = me.ser.do_cmd(sprintf('%x\r', thresh));
      [rsp errp] = me.ser.do_cmd('e'); % return to main menu      
      me.settings.thresh(detid) = thresh;
    end


    function m = set_gate_ph(me, detid, ph)
      % desc: sets a detector’s gate phase
      % inputs: detid: detector ID. range 1 to me.devinfo.num_det
      %         ph: phase in DAC units.
      if ((detid<0)||(detid>me.devinfo.num_det))
        error('detid must range 1 to %d\n', me.devinfo.num_det);
      end
      
      fprintf('cpds1000().set_gate_ph( %d %d)\n', detid, ph);
      
      [rsp errp] = me.ser.do_cmd('3');
      [rsp errp] = me.ser.do_cmd(char('1'+detid-1));
      [rsp errp] = me.ser.do_cmd(sprintf('%x\r', ph));
      [rsp errp] = me.ser.do_cmd('e'); % return to main menu
      me.settings.gate_ph(detid) = ph;
    end

    function set_dly(me, detid, dly)
    % detid: one-based
      detid = round(detid);
      corr_dly = me.settings.overall_corr_dly;
      % fprintf('CPDS1000 DBG: set_dly %d %d\n', detid, dly);
      if (~isempty(corr_dly))
        [rsp errp] = me.ser.do_cmd('2');        
	% archaic cpds does not have independent channel delays
	% in 3.6 ... 3.10 and probably earlier
        if ((detid==2)||(detid==4))
          small_dly = max(0,min(3,dly));
          [rsp errp] = me.ser.do_cmd('3');
          [rsp errp] = me.ser.do_cmd(char('0'+detid));
          [rsp errp] = me.ser.do_cmd(sprintf('%x\r', small_dly));
          me.settings.dly(detid)=small_dly;
        else
          small_dly = dly - corr_dly;
          % can we change just the "small" dly?
          if ((small_dly>=0)&&(small_dly<=3)) % we can
            [rsp errp] = me.ser.do_cmd('3');
            [rsp errp] = me.ser.do_cmd(char('0'+detid));
            [rsp errp] = me.ser.do_cmd(sprintf('%x\r', small_dly));
            me.settings.dly(detid)=dly;
          else % change overall
            [rsp errp] = me.ser.do_cmd('3');
            [rsp errp] = me.ser.do_cmd(char('0'+detid));
            [rsp errp] = me.ser.do_cmd(['0' 13]);
            [rsp errp] = me.ser.do_cmd('3');
            [rsp errp] = me.ser.do_cmd('5');
            [rsp errp] = me.ser.do_cmd(sprintf('%x\r', dly));
            d = dly - me.settings.overall_corr_dly;
            me.settings.overall_corr_dly = dly;
            me.settings.dly(detid)=dly;
            me.settings.dly(4-detid)=me.settings.dly(4-detid) + d;
          end
        end
        [rsp errp] = me.ser.do_cmd('e'); % return to main menu
      else
        dly = max(0,round(dly));
        [rsp errp] = me.ser.do_cmd('2');
        [rsp errp] = me.ser.do_cmd('3');
        [rsp errp] = me.ser.do_cmd(char('0'+detid));
        [rsp errp] = me.ser.do_cmd(sprintf('%x\r', dly));        
        [rsp errp] = me.ser.do_cmd('e'); % return to main menu        
        me.settings.dly(detid)=dly;
      end
    end



    function sweep_gate_ph_setup(me, detid, measlen)
      if ((detid<0)||(detid>me.devinfo.num_det))
        error('detid must range 1 to %d\n', me.devinfo.num_det);
      end
      me.ser.do_cmd('6');
      me.ser.do_cmd(char('0'+detid));
      me.expected.chan = detid;
      me.expected.idx = 0; % expected phase index
      me.ser.do_cmd('6'); % specify measlen in hex ("manual" entry)
      me.ser.start_cmd_accum([dec2hex(measlen) char(13)]); % entry in hex
      me.ser.read(-1,400,char(10)); % skip echo
      me.expected.ph_at_max = me.settings.gate_ph(detid);
      me.expected.cmd_started=1;
    end


    function sweep_gate_ph_done(me, set2max)
    % desc: terminates the gate sweep.  Sets phase to the setting
    %    that resulted in the largest singles count.
      if (me.expected.cmd_started)
        [~, err]=me.ser.do_cmd('E'); % esc does not always work, nor does lowcase e
        if (err==3)
          fprintf('ERR: cpds1000_class.sweep_gate_ph_done():  failed to cleanly abort\n');
        end
      end
      me.expected.cmd_started=0;
      if (~set2max)
        me.ser.do_cmd('e');
      else
        me.ser.do_cmd('m'); % maximize and exit
        me.settings.gate_ph(me.expected.chan) = me.expected.ph_at_max;
% fprintf('DBG: set gate_ph(%d) to %d\n', me.expected.chan, me.expected.ph_at_max);
      end
    end

    function [counts done errmsg] = sweep_gate_ph_meas_counts(me)
    % desc:
    %   non-blocking: if the CPDS does not respond
    %   within one second, the function returns anyway.
    % returns:
    %   counts: []: means no counts were returned yet (in non-blocking mode)
    %           1xn vector: the counts measured.
                   %        index this vector using the corrstat_id* mapping functions
    %   done: 1=done with this scan (got >).  0=not done yet
    %   errmsg: empty if no error.  Otherwise a string description of error.
      errmsg='';
      counts=[];
      [line done] = me.ser.accum_line();
      if (~isempty(line))
        if (~isempty(regexp(line,'[;>]')))
          me.expected.cmd_started=0;
          done=1;
        end
        if (strfind(line,'ERR')) % may happen if clock is lost
          errmsg=line;
          done=1;
          return;
        end
        idx = strfind(line,'@'); 
        if (~isempty(idx)) % summary line at end is like: "det# @ 0x<hex>  max=<dec> @ 0x<hex>"
          [ph_cur ct] = sscanf(line(idx(1):end),'@ 0x%x',1);
          if (ct==1)
            me.settings.gate_ph(me.expected.chan) = ph_cur;
          end
          if (length(idx)>1)
            [ph ct] = sscanf(line(idx(2):end),'@ 0x%x',1);
            if (ct==1)
              me.expected.ph_at_max = ph;
              % fprintf('DBG: expected ph_at_max 0x%x=%d\n', ph, ph);
            end
          end
          % [ph_max ct] = sscanf(line(idx(2)+4:end),'%x',1); % we dont care
        else
          % Each line is like
          % <ph_hex> ct ct ct ct ...
          % Line may have escape chars to colorize current posistion
          [ph ct e k]= sscanf(line,'%x',1); % k is nextindex
          if ((ct==1)&&(ph==me.expected.idx)&&(k<=length(line)))
            % vt100_purple is 6 chars long.  Starts with esc and ends with 'm'
            % vt100_norm   is 5 chars long.  Starts with esc and ends with 'm'
            line=regexprep(line(k:end), '\x{1B}[^m]*m', ''); % strip them!
            me.expected.idx=me.expected.idx+16;
            [counts c_l] = sscanf(line,'%d');
            counts = counts(:);
          end
        end
      end
    end



    
    function meas_counts_change_bias(me, sgn)
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_change_bias(): called before meas_counts_start()');
      end
      if (me.expected.meas_counts_active && me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts calls accum_line(), which ensures an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum(nc.util.ifelse(sgn>0,'>','<'));
      end
    end
    
    function meas_counts_change_thresh(me, sgn)
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_change_thresh(): called before meas_counts_start()');
      end
      if (me.expected.meas_counts_active && me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts calls accum_line(), which ensures an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum(nc.util.ifelse(sgn>0,'+','-'));
      end
    end
    
    function meas_counts_change_dly(me, sgn)
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_change_dly(): called before meas_counts_start()');
      end
      if (me.expected.meas_counts_active && me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts calls accum_line(), which ensures an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum(nc.util.ifelse(sgn>0,'s','a'));
      end
    end
    
    function meas_counts_change_gateph(me, sgn)
    % only do this in continuous mode
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_change_gateph(): called before meas_counts_start()');
      end
      if (me.expected.meas_counts_active && me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts calls accum_line(), which ensures an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum(nc.util.ifelse(sgn>0,'w','q'));
      end
    end
    
    function meas_counts_hold_settings(me)
    % only do this in continuous mode
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_change_gateph(): called before meas_counts_start()');
      end
      if (me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts called accum_line(), which ensured an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum(' ');
      end
    end
    
    function meas_counts_goto_noise_floor(me)
    % only do this in continuous mode
      if (~me.expected.meas_counts_active)
        error('cpds1000_class.meas_counts_goto_noise_floor(): called before meas_counts_start()');
      end
      if (me.expected.autorpt)
        if (length(me.ser.bridge_objs)>0)
          % meas_counts called accum_line(), which ensured an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        me.ser.start_cmd_accum('t');
      end
    end




    
    function declare_chans_of_interest(me, chanmsk, autorpt)
      import nc.*
      me.expected.chanmsk = chanmsk;
      me.expected.autorpt=autorpt;
      
      % fprintf('DBG: c1k:declare_chans_of_interest  x%x\n', chanmsk);
      
      if (autorpt)

        if (nc.util.bitcnt(chanmsk)~=1)
          % For now this is an error but maybe not always
          error('BUG: in autorpt for cpds1000, chanmsk must specify only one channel');
        end
        chan = nc.util.bitpos(chanmsk);
        chan_max = util.ifelse(util.ver_is_gte(me.devinfo.fwver, [5 2]),8,4);
        if ((chan<1)||(chan>chan_max))
          error(sprintf('BUG: chanmsk must specify a channel 1..%d', chan_max));
        end
        data_ids = [chanmsk bitor(chanmsk,nc.cpds_class.ACCID)];
        if (nc.util.ver_is_gte(me.devinfo.fwver, [3 16]))
          for k=1:me.devinfo.num_det
            if (k~=chan)
              data_ids =[data_ids bitset(chanmsk, k)]; % pairwise corrs
            end
          end
        elseif (nc.util.ver_is_gte(me.devinfo.fwver, [3 12]))
          for k=1:me.devinfo.num_det
            if ((k~=chan)||(chan==me.devinfo.num_det)) % this was a bug
              data_ids =[data_ids bitset(chanmsk, k)];
            end
          end
        end
        
        me.expected.data_ids = data_ids;
        me.expected.num_stats = length(data_ids);        
      else
        stats_ids=[];
        stats_dsts=[];
        if (chanmsk<4)
          % cmd='8';
          me.expected.num_stats = 6;
        elseif (chanmsk<16)
          % cmd='b';
          me.expected.num_stats = 22;
        else % use the new custom set of stats method
          % cmd='s';
	  stats_s='';
          for pci=1:8
            if (bitget(chanmsk, pci))
              stats_s    = [stats_s ' s' char('0'+pci)];
              stats_ids  = [stats_ids bitset(0,pci)];
              stats_s    = [stats_s ' ap' char('0'+pci)];
              stats_ids  = [stats_ids bitor(bitset(0,pci),cpds_class.ACCID)];
              for pci2=(pci+1):8
                if (bitget(chanmsk, pci2))
                  stats_s   = [stats_s ' c' char('0'+pci) char('0'+pci2)];
		  stats_ids = [stats_ids bitset(bitset(0,pci),pci2)];
                  stats_s   = [stats_s ' a' char('0'+pci) char('0'+pci2)];
	          stats_ids = [stats_ids bitor(bitset(bitset(0,pci),pci2),cpds_class.ACCID)];
                end
              end
            end
          end
          me.expected.stats_s = stats_s;
          me.expected.data_ids = stats_ids;
          me.expected.num_stats = length(stats_ids);
        end
        
      end
    end

    function errmsg = meas_counts_start(me, chanmsk, autorpt)
    % desc:
    %   declares the set of statistics to measure, and prepares the CPDS to
    %   to take that measurement.  To actually get the data from a measurement,
    %   call meas_counts().  Then after one or more (or zero) calls to meas_counts(),
    %   call meas_counts_stop().
    %
    %   NOTE:  Some CPDS1000 firmwares support an iteration parameter ("number of
    %   captures") to its so-called "manual mode", in which each measurement
    %   is always repeated a fixed number of times, and then it reports the
    %   total.  This feature is not supported by this API.  Instead, programs can
    %   simply iterate their calls to meas_counts() and add totals themselves.
    %   No CPDS2000 firmwares support that concept either.
    %
    % inputs:
    %   chamsk: bit vector of channels of interest. OR of corrstat for singles counts.
    %      Prepares cpds to measure all supported singles, accidentals and
    %      correlations involving those channels of interest.
    %   autorpt: 0=commence each measurement each time meas_counts() is called.
    %              In the cpds menus, this is called "manual mode"  
    %            1=start a new measurement immediately after previous one finishes.
    %              In the cpds menus, this is called "continuous mode"  
    % returns: errmsg: empty if no error.  Otherwise a string description of error.
    %
      import nc.*
      errmsg='';
      if (me.expected.meas_counts_active)
        error('BUG: you must call meas_counts_stop() before another meas_counts_start()');
      end
      if (nargin<3)
        autorpt =0;
      end

      me.abort_flag=0;
      me.expected.meas_time_s = max(0, me.settings.measlen * me.settings.clkdiv / me.settings.clkfreq_Hz * 1.25) + 0.1;
      % This sets expected.num_stats
      me.declare_chans_of_interest(chanmsk, autorpt);
      
      if (autorpt)
        if (util.bitcnt(chanmsk)~=1)
          % For now this is an error but maybe not always
          error('BUG: in autorpt for cpds1000, chanmsk must specify only one channel');
        end
        chan = util.bitpos(chanmsk);

        chan_max = util.ifelse(util.ver_is_gte(me.devinfo.fwver, [5 2]),8,4);
        if ((chan<1)||(chan>chan_max))
          error(sprintf('BUG: chanmsk must specify a channel 1..%d', chan_max));
        end
        
        me.ser.set_timo_ms(max(1,me.expected.meas_time_s)*1000+100); % a new thing. whynot?
        
        me.ser.do_cmd('5');  % continuous mode
        
        % After issuing channel num, firmwares of 3.15 and prior call det_set_pos()
        % which call wait_for_gtpsync() which can cause a 2 second delay if clock is absent.
        if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 13]))
          me.ser.start_cmd_accum(sprintf('%d', chan));
          % version 3.12 and earlier then print "press any key to start" 
          % and then wait for a key with no prompt.
          [rsp found_key met_timo] = me.ser.read(-1, 4000, 'y');
          if (met_timo)
% 'DBG: no press any key to start'
            errmsg='cpds failed to respond with "press any key"';
            return;
          end
          me.ser.start_cmd_accum(' ');
          % Now we handle this skip til x in meas_counts()
          % % The header has a damn greater than char in it! skip til x in "exit"
          % % [rsp found_key met_timo] = me.ser.read(-1, 500, 'x');
        elseif (~nc.util.ver_is_gte(me.devinfo.fwver, [3 16]))
          me.ser.do_cmd(sprintf('%d', chan));
        % The header has a damn greater than char in it! skip til x in "exit"
     %          [rsp found_key met_timo] = me.ser.read(-1, 3000, 'x');
          me.ser.start_cmd_accum(''); % resume reading          
        else
          % The header has a damn greater than char in it!
          rsp = me.ser.do_cmd(sprintf('%d', chan));
          me.ser.start_cmd_accum(''); % resume reading
%          [rsp found_key met_timo] = me.ser.read(-1, 500, 'x');
        end
%        [rsp found_key met_timo] = me.ser.read(-1, 500, char(10)); % read till EOL
%        [lbls found_key met_timo] = me.ser.read(-1, 500, char(10)); % header labels
        % skip ---- bar or in 4.1 & later skip empty line:
%        [rsp found_key met_timo] = me.ser.read(-1, 500, char(10));
        me.expected.meas_counts_active=1;
        me.expected.meas_counts_st=1;
        return;
      end
      
      % 4 = go to "Manual Mode" submenu
      me.ser.do_cmd('4');  % 0.040 s
      % Then we are offered the choice:
      %  8 - formatted output for detectors 1,2
      %  9 - formatted output for detectors 3,4
      %  b - formatted output for detectors 1,2,3,4
      %  c - stats for custom set of channels (fver 3.16+, 4.16+)
      %  s - custom set of statistics
      % an old bug had cmd='9' for num_spd=2?!!!!!
      
      if (chanmsk<4)
        cmd='8';
      elseif (chanmsk<16)
        cmd='b';
      else % use the new custom set of stats method
        cmd='s';
      end
      timo_prior_ms = me.ser.cmd_timo_ms;
      me.ser.set_timo_ms(8000);
      [rsp err]=me.ser.do_cmd(cmd); % takes .030 s.  If no clk, on old version takes longer, maybe 4s?!!
      me.ser.set_timo_ms(timo_prior_ms);
      if (cmd=='s')
        rsp = me.ser.do_cmd([me.expected.stats_s char(13)]);
        if (strfind(rsp,'ERR'))
          errmsg = sprintf('tried to read statistics "%s" but cpds reported error', stats_s);
          return;
        end
      end

      % After '8' or 'b', for some cpds firmwares, there's a 3 second warmup delay!

      % cpds ver 3.11 prompts "enter number of captures (1 to 7ffffff, default=1) > "
      me.ser.start_cmd_accum(['1' char(13)]);
	
      ver_gte_3_4 = nc.util.ver_is_gte(me.devinfo.fwver, [3 4]);
      if (~ver_gte_3_4)
        key='E'; % version 3.1&3.2 prompts "Press SPACE to Start"
      else
        % version 3.4+ prompts "press any key to continue"
        % version 3.11 prompts "press any key to continue" and there is no ">" prompt!
        % version 4.2.1+ in nomenu mode prompts "y"
        key='y'; %char(10); 
      end
      [rsp found_key met_timo] = me.ser.read(-1, 4000, key);
      if (met_timo)
        errmsg='cpds failed to respond with expected prompt';
        return;
      end

      % we used to check for the pause prompt,
      % but it's not really necessary.
      %  if (~DEVS.cpds_hwver_gte_3_4)
      %    key='E'; % version 3.1&3.2 prompts "Press SPACE to Start"
      %  else
      %    key='k'; % version 3.4+ prompts "press any key to continue"
      %  end
      %  [bytes_read found_key met_timo] = ser_skip(DEVS.cpds, 200, key);
      %  if (~found_key)
      %    msg('WARN: cpds gave bad rsp to formatted_out cmd');
      %    % fprintf(' got '); nc.uio.print_all(str);
      %  end

      % allow old cpds to warm up
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 14]))
        pause(1.0);
      end
      me.expected.meas_counts_st = 4;
      me.expected.meas_counts_active=1;
    end




    function id  = corrstat_idx2id(me, idx)
% desc: used to interpret the counts vector returned by cpds_meas_counts().
% inputs: idx: an index into the counts vector returned from cpds_meas_counts().
% chanmsk: same as what was passed to meas_counts().
% returns: id: a bit mask of the channels involved in the correlation or accidental,
%              ORed with a bit indicating whether it is a correlation or an accidental.
%
% When cpds prints correlation measuements, the cpds might be doing so in different "formats".
% for the cpds1000, the difference is when using '4' versus '8'.
% for cpds2000, difference is "corr [o]" versus "corr [o]r"
      global CPDS1000_G
      if (me.expected.autorpt)
        id = me.safeidx(me.expected.data_ids, idx);
      else
        if (isempty(CPDS1000_G)||~isfield(CPDS1000_G,'map'))
  	  nc.cpds1000_class.init_corrstat_map;
        end
        map = CPDS1000_G.map;
        chanmsk = me.expected.chanmsk;
        if (chanmsk<4)
          id = me.safeidx(map.idx2id_f2, idx);
        elseif (chanmsk<16)
          id = me.safeidx(map.idx2id_f4, idx);
        else % new custom set of stats, including remote channels
          id = me.safeidx(me.expected.data_ids, idx);
        end
      end
    end

    % both the c1k and c2k define these:
    function idx = corrstat_id2idx(me, id)
      % desc:
      %   given the id of a "correlation statistic" this returns the index
      %   of that statistic in the vector returned from meas_counts().
      % inputs
      %   id: id of a "correlation statistic". a bit mask of the
      %     channels involved in the correlation or singles count.
      %     Ored with cpds_class.ACCID if an accidental or afterpulse.
      %
      % when cpds1000 outputs correlation counts, it's one of these formats:  
      %    s_1 s_2 cc_12 ac_12 ap_1 ap_2
      %    s_3 s_4 cc_34 ac_34 ap_3 ap_4  (NOT USED!)
      %    s1 s2 s3 s4  c12 a12  c34 a34  c13 a13  c24 a24  c14 a14  c23 a23   c1234 a1234  ap1 ap2 ap3 ap4
      global CPDS1000_G

      if (me.expected.autorpt)
        idx = me.safe_find(me.expected.data_ids,id);
      else
        if (isempty(CPDS1000_G)||~isfield('CPDS1000_G','map'))
	  nc.cpds1000_class.init_corrstat_map;
        end
        map = CPDS1000_G.map;
        chanmsk = me.expected.chanmsk;
        a    = bitand(id, nc.cpds_class.ACCID);
        if (a)
          id = bitand(id, bitcmp(nc.cpds_class.ACCID));
	  if (chanmsk<4)
	    idx = me.safeidx(map.a_id2idx_f2, id);
	  elseif (chanmsk<16)
	    idx = me.safeidx(map.a_id2idx_f4, id);
          else
            error('BUG: not imp.. TODO');
	  end
        else
	  if (chanmsk<4)
	    idx = me.safeidx(map.c_id2idx_f2, id);
	  elseif (chanmsk<16)
	    idx = me.safeidx(map.c_id2idx_f4, id);
          else
            idx = me.safe_find(me.expected.data_ids,id);
	  end
        end
      end
    end


    function meas_abort(me)
      me.abort_flag=1;
    end


    % two ways.  which is best?
    % meas_counts returns after one second, regardless.  But using this is a bit awkward.
    % meas_counts potentially waits forever.  But you can call meas_counts_stop() if you are a GUI. 
    function [counts ok errmsg] = meas_counts(me)
      % desc: gets correlation statistics (corrstats) from the CPDS, or times out
      %     after one second and returns anyway.
      %   NOTE: Before calling this you must first call meas_counts_start() to declare
      %         the set of statistics you are interested in, and customize the manner in
      %          which the measurements are taken.
      % returns:
      %   counts:
      %      []: it timed out.  Happens with auto (continuous mode).  Unusual, but does not set errmsg.
      %          In this case, call meas_counts() again, or give up and call meas_counts_stop().
      %      1xn vector: measured counts
      %                  NOTE: index this vector using the corrstat_id* mapping functions
      %   errmsg: empty if no error.  Otherwise a string description of error.
      %
      % NOTE:the "4" command (manual mode) "format" chosen previously will be one of:
      %       s1 s2 c12 a12 ap1 ap2
      %       s3 s4 c34 a34 ap3 ap4  (NOT USED!)
      %       s1 s2 s3 s4  c12 a12  c34 a34  c13 a13  c24 a24  c14 a14  c23 a23   c1234 a1234  ap1 ap2 ap3 ap4
      %       s1 s2 s3 s4 c12 a12 c34 a34 c13 a13 ... and so on
      import nc.*
      errmsg='';
      ok = 1;
      if (~me.expected.meas_counts_active)
        error('BUG: meas_counts_start() must return without error before you call meas_counts()');
      end


      if (~me.expected.autorpt)
        % as a result of meas_counts_start(),
        % cpds1000 should already be in a mode such that it is waiting for any key.
        % we send it space (we could send any character) which tells
        % it to start a measurement.
        me.ser.start_cmd_accum(' ');
      end

      ver_prints_dly = nc.util.ver_is_gte(me.devinfo.fwver, [3 12]); % prints delay
      
      counts=[]; % zeros(1, me.expected.num_stats);
      done=0;
      ts = tic();
      while(~done)
        % read next line (or up to the prompt)
        [line done] = me.ser.accum_line();

        % fwv3.11: if clk is absent:
        %            continuous mode returns to main menu without err msg.  so done=1
        %            manual mode prints ERR: lost clock, still prints T=..., and does not exit.
        if (~isempty(line))

          if (strfind(line,'ERR')) % may happen if clock is lost during manual mode
            errmsg=line;
          end

          % This skips two lines after the line containing 'e = exit'.
          % Used to be done in meas_counts_start, but doing it here
          % allows us to use accum_line, which works through bridges.
          if (me.expected.meas_counts_st==1)
            if (~isempty(strfind(line,'x')))
              me.expected.meas_counts_st=2;
            end
            continue;
          elseif (me.expected.meas_counts_st<4)
            % maybe that should be <3 !!!
            me.expected.meas_counts_st=me.expected.meas_counts_st+1;
            continue;
          end
          
          if (me.expected.autorpt) % continuous mode

    % Note: in "continuous mode", If a param is inced/deced past limit, cpds1000 prints
    %   WARN: det% bias limited to x###"
    %   ERR: th over/under lim"
    % delay is silently limited, phase silently wraps

% if is rcs, bias and thresh not printed (indicated below by square brackets]
%  each line of data is : S1 AP1 pos(hex)  [bias(hex) thresh(hex)] steps(dec)
%  ver3.12              : s2 ap2 c12 c23 c24 pos(hex) dly(hex) [bias thresh] steps
            
%  ver4.4.0             : a1 ap1 c12 ph(hex) bias(hex) thresh(hex) steps(dec)
%  ver4.4               : a1 ap1 c12 c13 c14 bias(hex) thresh(hex)] steps(dec)????
%                                implemented pairwise corrs.(to num_det).
            words=regexp(line, '\S+','match');
            words_l = length(words);
            if ((words_l>1) && ~isempty(regexp(words(1),'^\d+')))
              stats_l = min(words_l, me.expected.num_stats); % there is extra stuff at end
              if (stats_l ~= me.expected.num_stats)
  	         errmsg =sprintf('cpds responded with %d stats not %d stats', ...
                                 words_l, me.expected.num_stats);
              end
              % 
              row = cellfun(@nc.cpds1000_class.safe_str2num, words);

              counts=zeros(1, me.expected.num_stats);
              counts(1:stats_l) = row(1:stats_l);

              chan = nc.util.bitpos(me.expected.chanmsk);

              % after the counts is phase in hex!

              idx = me.expected.num_stats+1;
              if (idx <= words_l)
                [n ct]=sscanf(words{idx},'%x',1);
                if (ct==1)
                  me.settings.gate_ph(chan) = n;
                end
              end
              idx = idx+1;

              if (ver_prints_dly)
                if (idx < words_l)
                  [n ct]=sscanf(words{idx},'%x',1);
                  if (ct==1)
                    me.settings.dly(chan) = n;
                  end
                end
                idx=idx+1;
              end
              
              if (~me.devinfo.is_rcs)
              % old rcs always printed bias and thresh I guess
                  
                if (idx < words_l)
                  [n ct]=sscanf(words{idx},'%x',1);
                  if (ct==1)
                    me.settings.bias(chan) = n;
                  end
                end
                idx=idx+1;
               
                if (idx < words_l)
                  [n ct]=sscanf(words{idx},'%x',1);
                  if (ct==1)
                    me.settings.thresh(chan) = n;
                  end
                end
                idx=idx+1;

              end
              return;
            end

          else % NOT autorpt.  manual mode.
            % old expected response is:
            % <20>  Pulse_1  Pulse_2   CC_12   AC_12   AfterP_ ...
            % ------------------------------------------------<20>\n\r ...
            % # # # # # #
            % T = <20># # # # # #<20>\n\r<7>
            %         
            idx=0;
            if (nc.util.ver_is_gte(me.devinfo.fwver, [3 4]))
              % in nomenu mode, manual "mode" only prints the totals line, so look ONLY for that
              % The newer CPDS prints the "T = " for all formats (no char 20?)
              % But it seems that 3.5 still puts the char 20 in there.

              line_l=length(line);
              if ((line_l>5)&&~isempty(regexpi(line, 'T =')))
                idx=5;
    	        % Some old firmwares insert a damn char(20) right after the equal sign.  skip that!
                while ((idx<=line_l) && (line(idx)<=char(' ')))
                  idx=idx+1;
                end
              end
            else
              % but apparently ATT has an old CPDS which doesn't even print the T
              % when displaying formatted output for all detectors.
              % So we find the <20> and then parse those numbers.
              idx=strfind(line,char(20));
              if (isempty(idx)) idx=0; else idx=idx(1)+1; end
            end
            if (idx)
	      [row row_l] = sscanf(line(idx:end),'%d');
  	      if (row_l>1)
                if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 3]))
                  % The 3.1 & 3.2 CPDS always put an extra useless zero
                  % at the beginning of the line of data
                  % when outputing data for 4-detector mode.
                  if ((row_l>1)&&(me.expected.num_stats==22))
                    row = row(2:end);
                    row_l = row_l-1;
                  end
                end
                counts=zeros(1, me.expected.num_stats);
                if (row_l ~= me.expected.num_stats)
	          errmsg =sprintf('cpds responded with %d stats not %d stats', ...
                                 row_l, me.expected.num_stats);
	          % uio.print_all(line);
                end
                row_l = min(row_l,me.expected.num_stats);
	        counts(1:row_l) = row(1:row_l);
                break;
              end
	    end
          end % if continuous mode
        end % line not empty
        
	if (done)
          counts=[];
          errmsg = 'cpds1000 continuous or manual mode ended abnormally.';
          me.expected.meas_counts_active = 0;
	  break;
	end
        if (toc(ts)>me.expected.meas_time_s)
          counts=[];
          break;
        end
      end  % while not done

    end

    function str=const2str(me, map_ca, const)
      for k=1:size(map_ca,1)
        if (map_ca{k,1}==const)
          str = map_ca{k,2};
          return;
        end
      end
      str = '?';
    end
      
    function errmsg = meas_counts_stop(me)
      % desc: 
      %   tells CPDS to cease measuring statistics.
      errmsg='';
      if (me.expected.meas_counts_active)
        if (me.expected.autorpt && (length(me.ser.bridge_objs)>0))
          % meas_counts called accum_line(), which ensured an unfinished remote read.
          [rsp, err] = me.ser.get_cmd_rsp('accumline');
        end
        [rsp e] = me.ser.do_cmd('E'); % Write "E" to exit to main menu
        if (e==3)
          errmsg = 'meas_counts_stop(): cpds failed to stop measuring counts';
        end
      end
      me.expected.meas_counts_active=0;
    end
    
    function fstatus = get_flink_status(me, fid)
    % see get_status().
    % This method is just here to make code compatible with cpds2000_class.m
      fstatus = me.get_status();
    end

    function ver = get_ver(me)
      if (me.fwver_is_gte([5 2]))
        me.ser.do_cmd('f');
        [rsp err] = me.ser.do_cmd('v');
        me.ser.do_cmd('e');
        sfpi.vendor = me.ser.parse_keyword_val(rsp, 'sfp0_vendor', '?');
        sfpi.model  = me.ser.parse_keyword_val(rsp, 'sfp0_model', '?');
        sfpi.sn     = me.ser.parse_keyword_val(rsp, 'sfp0_sn', '?');
        sfpi.wl_nm  = me.ser.parse_keyword_val(rsp, 'sfp0_wl_nm', 0);
        me.devinfo.sfp_ver = sfpi;
        ver = sfpi;
      end
    end
    
    function status = get_status(me)
    % desc: gets status
    % returns:
    %   status.clk1ok: whether all the PLLs associated with the clk1 input are currently locked,
    %                  during the moment in which you invoke the status command. 1=ok, 0=bad.  
    %   status.clk2ok: similar for clk2.
    %   status.clk1_bad_ctr: Each time any of the PLLs associated with the clk1 input looses lock,
    %                  this counter is incremented, up to a maximum of three.  After a get_status,
    %                  the counter is automatically cleared. If you have a bad clock, this might
    %                  provide some idea of how often the clock is bad.
    %   status.clk2_bad_ctr: similar for clk2.
      import nc.*
      [rsp errp] = me.ser.do_cmd('1');
      status.clk1ok = me.ser.parse_keyword_val(rsp, 'clk1ok', 0);
      num_clks      = me.ser.parse_keyword_val(rsp, 'num_clks', 1);
      status.clk1_bad_ctr = me.ser.parse_keyword_val(rsp, 'clk1_bad_ctr', 100);
      if (num_clks==1)
        status.clk2ok = status.clk1ok;
        status.clk2_bad_ctr = 0;
      else
        status.clk2ok = me.ser.parse_keyword_val(rsp, 'clk2ok', 0);
        status.clk2_bad_ctr = me.ser.parse_keyword_val(rsp, 'clk2_bad_ctr', 100);
      end
      status.clklock = bitor(bitshift(uint32(~~status.clk2ok),1), uint32(~~status.clk1ok)); % to be same as c2k
      status.sfp_los   = me.ser.parse_keyword_val(rsp, 'sfp_los', 0); % loss of signal indication from SFP
      % used common code sfp.c in c1k firmware so prints sfp0 not sfp1.
      status.sfp_temp_C   = me.ser.parse_keyword_val(rsp, 'sfp0_temp_C', -1);
      status.sfp_vcc_mV   = me.ser.parse_keyword_val(rsp, 'sfp0_vcc_mV', 0);
      status.sfp_rxpwr_uW = me.ser.parse_keyword_val(rsp, 'sfp0_rxpwr_uW', -1);
      status.sfp_txpwr_uW = me.ser.parse_keyword_val(rsp, 'sfp0_txpwr_uW', -1);
      status.flink_dcdsync = me.ser.parse_keyword_val(rsp, 'flink_synced', 0);
      status.flink_was_unsynced = me.ser.parse_keyword_val(rsp, 'was_unsynced', 0);

      if (~nc.util.ver_is_gte(me.devinfo.fwver, [5 2]))
        i = me.ser.parse_keyword_val(rsp, 'BER:', 500000); % ppm
        status.flink_ber_and_use = [double(i)/1e6, 0];
        i = me.ser.parse_keyword_val(rsp, 'rxing', 0);
        status.flink_rx = bitshift(util.ifelse(i,15,0),4);
        i = me.ser.parse_keyword_val(rsp, 'txing', 0);
        status.flink_tx = util.ifelse(i,15,0);
      else
        i = me.ser.parse_keyword_val(rsp, 'flink_ber', 500000); % ppm
        status.flink_ber_and_use = [double(i)/1e6, 0];
        status.flink_rx = bitshift(me.ser.parse_keyword_val(rsp, 'flink_r', 0),4);
        status.flink_tx = me.ser.parse_keyword_val(rsp, 'flink_t', 0);
      end
   
      status.cmpr_state = me.ser.parse_keyword_val(rsp, '[^d]cmpr_st ', 0);
      status.cmpr_state_str = me.const2str(me.devinfo.cmpr_state_map, status.cmpr_state);
      status.dcmpr_state = me.ser.parse_keyword_val(rsp, 'dcmpr_st ', 0);
      status.dcmpr_state_str = me.const2str(me.devinfo.dcmpr_state_map, status.dcmpr_state);      
      status.cmpr_stopreason  = me.ser.parse_keyword_val(rsp, '[^d]cmpr_stopreason', 0);
      status.cmpr_stopreason_str  = me.const2str(me.devinfo.cmpr_stopreason_map, status.cmpr_stopreason);
      status.dcmpr_stopreason = me.ser.parse_keyword_val(rsp, 'dcmpr_stopreason', 0);
      status.dcmpr_stopreason_str = me.const2str(me.devinfo.dcmpr_stopreason_map, status.dcmpr_stopreason);
      status.dcmpr_latency = me.ser.parse_keyword_val(rsp,'dcmpr_latency',0);
      status.flink_ack_latency = me.ser.parse_keyword_val(rsp,'flink_ack_latency',0);
    end

    function data = meas_tomo(me, pa1, pa1_chan, pa2, pa2_chan, wait_ms)
    % desc: takes measurements required to compute polarization-based quantum tomography
    % inputs:
    %   pa1: instance of pa1000_class
    %   pa1_chan: channel of pa1 to use
    %   pa2: instance of pa1000_class
    %   pa2_chan: channel of pa2 to use
      import nc.*                             
      pa1_basis='HHVVVVHHHHVVAADDDDAAAADDRRLLLLRRRRLL';
      pa2_basis='HVVHRLLRDAADDAADRLLRHVVHHVVHRLLRDAAD';
      n = length(pa1_basis);
      data=zeros(n,23);
      data(1:n,1)=1:n;
      pa1_p = '0';
      pa2_p = '0';
      for k=1:n
        pa1_s = pa1_basis(k);
        pa2_s = pa2_basis(k);
        if (~isempty(pa1)&& (pa1_s ~= pa1_p))
          pa1.set_tomo_state(pa1_chan, pa1_s)
        end
        if (~isempty(pa2)&& (pa2_s ~= pa2_p))
          pa2.set_tomo_state(pa2_chan, pa2_s)
        end
        if (wait_ms)
          pause(wait_ms / 1000);
        end
        data(k, 2:23) = me.meas_counts();
        pa1_p = pa1_s;
        pa2_p = pa2_s;
      end
    end

    function errmsg=maxc_start(me, dlyset, corrset, dly_start, dly_end)
      % desc: starts a search for maximal correlations by delaying one or more correlator channels.
      %       after this, call maxc_accum repeately, and/or maxc_abort.
      % corrset: a vector of correlation statistic IDs you wish to maximize
      % dlyset: integer.  bitmask of correlator channels to delay.  All specified channels
      %         will be set to the same delay, from dly_start to dly_end, for each measurement
      % dly_start: starting delay in units of gate periods.
      % dly_end: ending delay in units of gate periods.

      errmsg='';
      corrset_l = length(corrset);
      me.expected.maxc_st=0;
      me.expected.idxs=zeros(1,corrset_l);

      me.expected.corrset_strs = cell(corrset_l,1);
      for k=1:corrset_l
        me.expected.corrset_strs{k} = me.corrstat_id2str(corrset(k));
      end
      me.expected.bestcorrs=zeros(corrset_l, 4);
      me.expected.sawcorr=zeros(corrset_l, 1);

      if (me.devinfo.dly13_only)
        % old retarded cpds
        ok_corrs = [3 9 12 6]; % [c(1,2) c(1,4) c(3,4) c(2,3)];
        for k=1:corrset_l
          idx =find(corrset(k)==ok_corrs,1);
          if (~idx)
	    errmsg=sprintf('correlation %s not available in this cpds', me.expected.corrset_strs{k});
            return;
          end
          me.expected.idxs(k)=idx; % index in resp of corrset(k)
        end

        if (isempty(dlyset) || (dlyset ~= 5)) % c(1,3)
	  errmsg='This cpds can only search by varying delays 1 and 3 together';
          return;
        end

        me.ser.do_cmd('a'); % a = scan dly
        dly_start = floor(dly_start/16)*16; % Stupid code aligns start delay!
        me.ser.do_cmd(sprintf('%x\r', dly_start));
        me.ser.start_cmd_accum(sprintf('%x\r', dly_end));

        me.expected.maxc_st=2;
        me.expected.maxc=1;

      else

        c_str = repmat(char(' '), 1, 32);
        c_l=0;
        for k=1:corrset_l
          str = me.expected.corrset_strs{k};
          str_l = length(str);
          if (c_l)
            c_l=c_l+1;
            c_str(c_l)=char(' ');
          end
          c_str(c_l+(1:str_l))=str;
          c_l=c_l+str_l;
        end
        c_str=c_str(1:c_l);
        d_str='d';
        l=1;
        for pci=1:me.devinfo.num_corr_chan
          if (bitget(dlyset,pci))
           l=l+1;
            d_str(l)=char('0'+pci);
          end
        end

        cmd = [c_str(1:c_l) ' ' d_str sprintf(' %d %d\r', dly_start, dly_end)];
        me.ser.do_cmd('m'); % m = maxc command
        % fprintf("usage: (c###)* (d###) start end\r\n");
        me.ser.start_cmd_accum(cmd);
        me.expected.maxc_st=1;
        me.expected.maxc=1;
      end
      dlys_l=dly_end-dly_start+1;
      me.expected.dly=dly_start;
      me.expected.corrs_l=0;
      me.expected.corrs=zeros(dlys_l,1+corrset_l); % first col is dly
      me.expected.best_corr=zeros(corrset_l,1);
      me.expected.best_corr_idx=zeros(corrset_l,1);
    end

    function [done rsp errmsg] = maxc_abort(me)
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 12]))
        me.ser.write('e');
      else
        me.ser.write(' ');
      end
    end

    function [done res errmsg] = maxc_accum(me)
% res: may be [].  Otherwise it's Nx4 and it's an update.
%         Each row for each correlation,
%         and columns are:   dly  maxcnt accid CAR
      if (~me.expected.maxc_st)
        error('maxc_start not called or failed when it was called.  You must check return status from maxc_start()');
      end
      rsp='';
      errmsg='';
      ts=tic();
      corrstats_l = length(me.expected.idxs);
      corrset_l = length(me.expected.corrset_strs);
 
      while(1)
      [line done] = me.ser.accum_line();
      if (~isempty(line))
        if (~isempty(regexpi(line, 'ERR')))
          errmsg=line;
          break;
        elseif (me.expected.maxc_st==1)
          if (line(1)=='%') % we rxed the header.
            me.expected.maxc_st=3;
          end
        elseif (me.expected.maxc_st==2)
          if (line(3)=='c')
            me.expected.maxc_st=3;
          end
        else

          if (~me.devinfo.dly13_only)

            flds = regexp(line, '\S+', 'match');
            % expect %     stat    dly    max  accid    car\r\n");
            flds_l=length(flds);
            if ((flds_l>4) && (flds{1}(1)=='c'))
              for k=1:corrset_l
                if (strcmp(me.expected.corrset_strs{k}, flds{1}))
                  me.expected.sawcorr(k)=1;
                  for kk=2:flds_l
                    me.expected.bestcorrs(k,kk-1)=sscanf(flds{kk},'%g',1);
                  end

%                  me.expected.bestcorrs(k,:)

                  break;
                end
              end
            end

          else % if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 12]))
            % Our archaic cpds 1000
            if (~isempty(regexpi(line, 'corr_dlys '))) % ending summary
              [v ct]=sscanf(line(10:end),'%d');
              if (ct==5)
                me.settings.dly=v(2:5).' + [1 0 1 0]*v(1);
              end
            else
              [v ct]=sscanf(line,'%d');
              % ignore empty line or main menu
              if (ct==4)
                fprintf('%d: %d %d %d %d\n', me.expected.dly, v);

                me.expected.corrs_l=me.expected.corrs_l+1;
                idx = me.expected.corrs_l;

                me.expected.corrs(idx,1)=me.expected.dly;
                for ci=1:corrstats_l
                  corr=v(me.expected.idxs(ci));
                  me.expected.corrs(idx,ci+1)=corr;
                  if (~me.expected.best_corr_idx(ci) || (corr>me.expected.best_corr(ci)))
                    me.expected.best_corr(ci)=corr;
                    me.expected.best_corr_idx(ci)=idx;
                  end
                end
                me.expected.dly = me.expected.dly +1;
              end
            end
          end

        end
      end
      if (done || (toc(ts)>2))
        break;
      end

      end % while(1)

      if (~me.devinfo.dly13_only)
        if (~all(me.expected.sawcorr))
          res=[];
        else
          res=me.expected.bestcorrs;
        end
      else

        if (me.expected.corrs_l<2)
          res=[];
        else
          res=zeros(corrstats_l, 3);
          for ci=1:corrstats_l
            idx = me.expected.best_corr_idx(ci);
            if (idx>0)
              res(ci,1)=me.expected.corrs(idx,1); % dly
              res(ci,2)=me.expected.best_corr(ci);
              res(ci,3)=mean(me.expected.corrs((1:me.expected.corrs_l)~=idx,1+ci));
              res(ci,4)=me.expected.best_corr(ci) / res(ci,3);
            end
          end
        end
      end
      if (done)
        me.expected.maxc_st=0;
      end
    end

    function set_flink_tx(me, fid, flink_tx)
      flink_tx = bitand(flink_tx, 15);
      me.ser.do_cmd('f');       
      me.ser.do_cmd('t');
      me.ser.do_cmd([num2str(flink_tx) char(13)]);
      me.ser.do_cmd('e');
      me.settings.flink_tx = flink_tx;
    end
      

    function err = set_dcmpr_latency(me, latency_cycs)
     % desc: sets the decompressor latency.  When the RCS first receievs
     %     channel data from a remote RCS, it waits for this delay and then
     %     begins decompressing it.
     % latency_cycs: decompressor latency in units of sampling cycles.
      me.ser.do_cmd('f');
      me.ser.do_cmd('l');
      [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', round(latency_cycs)));
      if (~isempty(m) && ~err)
        me.settings.dcmpr_latency = m(1);
      end
      me.ser.do_cmd('e'); 
    end
      

  
    function settings = get_settings(me)
    % desc: querries cpds1000 for its current settings.  Returns those settings in settings structure.
    %       Also sets instance member me.settings to this.  Note that settings are automatically queried
    %       every time device is opened.
    % returns: settings.  See comment in instance member section.
      [rsp err] = me.ser.do_cmd('1');
      me.devinfo.is_fallback=((err==3)&& (length(rsp)<16));

      me.settings.masklen  = me.ser.parse_keyword_val(rsp, 'mask[^=]*', 1);
      me.settings.clkdiv   = me.ser.parse_keyword_val(rsp, 'clk div', 1);
      me.settings.flink_in_use = 1;

      me.settings.free_run_always  = me.ser.parse_keyword_val(rsp, 'free_run', 0);
      
%      [sidxs, eidxs] = regexpi(rsp, 'gate pulses [^=\n]*');
%     fprintf('DBG: found %s\n', rsp(sidxs(1):eidxs(1)));

      % v3.11: "gate pulses per capture = %d\r\n", cfg.pulses_per_capture);
      % v4.2:  "gate pulses per measurement = %s\r\n", 
      me.settings.measlen  = me.ser.parse_keyword_val(rsp, 'gate pulses [^=\n]*', 1);

      me.settings.simsig = me.ser.parse_keyword_val(rsp, 'simsig_thresh', 0)/(2^14-1);

      if (me.fwver_is_gte([3 12]))
        str = me.ser.parse_keyword_val(rsp,'chan_src','');
        ca = regexp(str, '\S+', 'match');
      else
        str = me.ser.parse_keyword_val(rsp,'correlator inputs:','');
        % str is in the form in1=det1 in2=det2 in3=det3 in4=det4
        ca = regexp(str, '\S+', 'match');
        for k=1:length(ca)
          ca{k}=regexprep(ca{k}, '.*=', '');
        end
      end
      me.settings.chansrc=cell(8,1);
      for chanid=1:4
        if (chanid<=length(ca))
          str = ca{chanid}(1);
          % old firmwares indicated ch3,4 chansrc "d" for two-detector CPDSs!
          if (~nc.util.ver_is_gte(me.devinfo.fwver, [5 2]))
            if ((str=='d')&&(chanid>2)&&(me.devinfo.num_det<=2))
              str='0'; % fix the lie
            end
          end
          me.settings.chansrc{chanid}=str;
        else
          me.settings.chansrc{chanid}='0';
        end
      end
      for chanid=5:8 % The rest are not settable.  Always remote.
        me.settings.chansrc{chanid}='f';
      end
      me.settings.chansrc_fid=[0 0 0 0 1 1 1 1];
      me.settings.chansrc_r_ch=[0 0 0 0 1 2 3 4];
        
      me.settings.num_clks = me.ser.parse_keyword_val(rsp, 'num_clks', 1);
      me.settings.bias     = zeros(1,me.devinfo.num_chan);
      me.settings.thresh  = zeros(1,me.devinfo.num_chan);
      me.settings.gate_ph = zeros(1,me.devinfo.num_chan); % base zero
      me.settings.clkfreq_Hz = 50e6;
      me.settings.refclk_Hz = 0;
      me.settings.flink_cmpr_pwr = me.ser.parse_keyword_val(rsp, 'rle_pwr', 7);
      me.settings.flink_max_baud_Hz = 2.0e9;
      me.settings.flink_actual_baud_Hz = 2.0e9;
      me.settings.flink_ref_Hz = 50e6;
      me.settings.dcmpr_latency = me.ser.parse_keyword_val(rsp, 'dcmpr_latency', 0);
      me.settings.flink_tx = me.ser.parse_keyword_val(rsp, 'flink_t', 0);
      for chanid=1:me.devinfo.num_chan
	str = regexpi(rsp, ['det' char('0')+chanid ':[^\n\r]*[\n\r]'],'match','once');

        me.settings.bias(chanid)    = me.ser.parse_keyword_val(str,'bias',0);
	me.settings.thresh(chanid)  = me.ser.parse_keyword_val(str,'thresh',0);
	me.settings.gate_ph(chanid) = me.ser.parse_keyword_val(str,'pos',0);

      end
      me.expected.pending_clk_bad_ctrs(1) = me.expected.pending_clk_bad_ctrs(1) ...
                                            +  me.ser.parse_keyword_val(rsp, 'clk1_bad_ctr', 100);
      if (me.settings.num_clks==1)
        status.clk2_bad_ctr = 0;
      else
        me.expected.pending_clk_bad_ctrs(2) = me.expected.pending_clk_bad_ctrs(2) ...
                                            +  me.ser.parse_keyword_val(rsp, 'clk2_bad_ctr', 100);
      end

      corr_dly = me.ser.parse_keyword_val(rsp, 'correlator delay', []);
      me.settings.overall_corr_dly = corr_dly;
      if (~isempty(corr_dly))
	% archaic cpds does not have independent channel delays
	% in 3.6 ... 3.10 and probably earlier
	me.settings.dly = [corr_dly 0 corr_dly 0];
	% 3.7, 3.8, 3.9, 3.10, 3.11 has per chan "small dly"
	idx = strfind(rsp,'small dly');
	if (~isempty(idx) && (idx+9 < length(rsp)))
	     [v ct] = sscanf(rsp(idx+9:end), '%d');
	  me.settings.dly(1:ct) = me.settings.dly(1:ct) + v.';
	end

      else
	% 3.12, 3.13 
	idx = strfind(rsp,'corr dly');
	if (~isempty(idx) && (idx+8 < length(rsp)))
	  [v ct] = sscanf(rsp(idx+8:end), '%d');
	  me.settings.dly(1:ct) = v;
        else
     	  me.settings.dly = [0 0];
	end
      end
      settings = me.settings;
    end
    
    function set_refclk_Hz(me, f_Hz)
    end

    function set_clkfreq_Hz(me, f_Hz)
    end

    function err = set_simsig(me, prob)
    % desc: sets the probability of a simulated "count"
    %       for the "simulation signal".  The "simulation signal" is generated
    %       from an LFSR in the VHDL, and can be used as the "source" for channels
    %       1 through 4 using the set_chansrc() method.
    % inputs:
    %      prob: a double 0..1
      [rsp errp] = me.ser.do_cmd('2');
      [rsp errp] = me.ser.do_cmd('x');
      lat = round(prob * (2^14-1));
      [rsp errp] = me.ser.do_cmd(sprintf('%x\r', lat));
      [rsp errp] = me.ser.do_cmd('e');      
      me.settings.simsig = lat / (2^14-1);
    end
    
    function set_freerun(me, en)
      if (en)
        if (me.expected.freerun)
          error('already freerunning!');
        end
        me.ser.do_cmd('7');
        me.ser.do_cmd(' ');
        me.expected.freerun=1;
      else
        if (~me.expected.freerun)
          error('not freerunning!');
        end
        me.ser.do_cmd(' ');
        me.expected.freerun=0;
      end
    end


    function ca = bridge_params_cmd(me, chan, params)
      % returns cell array of strings of cmd that sets these params
      ca={};
    end
    function cmd = bridge_flush_cmd(me, chan)
      cmd = '';  % TODO: there is no flush cmd!
    end
    
    function cmd = bridge_idn_cmd(me, chan)
      % fprintf('DBG: cpds.bridge_get_idn\n');
      if (nc.util.ver_is_gte(me.devinfo.fwver,[5 2]))
        cmd = 'q';
      else
        cmd = '';
      end
    end
    
    function names = bridge_chan_list(me)
      if (nc.util.ver_is_gte(me.devinfo.fwver,[5 2]))
        names={'f1'};
      else
        names={};
      end
    end
    function name = bridge_chan_idx2name(me, chan)
      % chan: 1-based index
      names=me.bridge_chan_list();
      if (chan>length(names))
        name='';
      else
        name=names{chan};
      end
    end
    
    function cmd = bridge_cmd(me, chan, cmd)
      if (~nc.util.ver_is_gte(me.devinfo.fwver,[5 2]))
        error('BUG:c1k.bridge_cmd(chan) not supported for this fw');
      end
      if (length(chan)>1)
        error('BUG: c2k.bridge_cmd(chan) size chan>1');
      end
      cmd = strrep(cmd, '\',      '\134'); % encode \
      cmd = strrep(cmd, char(13), '\015'); % encode cr
      cmd = strrep(cmd, char(62), '\076'); % encode >
      cmd = sprintf('r %s\r', cmd);
    end
    
    function rsp = bridge_rsp(me, chan, rsp)
      % could verify local echo, but for now just strip it
      % todo: DECODE
      rsp = me.backslash_code2plain(rsp);
    end

    function [cmd ncmds] = bridge_timo_cmd(me, chan, timo_ms)
      % fprintf('DBG: %s bridge_timo %d ms\n', ser.dbg_alias, timo_ms);
      cmd = sprintf('fo%d\re', timo_ms);
      ncmds=4;
    end
    
    function [cmd ncmds] = bridge_set_term_cmd(me, chan, term_char)
      % fprintf('DBG: %s bridge_timo %d ms\n', ser.dbg_alias, timo_ms);
      cmd = sprintf('fc%d\re', double(term_char));
      ncmds=4;
    end
    
  end

  
end
