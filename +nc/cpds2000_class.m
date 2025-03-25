% SHOULD make gui_cpds2000_class that extends this!!!

% cpds2000_class.m
% NuCrypt Proprietary
% Matlab API for cpds2000

%   cpds.settings: structure of current settings of device. automatically read when device opened.
%      settings.measlen  integer  The number of gate pulses over which one measurement (of correlation statistics) is taken.
%                                 The temporal duration of one measurement will be measlen*clkdiv/clkfreq
%      settings.masklen: 1x4 vector. Per-channel duration of afterpulse masking. 1024=RZ
%      settings.clkdiv: The downsampling rate.  The front-panel clock frequency is divided by the clkdiv to determine the gate frequency.
%      settings.bias: 1xn vector  indexed by detector id.  APD bias in dac units.
%      settings.dly: 1xn vector.  indexed by correlator channel.  The post-downsampling delay for each correlator channel
%      settings.gate_ph: 1xn vector  indexed by detector id.   Each detector’s gate phase in DAC units.
%      settings.thresh: 1xn vector indexed by detector or channel id. Each detector's compartor threshold in DAC units
%      settings.num_clks: integer How many front panel clock inputs are being used.  1 means  front panel clock 1 is used
%                                 for all detectors, 2 means clk1 is used for detectors 1 and 3 while clock2 is used for detectors
%                                 2 and 4. 
%      settings.clkfreq_Hz: integer
%      settings.refclk_Hz: [r0 r1] where r is 0=internal, 1=flink0 2=flink1, other=Hz
%      settings.chansrc{}: cell array indexed by channel number.  Contains strings.
%                          Possible channel sources are one of devinfo.possible_chansrcs{chan}
%      settings.chansrc_fid:  vector indexed by channel number.  Contains "fids".
%                          An "fid" is the 1-based flink index.  0 means does not apply.
%                          An RCS can have multiple flinks.

% Notes on "bridging" (see also notes in ser_class.m)
%
%   An RCS can connect to up to two other "flinks", which connect to remote RCSs.
%   An RCS can also connect to two other "serlinks", which typically connect to PAs.
%   Whoever controls (sends commands to) this local RCS can control these other devices
%   by using "bridging".
%
%   Suppose an RCS is connected by "serlink" to a PA, but the PA has no other
%   connections.  Only the RCS is connected to the PC.  Software instantiates
%   the cpds2000_class.  Then it instantiates a pa1000_class object while
%   describing how it's connected.  That first there is an RCS, and there's a
%   "serlink" to the PA.  From then on, software
%   invokes the usual methods on that PA object, such as pa.set_waveplates_deg().
%   The pa1000_class knows that it's bridged, but that class does not contain
%   the code to do the "bridging".  It sends its usual commands to ser_class().
%   ser_class knows that first it must bridge through an RCS.  So it encapsulates
%   the PA command and sends it to the RCS.  The response is de-encapsulated,
%   and returned to the pa1000 class object.
%
%   The description of connection is a described by three vectors:
%        bridge_objs   - vector of device objects (such as cpds2000)
%        bridge_chans  - vector of numbers.  device specific "bridge channels"
%        bridge_params - device specific parameters
%
%   As of 5/26/2023, we added the second "flink" to the RCS.
%   So we had to re-number the bridging channels for the RCS.  Now they are:
%         0 - flink 0
%         1 - flink 1
%         2 - serlink 0
%         3 - serlink 1



classdef cpds2000_class < nc.cpds_class

  properties (Constant=true)
  end

  % instance members
  properties
    port
    baud
    dbg_lvl  % 0=none, 1=debug cpds reads
    ser
    idn
    devinfo
    %      devinfo.hwver: hardware version.  1xn vector of integers
    %      devinfo.fwver: firmware version.  1xn vector of integers
    %      devinfo.num_det  : number of detectors in this CPDS. typically 0,2,or 4
    %      devinfo.num_chan : number of "channels"
    %      devinfo.num_corr_chan : number of correlator channels. typically 4 or 8
    %      devinfo.con = 's'; describes communication ports available on this CPDS/RCS
    %               's'=std (for cpds) meaning no flink, 'c'=flink connectivity (std for RCS)
    %      devinfo.ser: type of serial links. 'x'=none, 's'=one serial link, '2'=two serial links
    %      devinfo.can_set_refclk: whether you can set the reference frequency. 0=cant, 1=can
    %      devinfo.dly13_only = 0; 1=archaic CPDS can only delay chans 1 and 3.  0=can dly all
    %      devinfo.num_thresh : number of analog thresholders.  Typically 4.
    %      devinfo.is_rcs : 0=rcs (does correlation only), 1=cpds (has detectors)
    %      devinfo.has_rxlpm_rst: Features bug workaround for rather old firmware version
    %      devinfo.has_t_cmd = 0; % cpds1000 only
    %      devinfo.has_timebin_mode: whether can correlate delayed version of same channel
    %      devinfo.has_maxc_cmd = 0:

    settings
  end
  
  properties (Access = private)
    cpds2000_exe % path to executable. string.  Not used with RCS. only with cpds2000
    ini_vars     % vars loaded cpds2000 config file.  Not used with RCS
    st           % structure containing various state maintained by this class
    % To do long measurements, we repeat over meas_num_itr times
    %    st.meas_num_itr:
    %    st.meas_itr:
    %    st.meas_accum_data:
    %    st.meas_accum_ok:
    %    st.meas_len_per_itr:
    %    st.meas_len_remainer:
  end
  
  properties (Constant=true)
    IDN_HW_VARIATION_NOLEDBOARD  = uint32(1);
    IDN_HW_VARIATION_RXINV       = uint32(2);
    IDN_HW_VARIATION_CANREADTEMP = uint32(4);
    IDN_HW_VARIATION_SPIDLYDIN   = uint32(8);
    IDN_HW_VARIATION_HASSFP      = uint32(32);
    IDN_HW_VARIATION_HASSERIAL   = uint32(64);
    IDN_HW_VARIATION_SPDTHRESH   = uint32(128);
  end

  
  methods (Static=true)
    % matlab "static" methods do not require an instance of the class


    function str = chan_idx2str(idx)
    % idx: channel index base 1, which is the matlab "way".
      str=sprintf('%d',idx-1);
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
    %      devinfo.num_det  = 2;
    %      devinfo.num_chan = 2;
    %      devinfo.num_corr_chan = 2;
    %      devinfo.con = 's'; % std
    %      devinfo.ser = 's'; % std
      import nc.*
      flds   = regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      model=0;
      if (num_flds>=2)
        model = parse_word(flds{2}, '%d', model);
      end

      devinfo = idn; % inherit what was already parsed

      for_fwver = [2 9 0];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: cpds2000_class(): This software was written for CPDS/RCS firmwares %s and below\n', util.ver_vect2str(for_fwver));
        fprintf('      but %s is has firmware %s and might not work with this +nc package\n', ...
                devinfo.name, util.ver_vect2str(devinfo.fwver));
      end

      
      % default CPDS
      devinfo.num_det  = 2;
      devinfo.num_chan = 2;
      devinfo.num_corr_chan = 2;
      devinfo.num_dly      = 2;
      devinfo.con = 's'; % std
      devinfo.ser = 's'; % std
      devinfo.can_set_refclk = 0;
      devinfo.can_set_clkfreq = 0;
      devinfo.can_set_outclk = 0;
      devinfo.num_flink = 0;
      devinfo.can_set_flink_baud = 0;
      devinfo.dly13_only = 0;
      devinfo.masklens = [0 4 7 15 23 31 39 47 55 63 1024]; % possible masklens

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
      
      if (3<=num_flds) % C1
        devinfo.num_det = parse_word(flds{3}, '%d', 2);
      end
      devinfo.num_thresh    = devinfo.num_det;
      devinfo.num_chan      = devinfo.num_det;
      devinfo.num_corr_chan = devinfo.num_det;
      devinfo.num_dly     = devinfo.num_det;
      devinfo.is_rcs = (devinfo.num_chan==0);
      if (devinfo.is_rcs)
	devinfo.num_thresh = 4;
        devinfo.num_chan = 4;
        devinfo.num_corr_chan = 4;
        devinfo.num_dly  = 4;
      end
      devinfo.has_rxlpm_rst = ~nc.util.ver_is_gte(devinfo.fwver, [2 0]);
      devinfo.has_t_cmd = 0; % cpds1000 only
      devinfo.has_timebin_mode = nc.util.ver_is_gte(devinfo.fwver,[1 31]);
      devinfo.has_maxc_cmd = 0; % this is supported by cpds2000.exe
      devinfo.can_set_refclk = nc.util.ver_is_gte(devinfo.fwver,[2 0]);
      devinfo.can_set_clkfreq = nc.util.ver_is_gte(devinfo.fwver,[2 0]);
      devinfo.can_set_outclk  = nc.util.ver_is_gte(devinfo.fwver,[2 5]);
      devinfo.refclk_can_be_rxclk = nc.util.ver_is_gte(devinfo.fwver,[2 7]);
      devinfo.has_simsig = 1;
      devinfo.has_free_run_always = 0; % this is a cpds1000 thing.
      devinfo.has_txrx_rdy_indic = nc.util.ver_is_gte(devinfo.fwver,[2 8]);
      devinfo.can_readback_patterns = nc.util.ver_is_gte(devinfo.fwver,[2 9]);
      
      % True for 2.6 but not earlier maybe
      wdly_w = [16 13 16 13];
      devinfo.dly_max = 2.^(wdly_w+3)-1;
      devinfo.dly_max(5:8)=0;
      
     % I'm not sure of this.  True, flink was introduced in 1.25
      % but it seems to me that the c2 test is the correct thing to do.
