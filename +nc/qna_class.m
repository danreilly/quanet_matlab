
classdef qna_class < nc.ncdev_class
    % NuCrypt qna device
    % s750 board in quanet qnic
  
  properties (Constant=true)
    c_mps = 299792458;
  end
  
  properties
    
    ser
    % ser_class used to access pulser
    idn
    devinfo
    % Customization and capability information about this pulser
    %   devinfo.num_chan
    %   devinfo.can_set_pulse_delay
    %   devinfo.can_set_pulse_width
    %   devinfo.can_set_voa 
    %   devinfo.can_set_wavelen
    %   devinfo.has_freqgen
    
    settings
    % Current settings of this pulser.
    % Note: This is a read-only structure.
    %   settings.
    
  end

  methods (Static=true)


    % static
    function devinfo = parse_idn(idn)
      devinfo = idn;

      for_fwver = [6 1 1];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: qna1000_class(): This software was written for QNA firmwares %s and below\n', nc.util.ver_vect2str(for_fwver));
        fprintf('      but QNA has firmware %s and might not work with this +nc package\n', ...
                nc.util.ver_vect2str(devinfo.fwver));
      end
      
      % default QNA
      devinfo.laser_is_pure=1;

    end
    
  end

  methods

    % CONSTRUCTOR
    function me = qna_class(arg1, opt)
    % desc: qna_class constructor. Opens device, reads all settings.
    % usages:
    %   obj = qna_class(opt)
    %           opt: a structure
    %             opt.dbg: 1=debug all io, 0 =dont
    %   obj = pg300_class(ser)
    %   obj = pg300_class(ser, opt)
    %           ser: a ser_class object that is open, stays open
    %   obj = pg300_class(port)
    %   obj = pg300_class(port, opt)
    %           port: a string like 'com21'
      import nc.*
      me.devinfo = [];
      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'baud', 115200);
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.devinfo = me.parse_idn(me.ser.idn);
        me.get_version_info();
        me.get_settings();
      elseif (ischar(arg1))
        me.ser = nc.ser_class(arg1, opt);
        me.open();
      else
        error('first param must be portname or ser_class');
      end
      me.ser.cmd_nchar = 100000;
    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end
    function open(me, arg1, arg2)
    % desc: opens pg300 device, does 'i' command, fills in me.devinfo.
    % usages: pg.open(portname)
    %         pg.open(opt)
    %         pg.open(portname, opt)
      import nc.*
      if (nargin==1)
        portname='';
        opt.dbg = 0;
      elseif (nargin==2)
        if (isstruct(arg1))
          opt = util.set_field_if_undef(arg1, 'dbg', 0);
          portname=util.getfield_or_dflt(opt,'portname','');
        else
          portname = arg1;
          opt.dbg = 0;
        end
      else
        portname = arg1;
        opt = arg2;
      end
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      end
      if (me.ser.isopen())
        idn = me.ser.get_idn_rsp; % identity structure
        me.devinfo = me.parse_idn(idn);
        me.get_version_info();
        me.ser.set_timo_ms(1000);
        me.get_settings();
      else
	if (me.ser.dbg)
	  fprintf('WARN: pg300_class.open failed\n');
        end
      end
    end

    function get_version_info(me)
      me.devinfo.laser_is_pure=1;
    end
    
    function f=isopen(me)
      f=me.ser.isopen();
    end
    
    function close(me)
      if (me.isopen())
        me.ser.close;
      end
    end
    
    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end
    
    function set_gas_fdbk_en(me, en)
      rsp = me.ser.do_cmd_get_matrix(sprintf('gas en %d\r', en));
      me.settings.gas_fdbk_en=en;
    end
    
    function err = set_itla_finetune_MHz(me, ch, finetune_MHz)
    % ch - ignored
      me.ser.set_timo_ms(20000);
      me.ser.write(sprintf('cfg it fine '));
      pause(0.1);
      rsp = me.ser.do_cmd(sprintf('%d\r', finetune_MHz));
      err = ~isempty(strfind(rsp,'ERR'));
      if (~err)
        me.settings.itla.finetune_MHz = finetune_MHz;
      end
    end

    function err = set_itla_mode(me, ch, mode)
    % ch - ignored
      me.ser.set_timo_ms(30000);
      rsp = me.ser.do_cmd(sprintf('cfg it mode %s\r', mode));
      err = ~isempty(strfind(rsp,'ERR'));
      if (~err)
        me.settings.itla.mode = mode;
      else
        rsp
      end
    end
    
    function set_itla_channel(me, ch, chan)
    % ch - ignored
      me.ser.set_timo_ms(60000);
      rsp = me.ser.do_cmd_get_matrix(sprintf('cfg it chan %d\r', chan));
      me.settings.itla.chan = chan;
    end
    
    function set_gaslines(me, lsr_idx, fname, gaslines)
      %  gaslines: Nx7 (not inc std) or Nx8
      if (lsr_idx~=1)
        error('can only config ref gasline now');
      end
      me.ser.set_cmd_params(500, 500);
      me.ser.set_dbg(1,'qna');
      [rsp err]= me.ser.do_cmd(['cfg gas ' fname char(13)]);

      for k=1:size(gaslines,1)
	r = gaslines(k,:);
        cmd = [sprintf(' %d', r) char(13)];
        fprintf('%s', cmd);
	for kk=1:4
	  [rsp err]= me.ser.do_cmd(cmd);
	  if (~err)
	    break;
	  end
	  fprintf('DBG: retry\n');
	  me.ser.set_dbg(1, 'tunlsr');
	  me.ser.write(char(13));
	  pause(0.5);
	  me.ser.flush();
	end
	pause(0.2); % otherwise embedded code drops chars. it cant read fast enough!
      end
      [rsp err]= me.ser.do_cmd(char(13));
      me.ser.set_cmd_params(1000, 60000);
      me.ser.set_dbg(0);
    end
    
    function err = set_itla_freq(me, ch, freq_MHz)
    % ch - ignored
      me.ser.set_timo_ms(60000);
      me.ser.write(sprintf('cfg it freq '));
      pause(0.1);
      rsp = me.ser.do_cmd(sprintf('%d\r', round(freq_MHz)));
      err = ~isempty(strfind(rsp,'ERR'));
      if (err)
        rsp
      end
      m = me.ser.parse_matrix(rsp);
      if (~isempty(m))
        me.settings.itla.freq_MHz = m;
      end
    end
    
    function set_beat_fdbk_tc_us(me, tc_us)
      rsp = me.ser.do_cmd_get_matrix(sprintf('beat tc %d\r', tc_us));
      if (~isempty(rsp))
        me.settings.beat_tc_us = rsp;
      end
    end
    
    function set_beat_goal(me, kHz)
    % kHz: 0= turn off feedback and reset FM to midpoint.
      rsp = me.ser.do_cmd_get_matrix(sprintf('beat goal %d\r', kHz));
      if (~isempty(rsp))
        me.settings.beak_goal_kHz = rsp;
      end
      if (kHz==0)
        rsp = me.ser.do_cmd(sprintf('cfg it fm 2047\r'));
      end
    end


    
    function status = get_status(me)
      rsp = me.ser.do_cmd(['stat' char(13)]);
      status.beat_kHz = me.ser.parse_keyword_val(rsp, 'beat_freq_kHz', 0);
      status.gas_lock = me.ser.parse_keyword_val(rsp, 'gas_lock', 0);
      status.gas_lock_dur_s = me.ser.parse_keyword_val(rsp, 'gas_lock_dur_s', 0);
      status.gas_mse_MHz2   = me.ser.parse_keyword_val(rsp, 'gas_mse_MHz2', 0);
      status.alarm_fm_at_rail = me.ser.parse_keyword_val(rsp, 'alarm_fm_at_rail', 0);
    end
  
    function get_settings(me)
      rsp = me.ser.do_cmd(['set' char(13)]);
      me.settings.wavelen_nm = me.ser.parse_keyword_val(rsp, 'wavelen', 0);

      
      rsp = me.ser.do_cmd(['beat set' char(13)]);
      me.settings.beat_en     = me.ser.parse_keyword_val(rsp, 'en', 0);
      me.settings.beat_dur_us = me.ser.parse_keyword_val(rsp, 'dur', 0);
      me.settings.beat_tc_us  = me.ser.parse_keyword_val(rsp, 'tc', 0);
      me.settings.beat_goal_kHz = me.ser.parse_keyword_val(rsp, 'goal', 0);

      rsp = me.ser.do_cmd(['cfg it set' char(13)]);
      me.settings.itla.en       = me.ser.parse_keyword_val(rsp, 'en', 0);
      me.settings.itla.pwr_dBm  = me.ser.parse_keyword_val(rsp, 'pwr_dBm', 0);
      me.settings.itla.freq_MHz = me.ser.parse_keyword_val(rsp, 'freq_MHz', 0);
      me.settings.itla.mode     = me.ser.parse_keyword_val(rsp, 'mode', 'd');
      me.settings.itla.f0_MHz   = me.ser.parse_keyword_val(rsp, 'f0_MHz', 0);
      me.settings.itla.grid_MHz = me.ser.parse_keyword_val(rsp, 'grid_MHz', 0);
      me.settings.itla.chan     = me.ser.parse_keyword_val(rsp, 'chan', 0);
    end
    
    function cfg_write(me)
      rsp = me.ser.do_cmd(['cfg write' char(13)]);
      % right now prompts for wl.
      % rsp = me.ser.do_cmd(char(13));      
    end
    
     function v=sample(me, nsamps)
       for k=1:3
	 [rsp err]= me.ser.do_cmd(['samp' char(13)]);
	 v = me.ser.parse_matrix(rsp);
	 if (length(v)==me.samp_hdr_len)
	   v=me.convert_units(v);
  	   if (length(v)~=me.samp_hdr_len)
	     fprintf('conv unit bug\n');
           end
	   return;
	 end
	 fprintf('\nERR tunlsr: bad tunlsr samp rsp!\n');
	 fprintf('             got %d numbers insted of %d\n', length(v), me.samp_hdr_len);
	 nc.uio.print_all(rsp);
	 if (k==3)
	   me.close();
	   error('BUG');
	 end
	 me.ser.write(['i' char(13)]);
	 pause(1);
	 me.ser.flush();
	 fprintf('TC: retry\n');
       end
       v=zeros(1,me.samp_hdr_len);
     end


    function er = wait_for_pwr_stability(me, lsr_idx, verbose, min_itrlim)
       % returns: er: 1=timeout after 100 tries, 0=ok and stable
       % input: min_itrlim = OPTIONAL. min num iterations to wait.  Then this is the number
       %          of iterations over which we consider a "change" to take place. see code.
       % NOTE: If you change the power of the pure photonics laser, it will take some
       % time to do that.  Then it will indicate that it is done.  But don't beleive it!
       % call this function to wait for the power to truely stabilize.  Same goes
    % for laser enable and also channel change!
       import nc.*
       if (nargin<2)
         verbose=0;
       end
       if (nargin<4)
         min_itrlim=8;
       end
       er=1;

       if (lsr_idx==1)
	 ldesc = 'refsr';
         % pcol = me.cols.ref_pwr;
       else
	 ldesc = 'tunsr';
         % pcol = me.cols.tun_pwr;
       end

       h_i = 1;
       h_l = min_itrlim;


       h = zeros(h_l,1);

       settle_start = tic;
       if (verbose)
         fprintf('waiting for power of %s to settle\n', ldesc);
       end
       % NOTE: wl1 is tunable laser.  wl2 is reference.

