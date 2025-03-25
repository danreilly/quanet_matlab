classdef intf1000_class < handle

  properties (Constant=true)

  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug cpds reads
    ser      % obj of type serclass
    idn      % NuCrypt identity structure
    devinfo  %
%     .has_fpc     
    settings % current settings
%     .samp_pd_ns
%     .dith_pd
%     .dith_ph
%     .dc_factor
%     .dc_mid
%     .dith2_ph
%     .intg_pd
%     fdbk_tc_ms
%     boost_tc_ms
%     boost_relax
%     fdbk_p % obsolete
%     fdbk_i % obsolete
%     fdbk_goal
%     ph_calc_method
%     bias
%     bias_pd_dac
%     bias_lims
%     fpc       - one row per EFPC.  Tpically 1x4, but may be 2x4 if there are two FPCs
%     ringmode
%     downsamp
%     ph_avg_tc_ms
%     avg_len_us
%     phase_deg
    running
    paused
    data_line_len % expected number of numbers per line during a "run"
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class
  end

  methods

    % CONSTRUCTOR
    function me = intf1000_class(arg1, opt)
    % desc: constructor
      if (nargin<2)
	opt.dbg=0;
      end
      opt=nc.util.set_field_if_undef(opt,'baud',115200);
%     me.dbg = opt.dbg;
      me.ser = []; % nc.ser_class('', opt.baud, opt);
      % me.ser.set_dbg(1);
      me.settings.samp_pd_ns=0;
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.idn = me.ser.idn;
        me.devinfo = me.parse_idn(me.idn);
        me.get_settings();
      elseif (ischar(arg1))
        me.ser = nc.ser_class(arg1, opt.baud, opt);
        me.open();
      else
        error('first param must be portname or ser_class');
      end
    end

    % DESTRUCTOR
    function delete(me)
      me.close;
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    function bool = isopen(me)
      bool = me.ser.isopen();
    end

    function close(me)
      if (me.ser.isopen())
	me.ser.close;
      end
    end

    function err = open(me, portname, opt)
      import nc.*
      err = 0;
      if (nargin==1)
        portname='';
        opt.dbg = 0;
      elseif (nargin==2)
        if (isstruct(portname))
          opt = util.set_field_if_undef(portname, 'dbg', 0);
          portname=util.getfield_or_dflt(opt,'portname','');
        else
          opt.dbg=0;
        end
      end
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      end
      if (~me.ser.isopen())
        return;
      end
      me.idn     = me.ser.get_idn_rsp();
      me.devinfo = me.parse_idn(me.idn);
      me.ser.set_timo_ms(5000);
      me.set_nomenu(1);
      me.get_settings();
    end

    function devinfo = parse_idn(me, idn)