%      if ((fw_ver(1)>1)||fw_ver(2)>=25)
%        devinfo.num_chan=8;
%      end
      if (4<=num_flds); % C2
        devinfo.con = lower(flds{4}(1));
      end

      % This WILL be updated later by a call to get_ver():
      % This is the ocde-to-string mapping for channel sources on channels 1-4
      devinfo.ver_chansrcs = {'d' 's' 'l' 'u4' 'u2' 'p0' 'p1'};
      
      devinfo.possible_chansrcs=cell(8,1);
      % TODO: really this ought to use ver_chansrcs and be done later in get_ver
      for k=1:4
        if (nc.util.ver_is_gte(devinfo.fwver, [2 6]))
          devinfo.possible_chansrcs{k} = {'d' 's' 'p0' 'p1'};
        else
          devinfo.possible_chansrcs{k} = {'d' 's'};
        end
      end
      for k=5:8
        devinfo.possible_chansrcs{k} = {};
      end
      
      if (devinfo.con=='c')
        devinfo.num_corr_chan = 8;
        devinfo.num_flink = 1 + nc.util.ver_is_gte(devinfo.fwver,[2 7]);
        devinfo.can_set_flink_baud = nc.util.ver_is_gte(devinfo.fwver,[2 7]);
      end
                      
      if (5<=num_flds) % C3
        devinfo.ser = flds{5}(1);
      end

      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
         v = default;
        end
      end
      
    end

    function init_corrstat_map()
      global CPDS2000_G;
      import nc.*
      map=[];
      % cpds2000 correlation statistic mappings
      map.idx2id=zeros(1,15+6);
      map.c_id2idx=zeros(1,64);
      map.a_id2idx=zeros(1,64);

      idx=1;
      for id=1:15 % local sings and corrs
	map.idx2id(idx)=id;
	map.c_id2idx(id)=idx;
	idx=idx+1;
      end
      for id=3:15 % local accid pairs
	if (util.bitcnt(id)==2)
	  % fprintf('map %d %d\n', idx, bitor(id, cpds_class.ACCID));
	  map.idx2id(idx)=bitor(id, cpds_class.ACCID);
	  map.a_id2idx(id)=idx;
	  idx=idx+1;
	end
      end
      for pci=5:8 % remote sings
	id = uint32(2^(pci-1));
	map.idx2id(idx)=id;
	map.c_id2idx(id)=idx;
	idx=idx+1;
      end
      for pci2=5:8
	for pci1=1:4
	  id = bitset(bitset(0,pci1),pci2);
	  map.idx2id(idx)=id;
	  map.c_id2idx(id)=idx;
	  idx=idx+1;
	end
      end
      for pci2=5:8
	for pci1=1:4
	  id = bitset(bitset(0,pci1),pci2);
	  map.idx2id(idx)=bitor(id, cpds_class.ACCID);
	  map.a_id2idx(id)=idx;
	  idx=idx+1;
	end
      end
      % fprintf('map.idx2id(%d)=%d\n', 16, map.idx2id(16));
      CPDS2000_G.map = map;
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
	  str = [str '0'+pci-1];
	end
      end
    end
    
    % STATIC    
    function dst = backslash_plain2code(src)
      dst=strrep(src, '\', '\\');
      dst=strrep(dst, char(13), '\r');
      dst=strrep(dst, char(27), '\033');
      dst=strrep(dst, '>', '\076');
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

  methods (Access = private)

    function str = private_pat_m2str(me, bitlen, m)
      k=1;
      str=repmat('0',1,bitlen);
      for str_i=1:bitlen
        if (mod(str_i,8)==1)
          if (k>length(m))
            fprintf('BUG: cpds200.private_pat_m2str() called with bad matrix\m');
            n = uint8(0);
          else
            n = uint8(m(k));
            k=k+1;
         end
        end
        str(str_i)=bitget(n,8)+'0';
        n=bitshift(n, 1);
      end
    end
    
    function [cmd rsp_len] = private_meas_counts_start_cmd(me, chanmsk, autorpt)
      import nc.*
      cmd = nc.util.ifelse(autorpt,'corr ','corr o');
      if (~(nc.util.ver_is_gte(me.devinfo.fwver,[1 25])))
        rsp_len = 15 + 6;
      elseif (chanmsk < 16)
	rsp_len = 15 + 6 + 3;
      else
	rsp_len = 15 + 6 + 4 + 16 + 16 + 3;
        cmd = [cmd 'r']; % include remote stats
      end
      me.st.meas_time_s = max(0, me.settings.measlen * me.settings.clkdiv / me.settings.clkfreq_Hz * 1.25)+0.1;
    end

    function measlen = set_measlen_ll(me, measlen)
      % Note: if you do sprintf('%d',2500000000)) matlab prints 2.5e9!!!!!
      %   And this %ld only works up to 1.0e18.
      [m err] = me.ser.do_cmd_get_matrix(sprintf('measlen %ld\r', measlen));
      if (length(m)==1)
        measlen = m;
        me.st.measlen_ll = m;
      else
        fprintf('ERR: cpds2000_class.set_measlen(%ld)', measlen);
        fprintf('     bad rsp from cpds\n');
        measlen = me.st.measlen_ll; % presume unchanged
      end
    end
    
  end
  
  methods

    function b=fwver_is_gte(me, ver)
      import nc.*
      b = nc.util.ver_is_gte(me.devinfo.fwver, ver);
    end
    
    % CONSTRUCTOR
    function me = cpds2000_class(arg1, opt)
      % desc: constructor
      % use:
      %   obj = cpds2000_class(ser, opt)
      %           ser: an open ser_class object
      %   obj = cpds2000_class(port, opt)
      % inputs: port: windows port name that cpds is attached to. a string.
      %         opt: optional structure. optional fields are:
      %           opt.dbg: 0=normal, 1=print all low level IO
      %           opt.baud: baud rate to use
      %           opt.cpds2000_exe: full pathname to cpds2000.exe utility. a string.
      %                    used to invoke the utility to run *.c2k scripts,
      %                    and to read the cpds2000.ini and calibration file.
      %                    Not needed for an RCS.  If empty, no effect.
      import nc.*
      if (nargin<2)
        opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'baud', 115200);
      opt = util.set_field_if_undef(opt, 'cpds2000_exe', ...
				    'C:\nucrypt\rcs2000\bin\cpds2000.exe'); % default
      me.cpds2000_exe = opt.cpds2000_exe; % seldom if ever used
      me.ini_vars = []; % read later if at all
      %      me.abort_flag=0;
      me.settings.flink_tx = 0; % dflt for older rcs fw
      me.settings.dcmpr_latency = 0; % dflt for older rcs fw
      me.st.measlen_ll = 0; % means unknown
      
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.idn = me.ser.idn;
        me.open();
      elseif (ischar(arg1))
        me.ser=nc.ser_class(arg1, opt.baud, opt);
        me.idn = [];
        me.open();
      else
        error('first param must be portname or ser_class');
      end

      me.st.chanmsk=15;
      me.st.autorpt=0;
      me.st.meas_counts_active=0;
      me.st.meas_hist_active=0;
      me.st.cmd_started = 0;
      %      me.st.echo_stripped = 0;
      
      if (~me.ser.isopen())
        'DBG: ck2 constructor not open yet!'
        return;
      end

      if (me.devinfo.con=='c')
        me.set_rtimo_ms(2000);
      end

      % computed expected values for this fwver/variation
      if (nc.util.ver_is_gte(me.devinfo.fwver,[1 25]))
        me.st.rsp_len = 15 + 6 + 3;
        me.st.retry_lim = 1;
      else
        me.st.rsp_len = 15 + 6;
        me.st.retry_lim = 4;
      end	
    end % constructor

    % DESTRUCTOR
    function delete(me)
      if (me.ser.isopen())
        me.close;
      end
      me.ser.delete;
    end

    function close(me)
    % desc: closes the cpds. you can re-open it with cpds2000_class.open()
      if (me.ser.isopen())
        %consider: consider issuing i to restore menus.  EPA gui used to do that.
	me.ser.close;
      end
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end
    
    function bool = isopen(me)
      bool = me.ser.isopen();
    end

    function err = open(me, portname, opt)
    % cpds2000_class.open()
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
    % returns:
    %   err: 0=opened, 1= not opened
      import nc.*
      err = 0;
      just_did_open=0;
      if (nargin<2)
        portname='';
        opt.dbg=0;
      elseif (nargin==2)
        if (isstruct(portname))
          opt=portname;
          portname='';
        else
          opt.dbg=0;
        end
      end
      if (~me.ser.isopen())
        me.ser.open(portname, opt);
        just_did_open=1;
      end
%      me.abort_flag=0;
      if (~me.ser.isopen())
	err = 1;
        return;
      end
      if (just_did_open || isempty(me.idn))
        me.ser.get_idn_rsp();
      end
      me.idn = me.ser.idn;
      me.devinfo = me.parse_idn(me.idn);
      if (me.devinfo.num_flink==2)
        fstatus = me.get_flink_status(2);
        if (~fstatus.moddet)
          me.devinfo.num_flink=1;
        end
      end
      
      ca=cell(1,me.devinfo.num_flink);
      for k=1:me.devinfo.num_flink
        ca{k}=sprintf('flink%d', k-1);
      end
      for k=5:8
        me.devinfo.possible_chansrcs{k}=ca;
      end
      
      me.get_ver();
      me.get_settings;
      if (me.settings.flink_cmd_term ~=62)
        me.set_cmd_term(62);
      end
      me.reset_flink_io(0);
    end


    function ca = bridge_params_cmd(me, chan, params)
      % returns cell array of strings of cmd that sets these params
      ca={};
      if (chan<3) % fiberlink
      else % serlink
        s=nc.util.ifelse(chan>3,sprintf('ser%d',chan-3),'ser');
        if (isfield(params,'baud_Hz'))
          ca{end+1}=sprintf('%s b %d\r', s, params.baud_Hz);
        end
        if (isfield(params,'parity'))
          ca{end+1}=sprintf('%s p %d\r', s, params.parity);
        end
        if (isfield(params,'xon_xoff_en'))
          ca{end+1}=sprintf('%s x %d\r', s, params.xon_xoff_en);
        end
      end
    end

    function cmd = bridge_flush_cmd(me, chan)
      if (chan<3) % fiberlink
        cmd = '';  % TODO: there is no flush cmd!
      elseif (chan==3) % serlink
        cmd = sprintf('ser f\r');
      else
        cmd = sprintf('ser%d f\r', chan-3);
      end
    end
    function names = bridge_chan_list(me)
      names={'f0';'f1';'s0';'s1'};
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
    
    function cmd = bridge_idn_cmd(me, chan)
    % chan: 1-based index      
    % fprintf('DBG: cpds.bridge_get_idn\n');
      explicit_cr = nc.util.ver_is_gte(me.devinfo.fwver, [2 7 0]);      
      if (chan==1) % flink 0
        if (explicit_cr)
          cmd = sprintf('r i\\r\r');
        else
          cmd = sprintf('r i\r');
        end
      elseif (chan==2) % flink 1
        if (explicit_cr)        
          cmd = sprintf('r1 i\\r\r');
        else
          cmd = sprintf('r1 i\r');
        end
      elseif (chan==3) % serlink
        cmd = sprintf('ser i\r');
      else
        cmd = sprintf('ser%d i\r', chan-3);
      end
    end

    function cmd = bridge_cmd(me, chan, cmd)