%       mag_pre=0;
       pwr_pre=0;
       ok_ctr=0;
       pcol=0;
       for itr=1:1000
%	 lset = me.get_laser_set;
%	 if (isref)
%	   pwr_dbm = lset.ref_pwr_dbm;
%         else
%	   pwr_dbm = lset.meas_pwr_dbm;
%         end
	 [hdr v] = me.cap(1);

         if (~pcol)
           pcol = nc.vars_class.datahdr2col(hdr, 'pwr_adc');
           if (~pcol)
             hdr
             v
             fprintf('FAIL: no pwr_adc reported by cap\n');
             return;
           end
         end
         
	 % assumes wl1 is stable.
         % ph = v(me.cols.ph_x10);

         %	 mag = util.iff(col, sqrt(v(col)), 1);
         if (pcol>length(v))
           me.ser.set_dbg(1);
           me.get_status();
           continue;
         end
         me.ser.set_dbg(0);
         
         pwr = v(pcol);
         if (itr>h_l)
           pch_pct = 100 * (pwr - h(h_i)) / h(h_i);
	   if (abs(pch_pct) < 0.1)
             er=0;
             break;
           end
         else
           pch_pct = 100 * (pwr - h(1)) / h(1);
         end
         h(h_i) = pwr;
         h_i=mod(h_i,h_l)+1;

	 % mag  = util.iff(me.cols.wl2_mag2, sqrt(v(me.cols.wl2_mag2)), 1);
         if (verbose)