% returns a structure with these fields:
%      devinfo.num_chan = 2;
%      devinfo.ser = 's'; % std
      devinfo=idn;
      devinfo.num_chan = 1;
      devinfo.pol_ctl = 'x';
      devinfo.ser = 'x';
      devinfo.num_wp = 4;

      flds   = regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);

      while(1)

        % C1
        k=3;
        if (k>num_flds)
	  break;
        end
        devinfo.num_chan = parse_word(flds{k}, '%d', 1);
	k = k + 1;
	if(k>num_flds)
	  return;
	end

        % C2
        devinfo.pol_ctl = flds{k}(1);
	k = k + 1;
	if(k>num_flds)
	  return;
	end

        % C3
        devinfo.ser = flds{k}(1);
  
        break;
      end

      me.devinfo=devinfo;

      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
         v = default;
        end
      end

    end

    function set_samp_pd_ns(me, ns)
      me.ser.do_cmd('s');
      me.ser.do_cmd('5');
      [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', round(ns)));
      if (~err && (length(m)==1))
        me.settings.samp_pd_ns = m;
      end
      me.ser.do_cmd('e');
    end

    function fdith_Hz = set_dith_freq_Hz(me, fdith_Hz)
      dith_pd = round(1/(me.settings.samp_pd_ns * 1e-9)/fdith_Hz);
      if ((me.idn.fwver(1)>=2)&&(me.idn.fwver(2)>=5))
        dith_pd = round(dith_pd/4)*4;
      else
        dith_pd = bitset(0,bitwid(dith_pd));
      end
      me.set_dith_pd(dith_pd);
      fdith_Hz = 1/(me.settings.samp_pd_ns*1e-9)/ me.settings.dith_pd;
    end

    function set_dith_pd(me, dith_pd)
      me.ser.do_cmd('s');
      me.ser.do_cmd('3');	
      if ((me.devinfo.fwver(1)>1)||(me.devinfo.fwver(2)>2))
	[m err rsp] = me.ser.do_cmd_get_matrix(sprintf('%d\r', dith_pd));
	if (~err && (length(m)==1))
          me.settings.dith_pd = m;
	end
      else
        me.ser.do_cmd([sprintf('%d', dith_pd) 13]);
        me.settings.dith_pd = dith_pd;
      end
      me.ser.do_cmd('e');
    end

    function set_dith_ph(me, dith_ph)
      me.ser.do_cmd('s');
      me.ser.do_cmd('4');       
      me.ser.do_cmd(sprintf('%.3f\r', dith_ph));
      me.ser.do_cmd(char(13));
      me.ser.do_cmd('e');
      me.settings.dith_ph = dith_ph;
    end

    function set_dith2_ph(me, dith2_ph)
      me.ser.do_cmd('s');
      me.ser.do_cmd('4');
      me.ser.do_cmd(char(13));
      me.ser.do_cmd(sprintf('%.3f\r', dith2_ph));
      me.ser.do_cmd('e');
      me.settings.dith2_ph = dith2_ph;
    end

    function set_idn(me, sn, hwver)
      if (length(hwver)~=2)
	error('hwver must be vector of length 2');
      end
      me.ser.do_cmd('c');
      rsp = me.ser.do_cmd('n');
      if (strfind(rsp,'pass'))
        rsp = me.ser.do_cmd(['matlab9' 13]);
      end
      if (strfind(rsp,'serial'))
        me.ser.do_cmd([sn 13]);
        me.ser.do_cmd([num2str(hwver(1)) 13]);
        me.ser.do_cmd([num2str(hwver(2)) 13]);
      end
      me.ser.do_cmd('e');
    end

    function save_cfg_in_flash(me, fname, caltype)
    % fname: full path filename of calibration file
% caltype: 'b'=bias sweep based calibration
%          's'=stability calibration
      if (nargin<2)
        fname='';
      end
%      me.ser.set_dbg(1);
      me.ser.do_cmd('s');
      me.ser.do_cmd('S');
      if ((me.idn.fwver(1)>1)||(me.idn.fwver(2)>2))
        me.ser.do_cmd(caltype);

%       me.ser.max_wr_len=8;
        me.ser.do_cmd([fname 13]);
%        me.ser.max_wr_len=0;
      end
      me.ser.do_cmd('e');
    end

    function set_dc(me, dc_factor, dc_mid)
      me.ser.do_cmd('s');
      me.ser.do_cmd('D');
      me.ser.do_cmd([sprintf('%g', dc_factor) 13]);
      me.ser.do_cmd([sprintf('%g', dc_mid) 13]);
      me.ser.do_cmd('e');
      me.settings.dc_factor = dc_factor;
      me.settings.dc_mid    = dc_mid;
    end

    
    function set_dig_attn(me, pd)
      error('intf1000_class.set_dig_attn(pd) was called... it is obsolete');
      me.ser.do_cmd('2');
      me.ser.do_cmd('w');       
      me.ser.do_cmd([sprintf('%d', pd) 13]);
%     me.ser.do_cmd('e');
    end
    
    function set_intg_pd(me, intg_pd)
      me.ser.do_cmd('s');
      me.ser.do_cmd('6');
      if ((me.devinfo.fwver(1)>1)||(me.devinfo.fwver(2)>2))
	[m err rsp] = me.ser.do_cmd_get_matrix(sprintf('%d\r', intg_pd));
	if (~err && (length(m)==1))
          me.settings.intg_pd = m;
	end
      else
        me.ser.do_cmd([sprintf('%d', intg_pd) 13]);
        me.settings.intg_pd = intg_pd;
      end
      me.ser.do_cmd('e');
    end

    function set_nomenu(me, en)
      me.ser.do_cmd('n');
    end

    function set_fdbk_gain(me, arg1, arg2)
      if ((me.idn.fwver(1)>1)||(me.idn.fwver(2)>=7))
        opt=arg1;
        me.ser.do_cmd('s');
        me.ser.do_cmd('9');
        me.ser.do_cmd(sprintf('%.6f\r', opt.fdbk_tc_ms));
        me.ser.do_cmd('8');
        me.ser.do_cmd(sprintf('%.6f\r', opt.boost_tc_ms));
        me.ser.do_cmd('7');
        me.ser.do_cmd(sprintf('%.6f\r', opt.boost_dur_ms));
        me.settings.fdbk_tc_ms = opt.fdbk_tc_ms;
        me.settings.boost_tc_ms = opt.boost_tc_ms;
        me.settings.boost_dur_ms = opt.boost_dur_ms;
      elseif ((me.idn.fwver(1)>1)||(me.idn.fwver(2)>=3))
        opt=arg1;
        me.ser.do_cmd('s');
        me.ser.do_cmd('9');
        me.ser.do_cmd([sprintf('%.6f', opt.fdbk_tc_ms) 13]);
        me.ser.do_cmd('8');
        me.ser.do_cmd([sprintf('%.6f', opt.boost_tc_ms) 13]);
        me.ser.do_cmd('7');
        me.ser.do_cmd([sprintf('%.6f', opt.boost_relax) 13]);
        me.settings.fdbk_tc_ms = opt.fdbk_tc_ms;
        me.settings.boost_tc_ms = opt.boost_tc_ms;
        me.settings.boost_relax = opt.boost_relax;
      else           
        gain_p = arg1;
        gain_i = arg2;
        % old obsolete way
        me.ser.do_cmd('s');
        me.ser.do_cmd('9');
        me.ser.do_cmd([sprintf('%.6f', gain_p) 13]);
        me.ser.do_cmd('8');
        me.ser.do_cmd([sprintf('%.6f', gain_i) 13]);
        me.settings.fdbk_p = gain_p;
        me.settings.fdbk_i = gain_i;
      end
      me.ser.do_cmd('e');
    end    

    function set_fdbk_goal(me, goal_deg)
      fprintf('WARN: intf1000_class.set_fdbk_goal deprecated.  Use set_phase_deg\n');
      me.ser.do_cmd('s');
      me.ser.do_cmd('g');
% NOTE: for now while Im debugging, be generous because this can take time!
      me.ser.set_timo_ms(5000);
      [rsp err] = me.ser.do_cmd(sprintf('%.3f\r', goal_deg));
      if (err)
        fprintf('ERR: intf1000_class.set_fdbk_goal(%.1f) failed, err %d', goal_deg, err);
      end
      me.ser.set_timo_ms(2000);
      me.ser.do_cmd('e');
      me.settings.fdbk_goal = goal_deg;
    end

    function set_ph_calc_method(me, method)
      me.ser.do_cmd('s');
      me.ser.do_cmd('m');
      me.ser.do_cmd([sprintf('%d', method) 13]);
      me.ser.do_cmd('e');
      me.settings.ph_calc_method = method;
    end

    function set_bias(me, bias)
      if (length(bias)~=1)
        error('intf1000_class.set_bias(bias): bias must be scalar');
      end
      me.ser.do_cmd('s');
      me.ser.do_cmd('b');
      [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', round(bias)));
      if (~err && (length(m)==1))
        me.settings.bias = m;
      end
      me.ser.do_cmd('e');
    end

    function set_bias_pd_dac(me, bias_pd_dac)
      bias_pd_dac = max(1,round(bias_pd_dac));
      me.ser.do_cmd('s');
      me.ser.do_cmd('1');
      me.ser.do_cmd([sprintf('%d', bias_pd_dac) 13]);
      me.ser.do_cmd('e');
      me.settings.bias_pd_dac = bias_pd_dac;
    end

    function set_bias_lims(me, bias_lims)
      if (length(bias_lims)~=2)
	error('intf1000_class().set_bias_lims: bias_lims must be of length 2.');
      end
      me.ser.do_cmd('s');
      me.ser.do_cmd('B');
      me.ser.do_cmd([sprintf('%d', bias_lims(1)) 13]);
      me.ser.do_cmd([sprintf('%d', bias_lims(2)) 13]);
      me.ser.do_cmd('e');
      me.settings.bias_lims = bias_lims;
    end

    function set_fpc(me, pc_i, wp_i, val)
    % desc: sets a waveplate of the Fiber Polarlization Controller (EFPC)
    % inputs:
    %   pc_i: index of polarization controller
    %   wp_i: index of waveplate (typically 1..4)
    %   val: dac value for that FPC waveplate
      if (~isscalar(pc_i) || ~isscalar(wp_i) || ~isscalar(val))
        error('intf1000_class.set_fpc(pc_i,wp_i,val): args must be scalar');
      end
      if ((pc_i<1)||(pc_i>2))
        error('intf1000_class.set_fpc(): bad pc_i');
      end
%      fprintf('DBG: set fpc%d: wp %d  val %d\n', pc_i, wp_i, val); 
      me.ser.do_cmd(nc.util.ifelse(pc_i==1,'f','F'));
      wp_i = max(min(wp_i,me.devinfo.num_wp),1);
      me.ser.do_cmd(char('0'+wp_i));
      val = max(min(val, 2^12-1),0);
      me.ser.do_cmd([num2str(val) 13]);
      me.settings.fpc(pc_i, wp_i)=val;
    end

    function set_ringmode(me, en)
      en = ~~en;             
      me.ser.do_cmd('s');       
      me.ser.do_cmd('f');
      me.ser.do_cmd('n');
      me.ser.do_cmd([char('0'+en) 13]);
      me.ser.do_cmd('e');      
      me.settings.ringmode=en;
    end

    function err = set_downsamp(me, ds)
      ds=max(round(ds),1);
      me.ser.do_cmd('s');
      me.ser.do_cmd('s');
      me.ser.do_cmd([num2str(ds) 13]);
      me.ser.do_cmd('e');
      me.settings.downsamp=ds;
    end


    function set_ph_avg_tc_ms(me, tc_ms)
      me.ser.do_cmd('s');
      me.ser.do_cmd('l');
      [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', round(tc_ms)));
      if (~err && (length(m)==1))
        me.settings.ph_avg_tc_ms = m;
      end
      me.ser.do_cmd('e');
    end

    function set_avg_len_us(me, us)
      fprintf('WARN: intf1000_class.set_avg_len_us is DEPRECATED\n');
      me.ser.do_cmd('s');
      me.ser.do_cmd('l');
      [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', round(us)));
      if (~err && (length(m)==1))
        me.settings.avg_len_us = m;
      end
      me.ser.do_cmd('e');
    end

    function set_trig(me, en)
      me.ser.do_cmd('s');
      me.ser.do_cmd('t');
      me.ser.do_cmd(sprintf('%d\r', en));
      me.ser.do_cmd('e');
    end

    function set_phase_deg(me, chan, ph_deg)
      me.ser.do_cmd('s');
      me.ser.do_cmd('g');
      me.ser.set_timo_ms(5000);
      % fprintf('DBG: intf1000_clas.set_phase_deg(%d, %g)\n', chan, ph_deg);
      [~, err] = me.ser.do_cmd(sprintf('%.3f\r', ph_deg));
      if (err)
        fprintf('ERR: intf.set_phase_deg(%d, %.2f) err=%d\n', chan, ph_deg, err);
      end
      me.ser.set_timo_ms(2000);
      me.ser.do_cmd('e');
      me.settings.phase_deg(chan) = ph_deg;
    end

    function set_fdbk_en(me, en)
      en = ~~en;	     
      if (me.running)
	if (en)
	  me.ser.write('F'); % 'F' = enable fdbk
	else
	  me.ser.write('f'); % 'f' = disable fdbk
	end
      else
        me.ser.do_cmd('s');
        me.ser.do_cmd('f');
        me.ser.do_cmd([char('0'+en) 13]);
        me.ser.do_cmd('e');
      end
      me.settings.fdbk_en=en;
    end

    function [dc_min dc_max] = meas_visibility(me)
    % desc: sweeps bias using current intg_pd and then returns
    % the min and max dc detector values seen
      me.ser.set_timo_ms(5000);
      rsp = me.ser.do_cmd('v');
      m = me.ser.parse_matrix(rsp);
      if (length(m)~=2)
	fprintf('ERR: intf1000_class.meas_visibility(): bad rsp\n');
        nc.uio.print_all(rsp);
	dc_min=0;
	dc_max=0;
      else
        dc_min=m(1);
        dc_max=m(2);
      end
      me.ser.set_timo_ms(2000);
    end
    
    function [a1 p1 a2 p2 ph dcv] = meas(me)
      rsp = me.ser.do_cmd('m');
      idxs = regexp(rsp,' \d');
      if (isempty(idxs))
        ct=0;
      else
        [row ct]=sscanf(rsp(idxs(1)+1:end),'%g');
      end
      if (ct==10)
        a1=row(5);
        p1=row(6);
        a2=row(7);
        p2=row(8);
        ph=row(9);
        dcv=row(10);
      else
        a1=0;
        p1=0;
        a2=0;
        p2=0;
        ph=0;
        dcv=0;
      end	
    end
      
    function sweep_bias_start(me, bias_s, bias_d, bias_e)
      me.ser.do_cmd('4');
      me.ser.do_cmd([sprintf('%d', bias_s) 13]);
      me.ser.do_cmd([sprintf('%d', bias_d) 13]);
      me.ser.write([sprintf('%d', bias_e) 13]);
      me.running=1;
    end
    
    function sweep_bias_end(me)
      rsp = me.ser.do_cmd(['0' 13]);
      me.running=0;
    end

    function set_data_hdr_style(me, v)
    % v: an integer.  indicates the style to use.
    % call this then call get_data_hdr
      me.ser.do_cmd('m');
      me.ser.do_cmd('h'); % p = print indefinately
      me.ser.do_cmd([num2str(v) 13]);
      me.ser.do_cmd('e');
    end

    function data_hdr = get_data_hdr(me, cmd)
      % desc: returns the data header appropriate for the data
      %       matrix generated by the specified command.
      % raison d'etre: Over time there are many changes to the methods
      %     of calculation and calculated and measured values. Some go
      %     obsolete. New ones arise.  Test programs can't expect specific
      %     data columns to stay the same, so thats why they are named.
      %     The column names will vary depending on the fimrware, the
      %     command being used, and possibly the mode of use.  To make it
      %     easy for test programs, They should call get_data_hder to
      %     learn the data header.  They should not assume they know what
      %     the data header is.
      % inputs:
      %    cmd: 'b': bias sweep commands
      %         'm': monitor commands
      if (nargin<2)
        error('intf1000_class.get_data_hdr(cmd): cmd arg required');
      end
      if (cmd=='m') % header for "run" and "measure" data
	if ((me.devinfo.fwver(1)>=1)&&(me.devinfo.fwver(2)>=3))
	  data_hdr = 'time_ms bias intf_ph intf_ph_avg err det_dc_v';
	else % old header for "run" command hdr format #2:
	  data_hdr = 'time_ms bias err err_sum bias_d intf_ph det_dc_v';
	end
      elseif (cmd=='b') % header for bias sweep data
	if ((me.devinfo.fwver(1)>=1)&&(me.devinfo.fwver(2)>=3))
	  data_hdr='time_ms bias a1 p1 a2 p2 intf_ph det_dc_V';
	else
	  % old firmware did not print the time during a bias sweep
	  data_hdr='bias a1 p1 a2 p2 intf_ph det_dc_V';
	end
      else
        error('intf1000_class.get_data_hdr(cmd): cmd must be b or m');
      end	     
    end

    function meas_print_start(me, zero_time)
      me.ser.do_cmd('m');
      if ((nargin>1)&&zero_time)
	me.ser.do_cmd('0');
      end
      me.ser.write('p'); % p = print indefinately
      me.running=1;      
    end

    function meas_print_stop(me)
    % does not stop the recording however.  Just stops the printing
      if (me.running)
        rsp = me.ser.do_cmd('e');
% the last line of rsp is a single number that indicates number of times
% ISR failed to service the IQ values produced by VHDL
	idx = max(1,length(rsp)-20);
	idxs=findstr(rsp(idx:end),char(10))+idx-1;
	idxs(end+1)=length(rsp);
	for k=1:length(idxs)-1
%	  rsp(idxs(k)+1:idxs(k+1)-1)
	  [v cnt] = sscanf(rsp(idxs(k)+1:idxs(k+1)-1),'%d');
	  if (cnt==1)
            if (v>0)
	       fprintf('ERR: ISR failed to service all IQ values\n');
	       fprintf('     miss_count = %d\n', v);
            end
            break;
          end
        end	    
        me.running=0;
        me.ser.do_cmd('e');
      end
    end

    function errmsg=set_wavelen_nm(me, vci, wl_nm)
    % also sets settings.sig_wl_nm
      err=0;
      if (~nc.util.ver_is_gte(me.idn.fwver, [2 7 1]))
	errmsg='INTF does not support wavelength correction';
        return;
      end
      errmsg='';
      me.ser.do_cmd('s');
      rsp = me.ser.do_cmd('w');
      rsp = me.ser.do_cmd(char(13));
      me.ser.do_cmd(sprintf('%.3f\r',wl_nm));
      me.ser.do_cmd('e');
      me.settings.sig_wl_nm = wl_nm;
    end

    function set_step(me, step_type, step_amt, step_time_s)
      me.ser.do_cmd('m');
      me.ser.do_cmd(step_type);
      me.ser.do_cmd([num2str(step_amt) 13]);
      me.ser.do_cmd('e');
    end
    
%    function run(me, paused);
%    % inputs:
%    %   me - instance of this class
%    %   paused - 0=just run, 1=wait for space before each measurement
%      if ((me.idn.fwver(1)>=1)&&(me.idn.fwver(2)>=3))
%        me.data_line_len = 5;
%      else
%        me.data_line_len = 7;
%      end
%      me.ser.write('r'); % r = indefinite run
%      % me.ser.write([sprintf('%d', iter) 13]);
%      me.running=1;
%      me.paused=0;
%      if ((nargin>1) && paused)
%        me.ser.write(' '); % space = use pause mode
%        me.paused=1;
%      end
%    end

    
    function run_stop(me, iter)
      if (me.running)
        me.ser.do_cmd('e');
        me.running=0;
      end
    end
    
    function settings = get_settings(me)
      me.ser.do_cmd('s'); % 's' = settings menu
      rsp = me.ser.do_cmd('p'); % 'p' = print settings
      me.ser.do_cmd('e'); % go back to main menu
      settings.fpc         = me.ser.parse_keyword_val(rsp, 'fpc', []);
      me.devinfo.has_fpc=~isempty(settings.fpc);
%      settings.ringmode    = me.ser.parse_keyword_val(rsp, 'ringmode', [], 0, 0, 0);
      settings.downsamp    = me.ser.parse_keyword_val(rsp, 'downsamp', 1);
      settings.samp_pd_ns  = me.ser.parse_keyword_val(rsp, 'samp_pd_ns', 0);
      settings.dith_pd     = me.ser.parse_keyword_val(rsp, 'dith_pd', 0);
      settings.dc_mid      = me.ser.parse_keyword_val(rsp, 'dc_mid', 0);
      settings.dc_factor   = me.ser.parse_keyword_val(rsp, 'dc_factor', 0);
      settings.bias        = me.ser.parse_keyword_val(rsp, 'bias ', 0);
      settings.bias_pd_dac = me.ser.parse_keyword_val(rsp, 'bias_pd_dac', 0);
      settings.bias_lims   = me.ser.parse_keyword_val(rsp, 'bias_lims', [0 0]);
      settings.dith_ph     = me.ser.parse_keyword_val(rsp, 'dith_ph', 0);
      settings.dith2_ph    = me.ser.parse_keyword_val(rsp, 'dith2_ph', 0);
      settings.intg_pd     = me.ser.parse_keyword_val(rsp, 'intg_pd', 0);
      settings.dmod_dly    = me.ser.parse_keyword_val(rsp, 'dmod_dly', 0);

      % OBSOELTE:
      settings.fdbk_p      = me.ser.parse_keyword_val(rsp, 'fdbk_p', 0);
      settings.fdbk_i      = me.ser.parse_keyword_val(rsp, 'fdbk_i', 0);

%      settings.fdbk_tc_ms  = me.ser.parse_keyword_val(rsp, 'fdbk_ms', 10);
      settings.usual_fdbk_tc_ms     = me.ser.parse_keyword_val(rsp, 'usual_fdbk_tc_ms', []);
      if (isempty(settings.usual_fdbk_tc_ms)) % backward compat with obsolete name
        settings.usual_fdbk_tc_ms   = me.ser.parse_keyword_val(rsp, 'fdbk_tc_ms', []);
      end
      settings.boost_fdbk_tc_ms = me.ser.parse_keyword_val(rsp, 'boost_fdbk_tc_ms', []);
      if (isempty(settings.boost_fdbk_tc_ms)) % backward compat with obsolete name
        settings.boost_fdbk_tc_ms = me.ser.parse_keyword_val(rsp, 'boost_ms', []);
      end
      if (~isempty(me.ser.parse_keyword_val(rsp, 'boostl', [])))
        error('Not compatible with obsolete firmware that uses boostl or boost_relax');
      end
      settings.boost_dur_ms   = me.ser.parse_keyword_val(rsp, 'boost_dur_ms', []);
      settings.kramp_dur_ms   = me.ser.parse_keyword_val(rsp, 'kramp_dur_ms', []);

 %     settings.boost_tc_ms  = me.ser.parse_keyword_val(rsp, 'boost_ms', 10);
 %     settings.boost_relax  = me.ser.parse_keyword_val(rsp, 'boostl', 1);

      settings.fdbk_en     = me.ser.parse_keyword_val(rsp, 'fdbk_en', 0);
      settings.fdbk_goal   = me.ser.parse_keyword_val(rsp, 'fdbk_goal', 0); % OBSOLETE
      settings.phase_deg   = me.ser.parse_keyword_val(rsp, 'fdbk_goal', 0); % feedback goal
%      settings.ringmode    = me.ser.parse_keyword_val(rsp, 'ringmode', [], 0, 0, 0);
      settings.ph_calc_method = me.ser.parse_keyword_val(rsp, 'ph_calc_method', 0);
      settings.avg_len_us  = me.ser.parse_keyword_val(rsp, 'avg_len_us', 0); % OBSOLETE
      settings.ph_avg_tc_ms = me.ser.parse_keyword_val(rsp, 'ph_avg_tc_ms', 0);

      settings.a2_factor   = me.ser.parse_keyword_val(rsp, 'a2_factor', [], 0);
      settings.a1a2_ph     = me.ser.parse_keyword_val(rsp, 'a1a2_ph', [], 0);
      settings.a1_amp         = me.ser.parse_keyword_val(rsp, 'a1_amp', 0); % new in fwv 1.7
      settings.a2_offset_poly = me.ser.parse_keyword_val(rsp, 'a2_offset_poly', [0 0]);
      settings.lock_thresh_deg = me.ser.parse_keyword_val(rsp, 'lock_thresh_deg', 5); % new in 2.1.3

      settings.lockref_wl_nm = me.ser.parse_keyword_val(rsp, 'lockref_wl_nm', 0);
      settings.sig_wl_nm = me.ser.parse_keyword_val(rsp, 'sig_wl_nm', 0);
      settings.kal_en         = me.ser.parse_keyword_val(rsp, 'kal_en', 0);
      settings.kal_x_tc_ms    = me.ser.parse_keyword_val(rsp, 'kal_x_tc_ms', []);
      settings.kal_h          = me.ser.parse_keyword_val(rsp, 'kal_h', []);
      settings.kal_q          = me.ser.parse_keyword_val(rsp, 'kal_q', []);
      settings.kal_m_var_deg  = me.ser.parse_keyword_val(rsp, 'kal_m_var_deg', []);
      settings.kal_calc_pk    = me.ser.parse_keyword_val(rsp, 'kal_calc_pk', 0);
      settings.kal_oshoot     = me.ser.parse_keyword_val(rsp, 'kal_oshoot', []);
%      settings.kal_kramp_dur_ms = me.ser.parse_keyword_val(rsp, 'kal_kramp_dur_ms', []);

      me.ser.do_cmd('c'); % go to config menu
      rsp = me.ser.do_cmd('p'); % print config settings
      me.ser.do_cmd('e'); % go to main menu
      settings.calfile        = me.ser.parse_keyword_val(rsp, 'calfile', '');
      settings.stabcalfile    = me.ser.parse_keyword_val(rsp, 'stabcalfile', '');
      me.settings = settings;
    end
    
    function status = get_status(me)
      rsp = me.ser.do_cmd('a'); % 'a' = get status
      status.locked      = me.ser.parse_keyword_val(rsp, 'locked', 1);

      status.fpga_temp_C = me.ser.parse_keyword_val(rsp, 'temp_C', 0);
      status.rej_pump_adc= me.ser.parse_keyword_val(rsp, 'rej_pump', 0);
      status.locktime_ms = me.ser.parse_keyword_val(rsp, 'locktime_ms', 0);
      status.mean_relock_t_ms = me.ser.parse_keyword_val(rsp, 'mean_relock_t_ms', 0);
      status.ph_deg      = me.ser.parse_keyword_val(rsp, 'ph_deg', 1);
      status.wrap_ctr    = me.ser.parse_keyword_val(rsp, 'wrap_ctr', 1);
      status.dt_mean_ms  = me.ser.parse_keyword_val(rsp, 'dt_mean_ms', 0);
      status.kal_p       = me.ser.parse_keyword_val(rsp, 'kal_p', 1);
      status.kal_k       = me.ser.parse_keyword_val(rsp, 'kal_k', 1);
      status.kal_x_rad   = me.ser.parse_keyword_val(rsp, 'kal_x', 1); % in rad
    end
    
    function [row err] = run_get_row(me)
    % desc:
      err=0;
%      if (me.paused)
%        me.ser.write(' '); % space = get next row
%      end
      while(me.running)
	[str found_key met_timo] = me.ser.read(256, 4000, ['>' 10]);
	if (strfind(str,'ERR'))
	  fprintf(str);
	end
	if (strfind(str,'>'))
	  row=[];
	  fprintf('DBG: got >\n');
          nc.uio.print_all(str);
	  me.running=0;
	  return;
	end
	[row, cnt]=sscanf(str,'%g');
	if (cnt>1)
          err = (cnt~=me.data_line_len);
	  if (err)
	    fprintf('ERR: could not parse %d numbers in\n', me.data_line_len);
            nc.uio.print_all(str);
          end
          row = row.';
	  return;
	end
      end
      row=[];
    end

  end
  
end