% NOTE: in epa.m version 1.22, it would use ['ser ' str]. perhaps a bug.
% Because cpds v 1.25 was when I introduced the "ser" cmd,
% and it always took a "c" for commands and did not skip a space.
    %      me.st.echo_stripped = 0;
      explicit_cr = nc.util.ver_is_gte(me.devinfo.fwver, [2 7 0]);
      if (length(chan)>1)
        error('BUG: c2k.bridge_cmd(chan) size chan>1');
      end
      if (chan==1) % fiberlink
        if (explicit_cr)
          cmd = sprintf('r %s\r', me.backslash_plain2code(cmd));
        else
          cmd = sprintf('r %s', cmd);
        end
        return;
      elseif (chan==2) % fiberlink 1
        if (explicit_cr)
          cmd = sprintf('r1 %s\r', me.backslash_plain2code(cmd));
        else
          cmd = sprintf('r1 %s', cmd);
        end
        return;
      end
      
      % we've always used backslash encoding for serlinks.
      cmd = me.backslash_plain2code(cmd);
      if (chan==3) % serlink
        cmd = sprintf('ser c%s\r', cmd);
      else
        cmd = sprintf('ser%d c%s\r', chan-3, cmd);
      end
    end

    function rsp = bridge_rsp(me, chan, rsp)
      % could verify local echo, but for now just strip it
    %      if (~me.st.echo_stripped)
        % Why would bridge_rsp ever get called twice?  In case bridging through two cpdss? but then
        % there would be two separate objects each with their own echo_stripped var.
        idx=find(rsp==char(10),1);
        if (isempty(idx))
          rsp='';
          return;
        end
        rsp = rsp(idx(1)+1:end);
        % fprintf('DBG: strip to %d\n', idx(1)+1);
        %        me.st.echo_stripped = 1;
        %      else
        %        error('DBG: echo stripped. how is this possible?');
        %      end
      if (me.fwver_is_gte([2 7 0]))
        % version 2.6 did not use backslash encode
        rsp=me.backslash_code2plain(rsp);
      end
    end

    function [cmd ncmds] = bridge_timo_cmd(me, chan, timo_ms)
      % fprintf('DBG: %s bridge_timo %d ms\n', ser.dbg_alias, timo_ms);
      if (chan<3) % fiberlink
        cmd = sprintf('rtimo %d\r', timo_ms);
      elseif (chan==3) % serlink
        cmd = sprintf('ser t %d\r', timo_ms);
      else
        cmd = sprintf('ser%d t %d\r', chan-3, timo_ms);
      end
      ncmds=1;
    end
    
    function reset_flink_io(me, fid)
      if (me.fwver_is_gte([2 8]))
        me.ser.do_cmd(sprintf('flink R %d\r', fid));
      end
    end
    
    function set_cmd_term(me, ch_ascii)
    % desc: sets termination character used when parsing response from remote rcs.
    %    used by the "r" command.
    % input: ch_ascii - ascii value of character
      if (me.fwver_is_gte([2 8]))
        me.ser.do_cmd(sprintf('flink k %d\r', ch_ascii));
        me.settings.flink_cmd_term = ch_ascii;
      end
    end
    
    function [cmd ncmds] = bridge_set_term_cmd(me, chan, term_char)
      key = double(term_char);
      if (chan<3) % fiberlink
        if (me.fwver_is_gte([2 8 0]))
          cmd = sprintf('flink k %d\r', double(term_char));
        else
          cmd = ''; % cannot change!
        end        
      elseif (chan==3) % serlink
        cmd = sprintf('ser k %s\r', me.backslash_plain2code(term_char));
      else
        cmd = sprintf('ser%d k %s\r', chan-3, me.backslash_plain2code(term_char));
      end
      ncmds=1;
    end
    
    function fn = lookup_calibration_fname(me)
    % This is seldom if ever used anymore.
      if (isempty(me.ini_vars))
        c2k_bin = fileparts(opt.cpds2000_exe);
        c2k_top = fileparts(c2k_bin);
        cpds2000_ini = fullfile(c2k_top, 'config\cpds2000.ini');
        if (exist(cpds2000_ini, 'file'));
  	  fprintf('DBG: reading %s\n', cpds2000_ini);
          me.ini_vars = vars_class(cpds2000_ini);
        end
      end
      fn='';
      if (~isempty(me.ini_vars))
        fn = me.ini_vars.get('cal_fname','');
      end
    end

    
    function err = run_cpds2000_exe_c2k_script(me)
    % This is seldom if ever used anymore.
      err=0;
      op = me.ser.isopen;
      if (op)
        me.close;
      end
      if (isempty(me.cpds2000_exe))
        fprintf('\nWARN: cpds2000_class.run_cpds2000_exe_c2k_script()\nPath to cpds2000.exe was undelcared in call to constructor\n');
        err=1;
      elseif (~exist(me.cpds2000_exe, 'file'));
        fprintf('\nWARN: cpds2000_class.run_cpds2000_exe_c2k_script()\n   %s does not exist\n', cpds2000_ini, me.cpds2000_exe);
        err=1;        
      else
        [stat res] = system([me.cpds2000_exe ' -r fin'], '-echo');
        if (stat)
          fprintf('\nERR: cpds2000_class.run_cpds2000_exe_c2k_script(me)\n');
          fprintf('    system call to cpds2000.exe failed\n');
          res
          err=1;
          return;
        end
      end
      if (op)
        me.open;
      end
    end
    

    function set_nomenu(me, nomenu)
      % desc: does not apply
    end

    function set_dsamp_ph(me, dsamp_ph_cycs)
    %  inputs:
    %    dsamp_ph_cycs: zero based. in units of cycles. range 0 to clkdiv-1.
      dsamp_ph_cycs=mod(dsamp_ph_cycs, me.settings.clkdiv);
      me.ser.do_cmd(sprintf('pbin %d\r', dsamp_ph_cycs));
      me.settings.dsamp_ph = dsamp_ph_cycs;
    end

    function rxlpm_rst(me)
      if (me.devinfo.has_rxlpm_rst)
        me.ser.do_cmd(['lpmreset' char(13)]);
      end
    end

    function set_rtimo_ms(me, rtimo_ms)
      % desc: sets timeout for "r" commands
      me.ser.do_cmd(sprintf('rtimo %d\r', rtimo_ms));
    end

    
    function set_measlen(me, measlen)
      % desc: sets the measurement length in units of optical pulses
      %       updates settings.measlen, which might be different
    % inputs: measlen: measurement length in units of optical pulses. whole.
      measlen = round(double(measlen));
      len_per_itr = me.set_measlen_ll(min(1250000000, measlen));
      num_itr = ceil(measlen / len_per_itr);
      me.st.meas_num_itr=num_itr;
      me.st.meas_itr=1;
      if (num_itr == 1)
        me.st.meas_len_per_itr = len_per_itr;
        me.st.meas_len_remainder = 0;
        me.settings.measlen = len_per_itr;
        return;
      end
      % we must do multiple iterations
      len_per_itr = ceil(measlen / num_itr);
      if (len_per_itr ~= me.st.measlen_ll)
        len_per_itr = me.set_measlen_ll(len_per_itr); % try a balanced division
      end
      %      remainder = mod(measlen, len_per_itr);
      remainder=0;
      if (remainder)
        remainder = me.set_measlen_ll(remainder); % ensure it can be implemented
        len_per_itr = me.set_measlen_ll(len_per_itr); % set it back
        me.settings.measlen = len_per_itr * (num_itr-1) + remainder;
      else
        me.settings.measlen = len_per_itr * num_itr;
      end
      me.st.meas_len_per_itr = len_per_itr;
      me.st.meas_len_remainder = remainder;
    end

    
    function err = set_dcmpr_latency(me, latency_cycs)
     % desc: sets the decompressor latency.  When the RCS first receievs
     %     channel data from a remote RCS, it waits for this delay and then
     %     begins decompressing it.
     % latency_cycs: decompressor latency in units of sampling cycles.
      latency_cycs = round(latency_cycs);
      [m err] = me.ser.do_cmd_get_matrix(sprintf('flink l %d\r', latency_cycs));
      if (isempty(m))
        me.settings.dcmpr_latency = latency_cycs;
      else
        me.settings.dcmpr_latency = m(1);
      end
    end
    
    function err = set_simsig(me, probs)
    % desc: sets the probability of a "dark count" and a "light count"
    %       for the "simulation signal".  The "simulation signal" is generated
    %       from LFSRs in the VHDL, and can be used as the "source" for channels
    %       0 through 3 using the set_chansrc() method.
    %    WARN: "light count" is only relevent if clkdiv>=8.
    % inputs:
    %      probs: a 1x2 matrix [dk lt] where dk is the simulated dark countprobability,
    %             and lt is the simulated light count probability.
    % sets:
    %      cpds.settings.simsig=[dk lt] whern dk and lt are the *actual*
    %             effective probabilities being implemented.
      import nc.*
      if (me.settings.clkdiv<8)
        probs(2)=0;
      end
      [m err] = me.ser.do_cmd_get_matrix(nc.uio.short_exp(sprintf('simsig %e %e\r', probs(1), probs(2))));
      if (length(m)==2)
        me.settings.simsig = m;
      end
    end
    
    function err = set_chansrc(me, ch, src_str, remote_ch)
    % desc:
    %   sets the "source" for the channel (specified by obj_ch).
    %   Not all sources are supported for all firmwares.  Remote
    %   sources from fiberlink are not possible if the link is down.
    %   So if the requested change cannot be made, no change is done,
    %   and this function returns err=1.
    % usage:
    %   cpds.set_chansrc(ch, src_str);
    %   cpds.set_chansrc(ch, src_str, remote_ch);
    % inputs:
    %   ch: the channel (1 based) to change.
    %   src_str: name of the source. a string. One of these "base" names:
    %      d = local detector (for CPDS), or front-panel input (for RCS)
    %      s = simulation signal
    %      l = lfsr
    %      p0 = pattern 0
    %      p1 = pattern 1
    %      flink0 = fiberlink 0
    %      flink1 = fiberlink 1
    %      0  = zeros
    %   remote_ch: optional double.  Used only when src_str specifies
    %              one of the fiberlinks.  This is the 1-based channel
    %              on the remote device.
    % returns:
    %   err=1: nothing changed.
    %   err=0: means success, and changes made to:
    %            me.settings.chansrc(ch) = src_name
      err=1;
      if (src_str(1)=='f')
        ca=regexp(src_str,'\d*\>','match');
        n=0;
        if (~isempty(ca))
          [fid n]=sscanf(ca{1},'%d',1);
        end
        if (n==1)
          fid=fid+1;
        else
          fid=1;
        end
        me.settings.chansrc_fid(ch)=fid;
        return; % for now!
      end
      code = me.chansrc_str2code(src_str);
      if (code>=0)
        [m err] = me.ser.do_cmd_get_matrix(sprintf('chansrc %d %d\r', ch-1, code));
        if (length(m)<1) % early versions no rsp
          me.settings.chansrc{ch}=me.chansrc_code2str(code);
        else % as of fwv 2.7.0:
          me.settings.chansrc{ch}=me.chansrc_code2str(m(1));
        end
        err=0;
      end

    end
    
    function set_pattern(me, pat_i, pat_str)
    % desc: sets a pattern
    % inputs: pat_i: one-based pattern index.  1 or 2.
    %         pat_str: string of 0's and 1's.
      pat_i_str=sprintf('p%d',pat_i-1);
      if (~any(cellfun(@(x) strcmp(x,pat_i_str), me.devinfo.ver_chansrcs)) ...
          || (pat_i<1) || (pat_i>length(me.devinfo.patlens)))
        fprintf('ERR: cpds2000_class.set_pattern(): pattern %d not implemented by firmware\n', pat_i);
        return;
      end
      if (~isempty(regexp(pat_str,'[^01]')))
        fprintf('ERR: cpds2000_class.set_pattern(): pat_str must contain only chars 0 and 1\n');
        return;
      end
      len_bits=length(pat_str);
      if ((len_bits<1)||(len_bits>me.devinfo.patlens(pat_i)))
        fprintf('ERR: cpds2000_class.set_pattern(): pattern length must range 1 to %d\n', ...
                me.devinfo.patlens(pat_i));
        return;
      end

      % form cmd
      cmd = sprintf('cfg pat %d %d\r', pat_i-1, len_bits);
      s_i=1; % src in pat_str
      byte=0;
      d_i=8; % dest in byte
      while(1)
        byte = bitset(byte, d_i, pat_str(s_i)=='1');
        s_i=s_i+1;
        d_i=d_i-1;
        if ((d_i<1)||(s_i>=len_bits))
          d_i=8;
          cmd = [cmd sprintf('x%02x\r', byte)];
          byte=0;
          if (s_i>=len_bits)
            break;
          end
        end
      end
      me.settings.pattern{pat_i}=pat_str;
      me.ser.do_cmd(cmd);
    end  
      
    function set_clkdiv(me, clkdiv)
      % desc:  updates settings.clkdiv, which might be different
      [m err] = me.ser.do_cmd_get_matrix(sprintf('clkdiv %d\r', round(clkdiv)));
      if (~nc.util.ver_is_gte(me.devinfo.fwver,[1 25]))
	me.settings.clkdiv = clkdiv;
      else
        % only fwver 1.25 & up respond with effective clkdiv.
	if (length(m)==1)
	  me.settings.clkdiv = m;
	else
          fprintf('ERR: cpds2000_class.set_clkdiv(%d)', clkdiv);
          fprintf('     bad rsp from cpds\n');
	end
      end
    end
    
    function set_outclk_Hz(me, f_Hz)
      % desc: sets frequency of front-panel output clocks      
      if (me.devinfo.can_set_outclk)
        [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg outclk %d\r', round(f_Hz)));
        if (~err && length(m==1))
          me.settings.outclk_Hz = m;
        end
      end
    end


    function set_num_clks(me, num_clks)
      num_clks = round(num_clks);
      if (nc.util.ver_is_gte(me.devinfo.fwver,[2 0]))
        num_clks=min(2,max(1,num_clks));
        me.ser.do_cmd(sprintf('cfg numclks %d\r', num_clks));
        me.settings.num_clks = num_clks;
      else
        me.settings.num_clks = 2;
      end
    end
    
    function set_refclk_Hz(me, ref_Hz)
    % desc: declares reference source for the two main sampling clock domains (clk0 and clk1)
    %       (Note: clk0 is used for inputs 0 and 2, while clk1 is used for inputs 1 and 3)
    % inputs: ref_Hz: a 1x2 vector or a scalar.
    %                 If a scalar, sets both references to be the same.
    %                 Otherwise, the first number is for clk0, the second for clk1.
    %                 The coding is:
    %                    0 = Use internal reference
    %                    1 = recover from flink 0
    %                    2 = recover from flink 1
    %                    other = frequency in Hz of ref0_in or ref1_in.
      ref_Hz = round(ref_Hz);
      if (length(ref_Hz)==1)
        ref_Hz(2)=ref_Hz;
      end
      if (nc.util.ver_is_gte(me.devinfo.fwver, [2 7 0]))
        [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg ref %d %d\r', ref_Hz));
        if (~err && length(m==2))
          me.settings.refclk_Hz = m;
        end
      elseif (me.devinfo.can_set_refclk)
        [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg ref %d\r', ref_Hz(1)));
        if (~err && (length(m==1)))
          me.settings.refclk_Hz = [m m];
        end
      end
    end

    function set_clkfreq_Hz(me, f_Hz)
      % desc: sets the main samping frequency, which is contrained to
      %       be a rational factor of whatever reference (internal or external)
      %       is being used.
      if (nc.util.ver_is_gte(me.devinfo.fwver,[2 0]))
        [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg clkfreq %d\r', round(f_Hz)));
        if (~err && length(m==1))
          me.settings.clkfreq_Hz = m;
        end
      end
    end

    function set_masklen(me, chan, masklen)
    % desc: sets the mask length in units of optical pulses.
    %       updates settings.masklen, which might be different
    % inputs:
    %   chan: channel 1..8 (one-based)
    %   len: mask length in units of gates.  1024 or INF means mask til return-to-zero
      if ((chan<1)||(chan>8))
        error(sprintf('cpds2000_class.set_maskeln(%d,%d): chan must range 1..8',chan,masklen));
      end
      if (chan>4)
        return;
      end
      if (isinf(masklen))
        masklen=1024; % RZ
      end
      [mn idx ] = min(abs(round(masklen)-me.devinfo.masklens));
      ml = me.devinfo.masklens(idx);
      if (masklen && ~ml)
        ml = me.devinfo.masklens(min(length(me.devinfo.masklens),idx+1));
      end
      
      [m err] = me.ser.do_cmd_get_matrix(sprintf('masklen %d %d\r', chan-1, ml));
      if (~nc.util.ver_is_gt(me.devinfo.fwver, [1 25 0]))
        % NOTE: only fwver 1.25 & up respond with effective masklen
        me.settings.masklen(chan)=ml;
      else
        if (~err && length(m==1))
          me.settings.masklen(chan)=m;
        else
          err=1;
        end
      end
      if (err)
        fprintf('ERR: cpds2000_class.set_masklen(%d)', masklen);
        fprintf('     bad rsp from cpds\n');
      end
    end

    function set_outfunc_ll(me, arg)
      if (isempty(arg))
        me.ser.do_cmd(['cfg outfunc' char(13)]);
        me.settings.outfunc = '';
      else
        me.ser.do_cmd(['cfg outfunc x' arg char(13)]);
        me.settings.outfunc = ['x' arg];
      end
    end

    function set_outfunc_remap(me, detchans)
    % desc: remaps detector channels 0..3 to correlator channels 0..3
    % detchans: 1x4 array of detector channels. index is corr chan+1
      arg=char(zeros(1,16));
      for k=0:15
        n=0;
        for cc=1:4 % correlator channel is cc-1
          if (bitget(k,detchans(cc)+1))
            n = bitset(n,cc);
          end
        end
        if (n<10)
          arg(k+1)='0'+n;
        else
          arg(k+1)='a'+n-10;
        end
      end
      me.set_outfunc_ll(arg);
    end

    function set_bias(me, detid, bias)
    % desc: sets detector bias (for CPDS, not RCS)
    % inputs: detid: one-based
    %         bias: dac value
      detid = round(detid);
      bias = round(bias);
      [rsp err] = me.ser.do_cmd(sprintf('bias %d %g\r', detid-1, bias));
      me.settings.bias(detid)=bias;
    end
    
    function set_thresh_mV(me, detid, mV)
    % desc: sets sampling Voltage threshold in mV units
      me.set_thresh(detid, me.thresh_mV2dac(detid, mV));
    end
    
    function set_thresh(me, detid, thresh)
    % desc: sets sampling Voltage threshold in DAC units
    % inputs:
    %   detid: one-based
    %   thresh: dac units
      detid = round(detid);
      thresh = max(round(thresh), 0);

      % GUI stuff:
      if (me.st.meas_counts_active)
        error('delete this code');
        if (me.st.cmd_started)
          me.ser.do_cmd(char(13));
        end
      end
      
      [rsp err] = me.ser.do_cmd(sprintf('thresh %d %g\r', round(detid-1), thresh));
      me.settings.thresh(detid)=thresh;

      % GUI stuff:
      if (me.st.meas_counts_active)
        error('delete this code');        
        if (me.st.cmd_started)
        [cmd rsp_len] = me.private_meas_counts_start_cmd(chanmsk, me.st.autorpt);
          me.st.rsp_len = rsp_len;
          me.ser.start_cmd([cmd 13]);
          me.st.cmd_started=1;
        end
      end
    end

    function set_dly(me, chanid, dly)
    % desc: sets channel delay
    % inputs:
    %   chanid: one-based channel id.
    %   thresh: dac units
    % chanid: one-based
      chanid = round(chanid);
      dly = max(0,round(dly));
      [m err] = me.ser.do_cmd_get_matrix(sprintf('dly %d %d\r', round(chanid-1), dly));
      if (me.fwver_is_gte([2 7])) % response added in fwv 2.7
        if (~err && (length(m)==1))
          me.settings.dly(chanid)=m;
        else
          fprintf('ERR: cpds2000_class.set_dly(%d)', dly);
          fprintf('     bad rsp from cpds\n');
        end
      else
        me.settings.dly(chanid)=dly;
      end
    end

    function ns = dly_dac2ns(me, dac)
      ns = 1e9*dac/me.settings.clkfreq_Hz;
    end
    
    function dac = dly_ns2dac(me, ns)
      dac = round(ns/1e9*me.settings.clkfreq_Hz);
    end

    function set_dll_en(me, chanid, en)
      chandid = round(chanid);
      if ((chanid>=1)&&(chanid<=4))
        en = ~~en;
        [rsp err] = me.ser.do_cmd(sprintf('dll %d %d\r', chanid-1, en));
        me.settings.dll(chanid)=en;
      end
    end
    
    function set_dinph_dac(me, chanid, dac)
      chandid = round(chanid);
      dac = round(dac);
      if (~me.fwver_is_gte([2 8]))
        dac = min(max(dac,0),31);
      end
      [m err] = me.ser.do_cmd_get_matrix(sprintf('dinph %d %d\r', chanid-1, dac));
      if (me.fwver_is_gte([2 8])) % response added in fwv 2.8
        if (~err && (length(m)==1))
          me.settings.dinph(chanid)=m;
        end
      else
        me.settings.dinph(chanid) = dac;
      end
    end
    
    
    function set_dinph_ps(me, chanid, ps)
      me.set_dinph_dac(chanid, me.dinph_ps2dac(chanid, ps));
    end
    
    function set_gate_ph(me, detid, ph)
    % desc: set gate phase (for CPDS, not RCS)
      detid = round(detid);
      ph = round(ph);
      [rsp err] = me.ser.do_cmd(sprintf('gate %d p %d\r', round(detid-1), ph));
      me.settings.gate_ph(detid)=ph;
    end

    function set_minrpd_s(me, minrpd_s)
    % desc: Sets the period (in units of seconds) of automatic resisual miminization
    %       or any sort of periodic software maintenance stuff if applicable.
    %       zero disables it
      minrpd_s=round(minrpd_s);
      [rsp err] = me.ser.do_cmd(sprintf('cfg minrpd %d\r', minrpd_s));
      me.settings.minrpd_s = minrpd_s;
    end

    
    function minr_all(me)
      if (nc.util.ver_is_gte(me.devinfo.fwver,[1 31]))
        [rsp err] = me.ser.do_cmd(sprintf('minr a\r'));
      end
    end

    function err = set_timebin_mode(me, en, use_remote)
      if (~me.devinfo.has_timebin_mode)
        err=1;
        return;
      end
      me.ser.do_cmd(sprintf('timebin %d %d\r', en, use_remote));
      me.settings.timebin_mode = [en use_remote];		    
      err=0;
    end
    
    function meas_hist_start(me, chanid)
    % Desc: starts up auto-repeating histographic mode.
    %       As soon as one histogram is collected, the data is returned,
    %       and firmware immediately starts collecting the next histogram      
    %       You call this, then call meas_hist() multiple times,
    %       then call meas_hist_stop().
      import nc.*
      cmd = sprintf('hist %d',chanid-1);
%      me.fwver_is_gte([1 25])
      me.st.autorpt=1;
      me.st.meas_hist_active=1;
      me.st.hist_len_expect = 1+me.settings.clkdiv + me.fwver_is_gte([1 25])*3;
%      me.st.hist_len_expect = 1+me.settings.clkdiv + 3;
      me.ser.start_cmd_accum([cmd 13]);

    end
    
    function [data, done, errmsg] = meas_hist(me, chanid)
    % desc:
    %    measures real-time histogram of singles counts.
    %    If you call this by itself (without first calling meas_hist_start)
    %    it will take one histogram and return it.  If it returns done=1,
    %    you don't need to call meas_hist_stop().
    % returns:
    %    data: 1xclkdiv vector of accumulated histographic data
    %          or [] if not all data recieved yet after one second (a timeout)
    %                in which case, call meas_hist() again, or if you want to give up,
    %                call meas_hist_stop().
    %    done: 0=not done, 1=auto-repeating histographic mode is done.
    %      
    %   TODO: instead of 1 sec, calc reasonable timeout based on freq & clkdiv.
    %         or allow caller to specify timeout. (gui might use shorter timo).
    %         This ought not return "done". Maybe premature prompt returns errmsg.
    %
      if (~me.st.meas_hist_active)
        me.st.autorpt=0;
        me.st.meas_hist_active=1;
        me.st.hist_len_expect = 1+me.settings.clkdiv + me.fwver_is_gte([1 25])*3;
        me.ser.start_cmd_accum(sprintf('hist %d o\r', chanid-1));
      end
      done=0;
      errmsg='';
      data=[];
      ts=tic();
      [l, done] = me.ser.accum_line();
      if (~isempty(l))
        [d cnt]=sscanf(l, '%g');
        if (me.dbg_lvl==1)
          fprintf('DBG: rd cpds %s: ', me.devinfo.sn);
          nc.uio.print_all(l);
        end
        if (cnt) 
          if (cnt~=me.st.hist_len_expect)
            % just drop it!
            % msg = sprintf('unexpected rsp len %d', cnt);
            % fprintf('\n\nunexpected rsp len %d', cnt);
            % nc.uio.print_all(l);
            % d=d(1:me.st.hist_len_expect);
          else
            data=d;
          end
        end
      end
      if (done)
        me.st.meas_hist_active = 0;
      end     
    end
    
    function errmsg = meas_hist_stop(me)
      errmsg='';
      % fprintf('stop. cmd_started=%d  ser.done=%d\n', me.st.meas_hist_active, me.ser.done);
      if (me.st.meas_hist_active)

        [~, err] = me.ser.do_cmd(char(27));
        if (err)
          errmsg = 'could not stop histogram normally';
        end
        % TODO: This should clean up by parsing until >.  And even that could
        % time out, in which case return ERR I suppose
        me.st.meas_hist_active = 0;
      end
    end




    function declare_chans_of_interest(me, chanmsk, autorpt)
      me.st.chanmsk = chanmsk;
      me.st.autorpt = autorpt;
    end
    
    function errmsg = meas_counts_start(me, chanmsk, autorpt)
    % cpds.MEAS_COUNTS_START()
    % cpds.MEAS_COUNTS_START(chanmsk)
    % cpds.MEAS_COUNTS_START(chanmsk, autorpt)
    % desc:
    %   Declares the set of statistics to measure, and prepares the CPDS to
    %   to take that measurement.  To actually get the data from a measurement,
    %   call meas_counts().  Then after one or more (or zero) calls to meas_counts(),
    %   call meas_counts_stop().
    % inputs:
    %   chamsk: bit vector of channels of interest. This is the bitwise OR of
    %      corrstat ids for the singles counts on those channels.
    %      Prepares cpds to measure all supported singles, accidentals and
    %      correlations involving those channels of interest.
    %      If omitted, the default is to measure the first four channels.
    %   autorpt: 0=commence each measurement each time meas_counts() is called.
    %            1=automatically start a new measurement immediately after previous one finishes.
    %      If omitted, the default is autorpt=0
    % returns: errmsg: empty if no error.  Otherwise a string description of error.
    %    If there is an error, you don't need to call meas_counts_stop.      
      errmsg='';
      me.st.chanmsk=chanmsk;
      if (nargin<2)
        chanmsk = 16;
      end
      if (nargin<3)
        autorpt=0;
      end
      
      me.st.autorpt = autorpt;
      me.st.cmd_started = 0;
      me.st.ignore_corr_ok = (chanmsk<16);
      me.st.corr_ok_idx = 15 + 6 + 4 + 16 + 16 + 1;
      if (autorpt) % start now
        [cmd rsp_len] = me.private_meas_counts_start_cmd(chanmsk, autorpt);
        me.st.rsp_len = rsp_len;
        me.ser.start_cmd_accum([cmd 13]);
        me.st.cmd_started = 1; % means expecting a response followed by ">"
      end
      me.st.meas_counts_active=1;
    end

    function id = corrstat_idx2id(me, idx)
% desc: used to interpret the counts vector returned by cpds_meas_counts().
% inputs: idx: an index into the counts vector returned from cpds_meas_counts().
% chanmsk: same as what was passed to meas_counts().
% returns: id: a bit mask of the channels involved in the correlation or accidental,
%              ORed with a bit indicating whether it is a correlation or an accidental.
%
% When cpds prints correlation measuements, the cpds might be doing so in different "formats".
% for the cpds1000, the difference is when using '4' versus '8'.
% for cpds2000, difference is "corr [o]" versus "corr [o]r"
%
% The cpds class takes care of sending the proper command, but you have to tell
% it the set of channels you are interested in.
% so far for the cpds2000, idx2id is same regardless of format.
% It's just that one format is longer the other
      global CPDS2000_G
      if (isempty(CPDS2000_G)||~isfield(CPDS2000_G,'map'))
	nc.cpds2000_class.init_corrstat_map();
      end
      map = CPDS2000_G.map;
      chanmsk = me.st.chanmsk;
      if (chanmsk<16)
        l = 15+6;
      else
        l = length(map.idx2id);
      end
      if ((idx<1) || (idx > l))
        id = 0;
      else
	id = map.idx2id(idx);
      end
    end

    
    function idx=hist_id2idx(me, id)
      % returns: one-based index within a line of histographic data
      %          corresponding to specified id.  1=bin1, 2=bin2, 3=bin3, etc.
      %          or id is one of cpds.HISTID_*
      %          0 if does not exist
      idx = 0;
      if ((id>=1) && (id<=me.settings.clkdiv+2))
        idx=id+1;
      else
        switch(id)
          case me.HISTID_RESID
            idx=1;
          case me.HISTID_OK
            idx = me.fwver_is_gte([1 25]) * (me.settings.clkdiv+2);
          case me.HISTID_FLINK_BER
            idx = me.fwver_is_gte([1 25]) * (me.settings.clkdiv+3);
          case me.HISTID_FLINK_USAGE
            idx = me.fwver_is_gte([1 25]) * (me.settings.clkdiv+4);
        end
      end
    end
    
    function idx=corrstat_id2idx(me, id)
      global CPDS2000_G
      if (isempty(CPDS2000_G)||~isfield(CPDS2000_G,'map'))
	nc.cpds2000_class.init_corrstat_map();
      end
      map = CPDS2000_G.map;
      chanmsk = me.st.chanmsk;
      if (bitand(id, nc.cpds_class.ACCID))
        id = bitand(id, bitcmp(nc.cpds_class.ACCID));
        if (id>length(map.a_id2idx))
          idx=0;
        else
	  idx = map.a_id2idx(id);
        end
      else
        if (id > length(map.c_id2idx))
          idx=0;
        else
  	  idx = map.c_id2idx(id);
        end
      end
    end


    function [data ok errmsg] = meas_counts(me)
    % [data ok errmsg] = cpds.MEAS_COUNTS()
    % desc: returns measured statistics from the cpds.
    %       You must have previously specified the statistics of interest
    %       by calling cpds.meas_counts_start().
    % returns:
    %   counts: 1xn vector of counts
    %           (index this vector using the corrstat_id* mapping functions)
    %           [] means timed out.  If so, call meas_counts() again.
    %   ok: 1=all counts valid, 0= not all counts valid, possibly due to
    %       corruption of data received over fiberlink for "remote" channels.
    %   errmsg: empty if no error.  Otherwise a string description of error.
    %      
    %   NOTE: retries if corr_ok=0
      errmsg='';
      
      chanmsk=me.st.chanmsk;

      if (~me.st.autorpt && ~me.st.cmd_started)

        % Note: for now, remainder is always zero.  I didn't bother because
        % we cant change meslen_ll during autorpt.
        if (me.st.meas_itr==1)
          if (me.st.measlen_ll~=me.st.meas_len_per_itr)
            set_measlen_ll(me, me.st.meas_len_per_itr);
          end
        elseif ((me.st.meas_itr==me.st.meas_num_itr)&&(me.st.meas_len_remainder>0))
          if (me.st.measlen_ll~=me.st.meas_len_remainder)
            set_measlen_ll(me, me.st.meas_len_remainder);
          end
        end
        
        [cmd rsp_len] = me.private_meas_counts_start_cmd(chanmsk, me.st.autorpt);
        me.st.rsp_len = rsp_len;
        me.ser.start_cmd_accum([cmd 13]);
        me.st.cmd_started=1;
      end
      ts=tic();
      
      ok=0;
      aborted=0;

      data=[];
      done = ~me.st.cmd_started; % i guess
      while(~done)

        % accumline may timeout before me.st.meas_time_s for long measlen
        % which is why this is in a while loop.
        % fprintf('c2k accum line\n');
	[l, done] = me.ser.accum_line();
        me.st.cmd_started = ~done;

        if (~isempty(l))
          [d cnt]=sscanf(l, '%g');
          if (cnt==me.st.rsp_len)
            % nc.uio.print_all(l);
            % fprintf('c2k got data\n');
            if (me.dbg_lvl==1)
              fprintf('DBG: rd cpds %s: ', me.devinfo.sn);
              nc.uio.print_all(l);
            end
            if (~done && ~me.st.autorpt && me.st.cmd_started)
              % for "corr o", try to parse to the >.  It should be there already!
              [rsp, err] = me.ser.finish_cmd();
              if (err~=3)
                me.st.cmd_started=0;
              end
            end
            
            if (me.st.meas_num_itr==1)
              data = d;
              ok = me.st.ignore_corr_ok || data(me.st.corr_ok_idx);
              break;
            end
            if (me.st.meas_itr==1)
              me.st.accum_data = d;
              me.st.accum_ok   = me.st.ignore_corr_ok || d(me.st.corr_ok_idx);
            else
              me.st.accum_data = me.st.accum_data + d;
              me.st.accum_ok   = me.st.ignore_corr_ok || (me.st.accum_ok && d(me.st.corr_ok_idx));
            end
            if (me.st.meas_itr>=me.st.meas_num_itr)
              data = me.st.accum_data;
              ok   = me.st.ignore_corr_ok || me.st.accum_ok;
              me.st.meas_itr=1;
              break;
            else
              me.st.meas_itr = me.st.meas_itr + 1;
              if (~me.st.autorpt)
                if (~done && me.st.cmd_started)
                  fprintf('BUG: cpds2000_meas_counts(): could not finish cmd properly. data may be corrupt.\n');
                end
                if ((me.st.meas_itr==me.st.meas_num_itr)&&(me.st.meas_len_remainder>0))
                  if (me.st.measlen_ll~=me.st.meas_len_remainder)
                    set_measlen_ll(me, me.st.meas_len_remainder);
                  end
                end
                [cmd rsp_len] = me.private_meas_counts_start_cmd(chanmsk, me.st.autorpt);
                me.st.rsp_len = rsp_len;
                me.ser.start_cmd_accum([cmd 13]);
                me.st.cmd_started=1;
              end
            end
          end
        end
        if (toc(ts)>me.st.meas_time_s)
          break;
        end
      end
      
    end
    

    function errmsg = meas_counts_stop(me)
      errmsg='';
      if (me.st.cmd_started)
        % fprintf('stop. cmd_started=%d  ser.done=%d\n', me.st.cmd_started, me.ser.done);

        % if not bridged, and still waiting...
        
        %        me.ser.accum_stop();
        
        % if bridged, ser.accum_line should have at least returned from "r" cmd.
        % if not, will this work?
        [~, err] = me.ser.do_cmd(char(27));
        if (err==3) % should never happen
          errmsg = 'failed to cleanly abort meas counts';
        end
      end
      me.st.meas_counts_active=0;
    end

    function [err done] = meas_auto_start(me)
% desc: puts cpds into an automatic measurement mode, in which as soon
%       as it has counts, it prints them.  In the cpds1000 this is (poorly) named
%       "continuous mode".  There may be more than one kind of such a mode.
    % Question: was this used in QuSwitch gui?
      error(' meas_auto_start(me) OBSOLETE');
      [err done] = me.ser.start_cmd(['corr' 13]);
    end

    function [counts err done] = meas_auto_read_counts(me)
% desc: puts cpds into an automatic measurement mode, in which as soon
% returns:
%     counts: if timout happens, counts=[].  Otherwise, counts.
      err=0;
      [line done] = me.ser.accum_line();
      if (isempty(line))
        counts=[];
      else
        [counts ct] = sscanf(line, '%d');
      end
    end

    function err = meas_auto_stop(me)
      me.ser.do_cmd(['i' 13]);
    end

    function dbg_time(me, iter)
      me.ser.do_cmd(sprintf('cyc0\r'));
      me.ser.do_cmd(sprintf('dbg time %d\r', iter));
      tx_times=zeros(iter,1);
      ts=tic();
      dts=zeros(1,iter);
      for k=1:iter
        me.ser.write(char(13));
%        ts1=tic();
        [rsp done to dt] = me.ser.read(-1, 4000, ['>']);
        dts(k)=dt;
%        tx_times(k)=toc(ts1);
      end
      t_s=toc(ts);
                  %      [rsp done to] = me.ser.read(-1, 4000, ['>']);
      fprintf('rsp len %d\n', length(rsp));
      fprintf(' %d * 10/115200 = %.1f ms\n', length(rsp), length(rsp)*10/115200*1000);
      fprintf('dur per %d iter %s\n', iter, nc.uio.dur(t_s/iter,3));
      dts
%      fprintf('mean tx time %d ms\n', round(mean(tx_times)*1000));
    end

    function fast_timebin_tomo_start(me, num_angs, num_runs)
      me.st.rsp='';
      me.st.sent_go=0;
      me.st.num_angs=num_angs;
%      me.ser.do_cmd(sprintf('cyc0\r'));
      me.ser.do_cmd(sprintf('tomo %d %d\r', num_angs, num_runs));
    end

    function [data done errmsg] = fast_timebin_tomo_accum(me)
    % data: first two columns are phases in deg      
      if (~me.st.sent_go)
        me.ser.write(char(13));
        me.st.sent_go=1;
      end
      [rsp done to] = me.ser.read(-1, 4000, ['>']);
      me.st.rsp=[me.st.rsp rsp];
      l=0;
      errmsg='';
      if (done)
        me.st.sent_go=0;
        data=zeros(me.st.num_angs^2,7);
        idx_s=1;
        idxs=strfind(me.st.rsp,char(10));
        for k=1:length(idxs)
          [v ct]=sscanf(me.st.rsp(idx_s:(idxs(k)-1)), '%d');
          if (ct==7)
            l=l+1;
            data(l,1:7)=v;
          end
          idx_s=idxs(k)+1;
        end
        if (~isempty(errmsg))
          if (l~=me.st.num_angs^2)
            errmsg=sprintf('did not rx matrix height from rcs');
          end
        end
        me.st.rsp='';
      else
        errmsg='';
        data=[];
      end
    end

    function [data done] = fast_timebin_tomo_abort(me)
    % actually any char other than char(13) would work too.
      me.ser.write('i');
    end


    function data_hdr = get_data_hdr(me)
      data_hdr = 's0 s1 c01 s2 c02 c12 c012 s3 c03 c13 c013 c23 c023 c123 c0123';
    end
    
    function [corrs err] = meas_corrs(me, corrids)
    % inputs: corrids: vector of correlation IDs
      corrs=ones(1,length(corrids))*NaN;
      err=1;
      devinfo = me.devinfo_a{h};
      if (~strcmpi(me.devinfo.name, 'cpds'))
        printf('ERR: cpds_get_corr: not a cpds\n');
        return;
      end
      if (me.devinfo.model==1000)
        printf('ERR: not implemented for cpds1000 yet. Contact NuCrypt\n');
      else
        fmt = 4;
        cmd = ['corr o' char(13)];

        for retry=1:me.st.retry_lim
    	  [rsp err] = me.ser.do_cmd(cmd);
	  
	  ies=regexp(rsp,'\n');
	  is=1;
	  cnt=0;
	  for k=1:length(ies)
  	    ie=ies(k)-1;
            [rspcorrs rspcnt]=sscanf(rsp(is:ie),'%g');
	    if (rspcnt>4)
	      if (me.dbg_lvl==1)
		nc.print_safe(rsp(is:ie));
		fprintf('\n');
	      end
	      break;
	    end
	    is=ie+2;
          end
	  if ((rspcnt>4)||(retry==retry_lim))
            break;
          end
          pause(0.1);
          me.ser.flush;
        end
        if (rspcnt<=4)
          fprintf('ERR: after %d retries, insufficient response from cpds\n', retry_lim);
          fprintf('     response was:\n');
	  uio.print_safe(rsp);
          fprintf('\n');
	  return;
	end

        if (rsp_len ~= rspcnt)
	  fprintf('WARN: expected %d correlation statistics, but read %d\n', ...
	          rsp_len, rspcnt);
	end
      end
      for k=1:length(corrids)
        id = corrids(k);
        idx = me.corrstat_id2idx(id);
	if (me.dbg_lvl==1)
  	  fprintf('DBG: id %d is at corrs(%d)\n', id, idx);
	end
        if ((idx>=1)&&(idx<=rspcnt))
          corrs(k) = rspcorrs(idx);
        end
      end
      err=0;
      
    end
    
%    function set_remote_flink_tx(me, msk)
%      % msk: bitmask of four bits.  bit1=tx chan1, bit2=tx chan2, etc.
%      [m, err] = me.ser.do_cmd_get_matrix(sprintf('r flink t %d\r', msk));
%      
%    end
    
    function set_flink_rx_map(me, ch, fid, remote_ch)
      if ((fid<1)||(fid>me.devinfo.num_flink))
        error(sprintf('fid must range 1 to %d\', me.devinfo.num_flink));
      end
      if (ch<4)
        error('chan to rx on must be remote-capable');
      end
      me.settings.flink_rx_map(ch,1:2)=[fid remote_ch];
    end
    
    function set_flink_tx(me, fid, flink_tx)
    % flink_tx: bitmask. bit1 for ch0, bit2 for ch1, etc.
      if (flink_tx)
        me.ser.do_cmd(sprintf('flink u %d\r', fid-1));
      end
      flink_tx = bitand(flink_tx, 15);
      % flink_tx = bitand(flink_tx, 2^me.devinfo.num_corr_chan-1); % maybe someday
      [m, err] = me.ser.do_cmd_get_matrix(sprintf('flink t %d\r', flink_tx));
      me.settings.flink_tx = flink_tx;
      if (~flink_tx)
        me.ser.do_cmd(sprintf('flink u %d\r', fid-1));
      end
    end

    function set_flink_cmpr_pwr(me, pwr)
      if (~me.fwver_is_gte([2 7]))
        pwr = max(min(8,pwr),4);
      end
      [m, err] = me.ser.do_cmd_get_matrix(sprintf('flink p %d\r', pwr));
      if (me.fwver_is_gte([2 7]))
        if (~err && (length(m)==1))
          me.settings.flink_cmpr_pwr = m;
        end
      else
        me.settings.flink_cmpr_pwr = pwr; % assume it worked
      end
    end
    
    function set_flink_ref_Hz(me, f_Hz)
      if (me.devinfo.num_flink>0)
        f_Hz=round(f_Hz);
        [m, err] = me.ser.do_cmd_get_matrix(sprintf('flink f %d\r', f_Hz));
        if (~err && (length(m)==1))
          me.settings.flink_ref_Hz = m(1);
        end
      end
    end
    
    function set_flink_max_baud_Hz(me, f_Hz)
      if (me.devinfo.num_flink>0)
        f_Hz=round(f_Hz);
        [m, err] = me.ser.do_cmd_get_matrix(sprintf('flink b %ld\r', f_Hz));
        if (~err && (length(m)==1))
          me.settings.flink_max_baud_Hz = f_Hz;
          me.settings.flink_actual_baud_Hz = m;
        end
      end
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
    
    function fstatus = get_flink_status(me, fid)
      % fid: index of flink.  1-based.
      if ((fid < 1) || (fid>me.devinfo.num_flink))
        error(sprintf('cpds2000_class.get_flink_status(fid): %d is an invalid fid\n', fid));
      end

      if (me.fwver_is_gte([2 6]))
        [rsp errp] = me.ser.do_cmd(sprintf('fstat %d\r', fid-1));
      else
        [rsp errp] = me.ser.do_cmd(sprintf('fstat\r'));
      end
      % indications from SFP
      % Note: some SFPs do not have IIC and don't return all this info,
      % in which case txpowr_uW and rxpwr_uW will be -1.
      fstatus.sfp_los      = me.ser.parse_keyword_val(rsp, 'los', 1);
      fstatus.moddet   = me.ser.parse_keyword_val(rsp, 'moddet', 1);
      if (me.fwver_is_gte([2 8]))
        fstatus.txrx_rdy = me.ser.parse_keyword_val(rsp, 'txrx_rdy', 1);
      end
      if (strfind(rsp,'ERR: iic: nack'))

        % version 2.6 printed that erro mesage. Newer ones more gracevful.
        fstatus.sfp_temp_C   = -1;
        fstatus.sfp_vcc_mV   = 0;
        fstatus.sfp_rxpwr_uW = -1;
        fstatus.sfp_txpwr_uW = -1;
      else
        fstatus.sfp_temp_C   = me.ser.parse_keyword_val(rsp, 'sfp\d_temp_C', -1);
        fstatus.sfp_vcc_mV   = me.ser.parse_keyword_val(rsp, 'sfp\d_vcc_mV', 0);
        fstatus.sfp_rxpwr_uW = me.ser.parse_keyword_val(rsp, 'sfp\d_rxpwr_uW', -1);
        fstatus.sfp_txpwr_uW = me.ser.parse_keyword_val(rsp, 'sfp\d_txpwr_uW', -1);
      end
      fstatus.dcdsync = me.ser.parse_keyword_val(rsp, 'dcdsync', 0);
      fstatus.ber_and_use = me.ser.parse_keyword_val(rsp, 'beranduse', [.5 0]);
      fstatus.flink_baud_Hz = me.ser.parse_keyword_val(rsp, 'flink b', 0);
      fstatus.flink_ref_Hz  = me.ser.parse_keyword_val(rsp, 'flink f', 0);
        
      fstatus.cmpr_stopreason = me.ser.parse_keyword_val(rsp, '[^d]cmpr_stopreason', 0);
      fstatus.cmpr_stopreason_str  = me.const2str(me.devinfo.cmpr_stopreason_map, fstatus.cmpr_stopreason);
        
      fstatus.dcmpr_stopreason = me.ser.parse_keyword_val(rsp, 'dcmpr_stopreason', 0);
      fstatus.dcmpr_stopreason_str = me.const2str(me.devinfo.dcmpr_stopreason_map, fstatus.dcmpr_stopreason);
      fstatus.dcmpr_latency = me.ser.parse_keyword_val(rsp,'latency',0);
      
      if (me.fwver_is_gte([2 7]))
        fstatus.flink_ack_latency = me.ser.parse_keyword_val(rsp,'ack_latency',0);
      else
        fstatus.flink_ack_latency = me.ser.parse_keyword_val(rsp,'acklatency',0);
      end

      fstatus.cmpr_state = me.ser.parse_keyword_val(rsp, '[^d]cmpr_st ', 0);
      fstatus.cmpr_state_str = me.const2str(me.devinfo.cmpr_state_map, fstatus.cmpr_state);
        
      fstatus.dcmpr_state = me.ser.parse_keyword_val(rsp, 'dcmpr_st ', 0);
      fstatus.dcmpr_state_str = me.const2str(me.devinfo.dcmpr_state_map, fstatus.dcmpr_state);
        
        % Initiallly the idea was that only one flink would be "in use" at a time.
        % but wouldn't it be nice if could be rxing from more than one flink?
        %        fstatus.sfp_in_use = me.ser.parse_keyword_val(rsp, 'flink u', 0)+1; % fw is zero based
      s = nc.util.ifelse(me.fwver_is_gte([2 7]),'flink_r ','flink r ');
      fstatus.flink_rx  = me.ser.parse_keyword_val(rsp, s, 0);
      if (~nc.util.ver_is_gt(me.devinfo.fwver,[2 6]))
        fstatus.flink_rx  = bitshift(fstatus.flink_rx, 4); % now bitmask corresponds to channels
      end
      fstatus.flink_tx  = me.ser.parse_keyword_val(rsp, 'flink t', 0);
      if (~me.fwver_is_gte([2 7]))
        me.settings.flink_tx = fstatus.flink_tx;
        if (me.settings.chansrc_fid(4) == fid)
          me.settings.dcmpr_latency = me.ser.parse_keyword_val(rsp, '\Wlatency', 0);
          me.settings.flink_cmpr_pwr = me.ser.parse_keyword_val(rsp, 'flink_rlepwr', 0);
        end
      end

      
      fstatus.cmpr_en = me.ser.parse_keyword_val(rsp, 'cmpr_en', 0);

      if (~me.fwver_is_gte([2 7]))      
        fstatus.acklatency = me.ser.parse_keyword_val(rsp, 'acklatency', 0);
      else
        fstatus.acklatency = me.ser.parse_keyword_val(rsp, 'ack_latency', 0);
      end
    end
    
    function status = get_status(me)
    % status.clkdet: a two-bit bitmask. bit 0 for refin0, bit 1 for refin1.
    %                1=detected, 0=not detected.
    % status.clklock: a two-bit bitmask. bit 0 for clk0, bit 1 for clk1
    %                1=locked, 0=not locked.
    % status.saw_clk_async: a four-bit bitmask. One bit for each of the first four channels.
    %                   indicates whether clk was ever observed to be asynchronous with other clks
    %                   at any time since the last call to get_status.  Cleared when read.
    %                   0=0K, 1= saw clk out of sync with other clocks.
    % status.dll_lock: a four-bit bitmask. One bit for each of the first four channels.
    %                   0=not locked, 1= DLL locked
    % status.flink_rx: a bitmask
    %                   0=not rxing, 1=rxing
    % status.resid: for cpds only
      [rsp errp] = me.ser.do_cmd(['stat' 13]);
      status.clklock   = me.ser.parse_keyword_val(rsp, 'clklock', 0);
      status.clkdet    = me.ser.parse_keyword_val(rsp, 'clkdet', 0);
      status.saw_clk_async = me.ser.parse_keyword_val(rsp, 'saw_clk_async', []);
      if (isempty(status.saw_clk_async))
        status.saw_clk_async = me.ser.parse_keyword_val(rsp, 'clkspill', 0);
      end
      status.dll_lock  = me.ser.parse_keyword_val(rsp, 'dll_lock', [0 0 0 0]);
      if (me.devinfo.is_rcs)
        status.resid     = me.ser.parse_keyword_val(rsp, 'resid', 0);
      end
      if (me.fwver_is_gte([2 7]))
        % this mask is OR from all active flinks.
        status.flink_rx  = me.ser.parse_keyword_val(rsp, 'flink_r', 0);
      else
        if ((me.devinfo.num_flink<1)|| me.devinfo.is_fallback)
          status.flink_rx = 0;
        else
          fstat = me.get_flink_status(1);
          status.flink_rx = fstat.flink_rx;
        end
      end
      
    end
    
    function get_ver(me)
      [rsp errp] = me.ser.do_cmd(['ver' 13]);

      for fid=1:me.devinfo.num_flink
        sfpi.vendor = me.ser.parse_keyword_val(rsp, ...
                         sprintf('sfp%d_vendor',fid-1), '?');
        if (nc.util.ver_is(me.devinfo.fwver, [2 6 0]) ...
            && all((sfpi.vendor<' ') | (sfpi.vendor>char(127))))
          % in version 2.6, if IIC acccess failed, firmware printed junk
          sfpi.vendor = '?';
          sfpi.model = '?';
          sfpi.sn = '?';
          sfpi.wl_nm = -1;
        else
          sfpi.model  = me.ser.parse_keyword_val(rsp, ...
                              sprintf('sfp%d_model',fid-1), '?');
          sfpi.sn     = me.ser.parse_keyword_val(rsp, ...
                              sprintf('sfp%d_sn',fid-1), '?');
          sfpi.wl_nm  = me.ser.parse_keyword_val(rsp, ...
                              sprintf('sfp%d_wl_nm', fid-1),0);
        end
        me.devinfo.sfp_ver(fid)=sfpi;
      end
      
      me.devinfo.hw_variation = nc.ser_class.parse_keyword_val(rsp, 'hw_variation', 0);
      % set of possible channel sources for each chann
      me.devinfo.is_fallback = nc.ser_class.parse_keyword_val(rsp, 'fallback', 0);
      me.devinfo.patlens =[128 128];
      if (me.fwver_is_gte([1 29]))
        [rsp errp] = me.ser.do_cmd(['cfg capa' 13]);
        me.devinfo.patlens = nc.ser_class.parse_keyword_val(rsp, 'patlens', 0);
        s = nc.ser_class.parse_keyword_val(rsp, 'chansrcs', '');
        % typ string:  d,s,l,u4,u2,p0,p1
        devinfo.ver_chansrcs = regexp(s, '[^,]+', 'match');
      end


      
    end

    function mV = thresh_dac2mV(me, detid, dac)
      if (bitand(me.devinfo.hw_variation, me.IDN_HW_VARIATION_SPDTHRESH))
        ref_V = 2.048;
      else % dac on cpds2000cmp board, which uses diff ref voltage
        ref_V = 2.000;
      end
      % mv = ((dac-0x8000)*(2.048*1000)/0x7fff);
      mV = ((dac-32768)*(ref_V*1000)/32767);
    end

    function dac = thresh_mV2dac(me, detid, mV)
      if (bitand(me.devinfo.hw_variation, me.IDN_HW_VARIATION_SPDTHRESH))
        ref_V = 2.048;
      else % dac on cpds2000cmp board, which uses diff ref voltage
        ref_V = 2.000;
      end
      % dac = (int)((mv/1000/2.048)*0x7fff)+0x8000;
      dac = int32((mV/1000/ref_V)*32767+32768);
    end

    function V = bias_dac2V(me, detid, dac);
      fprintf('BUG: bias_dac2V not implemented yet for cpds2000\n');
      V= 60;
    end
    
    function V = bias_V2dac(me, detid, V);
      fprintf('BUG: bias_V2dac not implemented yet for cpds2000\n');
      dac = 1000;
    end

    function ps = gate_ph_dac2ps(me, detid, dac)
% dac: may be vector
      fprintf('BUG: gate_ph_dac2ps not implemented yet for cpds2000\n');
      ps = 0;
    end

    function dac = gate_ph_ps2dac(me, detid, ps)
      fprintf('BUG: gate_ph_ps2dac not implemented yet for cpds2000\n');
      dac = 0;
    end
    
    function ps = dinph_dac2ps(me, chanid, dac)
    % TODO: this is only for fwv 2. and above !
      if (nargin<3)
        error('BUG: cpds2000_class.dinph_dac2ps(chanid, dac) missing arg(s)');
      end
      ps = dac*78;
    end
    
    function dac = dinph_ps2dac(me, chanid, ps)
    % TODO: this is only for fwv 2. and above !
      if (nargin<3)
        error('BUG: cpds2000_class.dinph_ps2dac(chanid, ps) missing arg(s)');
      end
      dac = min(max(round(ps/78),0),31);
    end

    function str = chansrc_code2str(me, code)
      if ((code>=0)&&(code<length(me.devinfo.ver_chansrcs)))
        str=me.devinfo.ver_chansrcs{code+1};
      else
        error(sprintf('BUG: chansrc_code2str(%d): bad code', code));
      end
    end
      
    function code = chansrc_str2code(me, str)
    % returns -1 if code not found
      import nc.*
      idx=find(cellfun(@(x) strcmp(x, str), me.devinfo.ver_chansrcs),1);
      code=util.ifelse(isempty(idx),0,idx)-1;
    end
      
    function get_settings(me)
      import nc.*
      [rsp errp] = me.ser.do_cmd(['set' 13]);
      
      settings.clkdiv   = ser_class.parse_keyword_val(rsp, 'clkdiv', 0); % in cycles
      
      measlen = ser_class.parse_keyword_val(rsp, 'measlen', 0);
      if (~me.st.measlen_ll || (measlen ~= me.st.measlen_ll))
        % act as if this is the total measlen, in one itr.
        % Although this should not matter because caller ought to call set_measlen later.
        me.st.measlen_ll = measlen;
        me.st.meas_itr=1;
        me.st.meas_num_itr=1;
        me.st.meas_len_per_itr = measlen;
        me.st.meas_len_remainder = 0;
        settings.measlen = measlen;
      else
        % This is a re-open, and state is same, so don't reset the meas_itr stuff.
        settings.measlen = me.settings.measlen;
      end
      
      settings.masklen  = ser_class.parse_keyword_val(rsp, 'masklen', 0); % in cycles
      settings.dly      = ser_class.parse_keyword_val(rsp, '\Wdly', [0 0 0 0]); % in cycles
      settings.bias     = ser_class.parse_keyword_val(rsp, 'bias', []); % dac units
      settings.simsig   = ser_class.parse_keyword_val(rsp, 'simsig', [0 0]); % probability
      % popt.dbg=1;
      settings.dsamp_ph = ser_class.parse_keyword_val(rsp, 'pbin', 0); % in cycles
      settings.thresh   = ser_class.parse_keyword_val(rsp, 'thresh', [0 0 0 0]); % dac units
      settings.dinph    = ser_class.parse_keyword_val(rsp, 'dinph', [0 0 0 0]); 
      settings.dll      = ser_class.parse_keyword_val(rsp, 'dll', []); % dac units
      settings.gate_ph  = ser_class.parse_keyword_val(rsp, 'gate p', []);
      settings.gate_amp = ser_class.parse_keyword_val(rsp, 'gate a', []);
      settings.timebin_mode = ser_class.parse_keyword_val(rsp, 'timebin', [0 0]);
      settings.outfunc  = ser_class.parse_keyword_val(rsp, 'cfg outfunc', '');
      settings.outclk_Hz = ser_class.parse_keyword_val(rsp, 'cfg outclk', 0);
      settings.minrpd   = ser_class.parse_keyword_val(rsp, 'cfg minrpd', '');

      settings.clkfreq_Hz = ser_class.parse_keyword_val(rsp, 'cfg clkfreq', 0);
      
      settings.refclk_Hz  = ser_class.parse_keyword_val(rsp, 'cfg ref', 0);
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [2 7 0]) && ...
          (length(settings.refclk_Hz)==1))
        % pre 2.7 response was only of length one.
        settings.refclk_Hz = [settings.refclk_Hz settings.refclk_Hz];
      end

      % designates index of fiberlink used for ctlchan and data xfer.
      % currently only one can be in use at any given time, but I hope to change that soon.
      if (~me.fwver_is_gte([2 10]))
        fid = ser_class.parse_keyword_val(rsp, 'flink u', 0)+1; % 1 based for matlab
        settings.chansrc_fid  = [0 0 0 0 repmat(fid,1,4)];
        settings.chansrc_r_ch = [0 0 0 0 1 2 3 4];
      else
        error('TODO: what is fid per channel?');
      end
      settings.dcmpr_latency = ser_class.parse_keyword_val(rsp, 'flink l', 0);
      settings.flink_ref_Hz = ser_class.parse_keyword_val(rsp, 'flink f', 0);
      settings.flink_cmpr_pwr = ser_class.parse_keyword_val(rsp, 'flink p', 0);
      settings.flink_cmd_term = me.ser.parse_keyword_val(rsp, 'flink k', 62); % cmd term key
      if (me.fwver_is_gte([2 7]))
        settings.flink_tx = ser_class.parse_keyword_val(rsp, 'flink t', 0);
      else
        % old fw it's obtained from fstat cmd.  but it's really a setting.
        settings.flink_tx = me.settings.flink_tx;
      end
      
      dflt = 2.5e9;

      settings.flink_max_baud_Hz    = ser_class.parse_keyword_val(rsp, 'flink b', dflt);
      settings.flink_actual_baud_Hz = ser_class.parse_keyword_val(rsp, 'flink_actual_baud', dflt);
      
      codes = ser_class.parse_keyword_val(rsp, 'chansrc', []);
      settings.chansrc = cell(1,me.devinfo.num_corr_chan);
      for k=1:me.devinfo.num_corr_chan
        if (k<=4)
          if (k<=length(codes))
            settings.chansrc{k}=me.chansrc_code2str(codes(k));
          else
            settings.chansrc{k}='?';
          end
        else
          settings.chansrc{k}=sprintf('flink%d', settings.chansrc_fid(k)-1);
        end
      end

      if (me.fwver_is_gte([1 30])) % new as of RCS ver 2.0
        settings.num_clks = me.ser.parse_keyword_val(rsp, 'numclks', 1);
      else
        settings.num_clks = 2; % always 2
      end

      pattern={'0';'0'};
      if (me.devinfo.can_readback_patterns) % Old firmwares could not read the pattern
        [m, err] = me.ser.do_cmd_get_matrix(['cfg pat 0' 13]);
        if (~err && length(m)>1)
          pattern{1} = me.private_pat_m2str(m(1),m(2:end));
        end
        [m, err] = me.ser.do_cmd_get_matrix(['cfg pat 1' 13]);
        if (~err && length(m)>1)
          pattern{2} = me.private_pat_m2str(m(1),m(2:end));
        end
      end
      settings.pattern = pattern;
      
      
      me.settings = settings;
      
    end
    
  end
  
end