%  	   fprintf('   laser pwr %.2f  mag %.1f  change %.3f%%\n', pwr_dBm, mag, change_pct);
  	   fprintf('   laser  pwr %d  ch %.3f%%\n',  pwr, pch_pct);
         end
	 pause(0.025);
%	 mag_pre = mag;
	 pwr_pre = pwr;
       end
%       er = (ok_ctr<=4);
       if (er && verbose)
         fprintf('tunlsr_class.wait_for_stability(): ERR: itla laser is stuck!\n');
       end
       settle_s = round(toc(settle_start));
       if (verbose)
         fprintf('settling took %s\n',uio.dur(settle_s));
       end
     end

    function hdr = get_cap_hdr(me)
      rsp = me.ser.do_cmd(['cap set' char(13)]);
      hdr = me.ser.parse_keyword_val(rsp, 'hdr', '');
    end
    
    function [hdr, data] = cap(me, len, type, step, dsamp)
    % usage:
    %   qna.cap(len) - captures <len> samples.  No step.
    %   qna.cap(len,type,step) - captures <len> samples and applies
    %     a "step" of the specified type after the tenth sample.
    %       type: f=fm step, g=goal step
    %       step: in dac units for fm step, in kHz for goal step.
      if (nargin<3)
        type='g';
        step=0;
        dsamp=1;
        amt=0;
      end

      est_ms = dsamp * len * me.settings.beat_dur_us / 1000;
      
      me.ser.set_timo_ms(10000 + est_ms);
      
      rsp = me.ser.do_cmd(sprintf('cap step %c %d\r', type, step));
      
      rsp = me.ser.do_cmd(['cap set' char(13)]);
      hdr = me.ser.parse_keyword_val(rsp, 'hdr', '');
      [data err] = me.ser.do_cmd_get_matrix(sprintf('cap go %d %d\r', len, dsamp));
      if (err)
        fprintf('ERR: qna_class.cap(): bad rsp: err %d, size %d x %d\n', ...
                  err, size(data));
      end
      if (size(data,1)~=len)
          fprintf('ERR: qna_class.cap(): requested %d, got %d\n', ...
                  len, size(data,1));
      end
    end
    
  end
end
