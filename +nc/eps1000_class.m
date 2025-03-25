% eps1000_class
%
% class ("static") functions
%   eps1000_class.parse_idn(idn)
%




% member variables ("properties")
%   eps.settings.
%         wavelen_nm: 1x2 vector of wavelengths in nm
%         pwr_dac: pump power in dac units
%         raw_out_en: 0|1
%         waveplates_deg: 1x4 vector of waveplate retardances in deg
%               
%   eps.cal.
%         ecpc_calfiles{2}
%
% member functions
%   eps=eps1000_class(port) CONSTRUCTOR. calls open, then get_settings.
%   eps.close              you may close and then re-open
%   eps.open(port)         if port absent, uses prior port
%   b=eps.isopen           returns logical
%   eps.get_settings       call, then access eps.settings structure


% in general:
%   set_* - change a setting on device
%   meas_* - measure something using device
%   cal_* - function intended for calibration only, not for general use


% Types of errors, and how handled:
%   bugs: misuse of this api.  Bug in the caller, so fix it.
%     causes a matlab crash and stack trace printout
%   communication error:
%     a windows com error could mean serial port yanked out.
%
%   garbled response:
%     could be a com error such as loss of chars due to buffer overrflow.
% 
%   operations on closed ports:
%     These routines continue silently.
%     Allows calling code to pretend as if the pa is connected, which
%     is useful for partial-system testing  if pa1000 is absent.





classdef eps1000_class < nc.ncdev_class

  properties
    dbg  % 0=none, 1=debug io
    port
    ser
    devinfo % structure of info about device
%     devinfo.can_enable_alignment : 1 = can turn on/off alignment signal, 0=cant
%     devinfo.can_switch_alignment : 1 = can set H vs D alignment, 0=cant
%     devinfo.can_set_freq         : 1 = can set pump pulse freq, 0=cant
%     devinfo.can_set_optical_atten  : 1 = can set pump atten
%     devinfo.can_set_optical_atten_dB  : 1 = can set pump atten (in dB)
%     devinfo.can_set_squeezer_rf_phase
%     devinfo.can_set_pump_phase   : 1 = can set phase of quant pulses, 0=cant
%     devinfo.can_set_wavelen      : 1 = can switch output wavelen thru TBF, 0=cant
%     devinfo.opt_pwr_ctl  -  from pwr ctl field in info string. p,n,b,d
%     devinfo.num_voa
%     devinfo.num_wp[2]  - num waveplates in each FPC
%     devinfo.efpc_pol_in_mid : 0=BATi FPC polarizer at end.  1=BATi FPC polarizer in middle
    settings % structure containing current settings
%     settings.wavelen_nm(chan)    - current wavelenths in nm
%     settings.wavelens_ochan(chan) - current wavelenths as optical channel number
%     settings.atten_dac            - optical attenuation in dac units []=not featured
%     settings.atten_dB             - opt atten in dBs. []=not featured
%     settings.hd_atten_dB          - opt atten in dBs
%     settings.colinear             - []=not featured, 0=not colinear, 1=colinear
%     settings.alignment            - o=off, h=horiz, v=vert, ?=not featured
%     settings.nomenu               - 0=verbose 1=not printing menus
%     settings.password
%    cal
    efpc1_cal
    efpc2_cal
    cal_ok
    st
    %    st.gui_mode % 1=gui mode, 0=normal (user) mode.
  end


    % Most programs should not use "gui mode".
    % the default is to not use it.
    %       Usually when writing matlab code that uses the NuCrypt API
    %       it's most convenient if commands take as long as necessary,
    %       within reason, before returning.  For example, you could set
    %       the splitting ratio with the following code:
    %
    %               eps.set_splitting_pct(50);
    %
    %       This function might take about a minute before it returns.
    %
    %       However, this API is also used by the GUI (epa.exe) that must sometimes
    %       be more responsive to user input. (such as to the "abort" button).
    %       The GUI calls the constructor with:
    %               opt.gui_mode=1
    %       The GUI isn't multithreaded,  so any command it calls must return within
    %       about one second in order to properly handle other things.
    %       If commands don't finish, the GUI calls them again.
    %       So the GUI code is written in a more awkward manner:
    %
    %              while(!abort_btn)
    %                [done rsp] = eps.set_splitting_pct(50);
    %                fprintf(rsp); % or do some other thing with rsp
    %                if (done)
    %                  break;
    %                end
    %                if (abort_btn_pressed)
    %                  eps.set_splitting_pct_abort();
    %                end
    %              end
    %
    %  gui_mode=0 saves most programmers from having to do it like that.
  
  properties (Constant=true)

    %           optchan  wl(nm) epschan
    TBFPA_WL2CHAN = [20  1547.7   2
                     19  1548.5   2  
                     18  1549.3   2
                     17  1550.1   2
                     16  1550.9   2
                     15  1551.7   2
                     14  1552.5   2
                     13  1553.3   0
                     12  1554.1   0
                     11  1554.9   0
                     10  1555.7   0
                      9  1556.5   0
                      8  1557.3   1
                      7  1558.1   1
                      6  1558.9   1
                      5  1559.7   1
                      4  1560.5   1];
    % Note: epschan 1=idler, 2=signal
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function cal = read_calfile(fname)
      cal = nc.pa1000_class.read_calfile(fname);
    end


    function [err msg_rsp cal] = parse_printcal_rsp(devinfo, rsp)
      %   msg_rsp : cell array of user feedback strings
      msg_rsp={};
      err=0;
      cal.voa_calfile  = nc.ser_class.parse_keyword_val(rsp, 'voa_calfile', '');


      cal.calfile = nc.ser_class.parse_keyword_val(rsp, 'calfile', '');
      if (isempty(cal.calfile))
        cal.calfile = nc.ser_class.parse_keyword_val(rsp, 'efpc_calfile', '');
      end
%      cal.calfile2     = nc.ser_class.parse_keyword_val(rsp, 'efpc_calfile', '');
      cal.no_wl_interp = nc.ser_class.parse_keyword_val(rsp, 'no_wl_interp', 0);

%      fpc0_dac = nc.ser_class.parse_keyword_val(rsp, 'cfg fpc 0', 0);
%      fpc1_dac = nc.ser_class.parse_keyword_val(rsp, 'cfg fpc 1', 0);
%      me.settings.fpc_dac = [fpc0_dac; fpc1_dac];
%      me.settings.fpc_deg = zeros(size(me.settings.fpc_dac));
      
      num_pc       = (nc.ser_class.parse_keyword_val(rsp, 'num_pc',0)==1);
      % if num_pc is zero, that means it hasn't been calibrated yet.  Otherwise it's
      % always 1, even though there are two fpcs in this device.  This is because of
      % the use of "common code".  We don't use the OZ fpc in any other device.
      % It's awkward.  Its calibration info is diminutive, different, and handled as
      % a special case.

      if (num_pc)
        pc=1;
        cal.num_wp(pc)=nc.ser_class.parse_keyword_val(rsp, sprintf('pc%d_num_wp', pc-1),0);
        for wp_i=1:cal.num_wp(pc)
          ax = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwp%dax', pc-1, wp_i-1), 0);
          cal.wp_axes(1:3,wp_i)=ax;
        end
        cal.num_wl(pc)=nc.ser_class.parse_keyword_val(rsp, sprintf('pc%d_num_wl', pc-1),0);
%        cal.num_wl(pc)
        wls_nm = zeros(1,cal.num_wl(pc));
        for wl_i=1:cal.num_wl(pc)
          wl_nm = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%d', pc-1, wl_i-1), 0);
          wls_nm(wl_i)=wl_nm;
          iv = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%div', pc-1, wl_i-1), 0);
          for wp_i=1:cal.num_wp(pc)
            co = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%dwp%dco', pc-1, wl_i-1, wp_i-1), 0);
          end
        end
        cal.pc_wavelens{pc}=wls_nm;
      else
        cal.wp_axes=[1 0 0; 0 1 0; 1 0 0; 0 1 0].';
      end
    end

    
    function [optchan epschan wl_nm] = wavelen_nm2chan(wl_nm)
    % desc: converts wavelength from units of nm to channel number
    % inputs
    %    wl_nm: wavlength in nm.
    % returns: 
    %    optchan: 0=not found, otherwise 4...20
    %    epschan: 0=not found, 1=idler, 2=signal
    %    wl_nm: actual wavelength (closest found, within reason)
      tmp = nc_eps.TBFPA_WL2CHAN;
      idx = find(abs(tmp(:,2)-wl)<=.05,1);
      if (isempty(idx))
        optchan = 0;
        epschan = 0;
      else
        optchan = nc_eps.TBFPA_WL2CHAN(idx,1);
        epschan = nc_eps.TBFPA_WL2CHAN(idx,3);
	wl_nm   = nc_eps.TBFPA_WL2CHAN(idx,2);
      end
    end

    function wl_nm = wavelen_chan2nm(optchan)
    % inputs: optchan: optical channel number 4..20
    % rerturns: wl: 0=not found, -1=unknown chan, otherwise whatever
      if (optchan==-1)
        wl_nm      = -1;
%       epschan = -1;
        return;
      end
      tmp = nc_eps.TBFPA_WL2CHAN;
      idx = find(tmp(:,1)==optchan,1);
      if (isempty(idx))
        wl_nm = 0;
%       epschan = 0;
      else
        wl_nm      = nc_eps.TBFPA_WL2CHAN(idx,2);
%       epschan = nc_eps.TBFPA_WL2CHAN(idx,3);
      end
    end



    % static
    function devinfo = parse_idn(idn)
% always sets:
%      devinfo.dsf_split:
%      devinfo.opt_pwr_ctl:
%      devinfo.rate: 
%      devinfo.is_timein
      import nc.*
      if (~isstruct(idn))
        error('eps1000_class.parse_idn: idn must be a structure');
      end
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);

      devinfo = idn;

      for_fwver = [7 3 4];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: eps1000_class(): This software was written for EPS firmwares %s and below\n', util.ver_vect2str(for_fwver));
        fprintf('      but EPS is has firmware %s and might not work with this +nc package\n', ...
                util.ver_vect2str(devinfo.fwver));
      end
      
      % default EPS
      devinfo.num_chan = 1; % one entangled pair
      devinfo.num_fpc = 2; % two fpcs
      devinfo.dsf_split = 's';
      devinfo.opt_pwr_ctl = 'd';
      devinfo.can_set_freq = nc.util.ver_is_gte(devinfo.fwver, [7 0]);
      devinfo.can_set_optical_atten_dB = nc.util.ver_is_gte(devinfo.fwver, [6 1]);      
      devinfo.can_set_optical_atten = nc.util.ver_is_gte(devinfo.fwver, [6 1]);      
      devinfo.can_set_ref_freq = nc.util.ver_is_gte(devinfo.fwver, [7 2]); % but can 7.0 do this?
      devinfo.can_switch_raw_out = 0;
      devinfo.can_set_clkout = nc.util.ver_is_gte(devinfo.fwver, [7 2]);
      
      devinfo.can_set_split = nc.util.ver_is_gte(devinfo.fwver, [7 2]);
      devinfo.can_set_waveguide_temp_offset = nc.util.ver_is_gte(devinfo.fwver, [7 3 0]);
      devinfo.can_meas_split = nc.util.ver_is_gte(devinfo.fwver, [7 3 0]);
      devinfo.rate = 'm';
      devinfo.is_timebin = 0;
      devinfo.can_change_wavelen = 0;
      devinfo.can_abort_align_sagnac = 0;
      devinfo.supports_flash_write = 1;
      devinfo.num_voa=1;
      devinfo.num_wp=[4 4];
      devinfo.d_align_offset_deg = 0;

      devinfo.can_enable_alignment = nc.util.ver_is_gte(devinfo.fwver, [5 0 2]);
      devinfo.has_diag_cmd = nc.util.ver_is_gte(devinfo.fwver, [7 0 0]);
      devinfo.has_status_cmd = nc.util.ver_is_gte(devinfo.fwver, [7 0 0]);
      devinfo.num_voa = 1+nc.util.ver_is_gte(devinfo.fwver, [7 2 0]);
      devinfo.can_set_wavelen = 0; % requires TBF
      devinfo.can_set_hd_atten = nc.util.ver_is_gte(devinfo.fwver, [7 2 0]);

      devinfo.can_set_squeezer_rf_phase = 0; % might be set nonzero in get_settings
      devinfo.can_set_pump_phase = 0; % nc.util.ver_is_gte(devinfo.fwver, [7 2 0]);
      % temp alarm wasnt correct in 7.3.3 but is in 7.3.4
      devinfo.has_temp_alarm = nc.util.ver_is_gte(devinfo.fwver, [7 3 4]);
      

      % During a brief time, certain settings intended for general use
      % were only accessible in the calibration menu.
      devinfo.set_split_using_cal = nc.util.ver_is_gte(devinfo.fwver, [5 0]) ...
          && ~nc.util.ver_is_gte(devinfo.fwver, [7 3 3]);

      
      % C1
      k=3;
      if(k>num_flds)
	return;
      end
      devinfo.dsf_split = lower(flds{k}(1));
      devinfo.is_timebin = (devinfo.dsf_split=='t');
      if (devinfo.is_timebin)
        devinfo.can_set_split=0;
      end

      k = k + 1;
      if(k>num_flds)
        return;
      end
   
      % C2
      devinfo.opt_pwr_ctl = lower(flds{k}(1));
%      if ((devinfo.opt_pwr_ctl=='b')||(devinfo.opt_pwr_ctl=='d'))
%        devinfo.pwr_lims = [0 3800]; % optical atten range (dac)
%      else
%        devinfo.pwr_lims = [0 1200]; % must be laser pwr range
%      end
      k = k + 1;
      if(k>num_flds)
        return;
      end
      devinfo.atten_is_dB=1; % WRONG for old ones!

      % C3
      devinfo.rate = lower(flds{k}(1));
%     devinfo.fwver
%     devinfo.rate
%nc.util.ver_is(devinfo.fwver, [4 0])
      % fwver5.0 identifies as 4.0. It is a lie!
      if (nc.util.ver_is(devinfo.fwver, [4 0]) && (devinfo.rate~='g'))
        % not sure if this test works in all cases, but I had to do something for ARL.
        devinfo.fwver = [5 0];
      end
      
      
      k = k + 1;
      if(k>num_flds)
        return;
      end

      % C4
      k = k + 1;
      if(k>num_flds)
        return;
      end

    end


    function t = therm_Ohms2C(beta, r_Ohms)
    % desc: convert thermistor Ohms to C.
      rinf_Ohms=10.0e3*exp(-beta/(25.0+273.15));
      t = beta/log(r_Ohms/rinf_Ohms) - 273.15;
    end

    function r = therm_C2Ohms(beta, t_C)
    % desc: convert thermistor C to Ohms.
      rinf_Ohms = 10.0e3*exp(-beta/(25.0+273.15));
      r = exp(  beta/(t_C+273.15)) * rinf_Ohms;
    end
    
  end

  methods

    % CONSTRUCTOR
    function me = eps1000_class(arg1, opt)
    % desc: constructor
      % use:
      %   obj = eps1000_class(ser, opt)
      %           ser: a ser_class object
      %   obj = eps1000_class(port, opt)
      import nc.*
      me.ser = [];
      me.devinfo = [];
      me.cal_ok = 0;
      me.efpc1_cal=[];
      me.efpc2_cal=[];
      me.settings.password='';
      if (nargin<1)
	port='';
      end
      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'baud', 115200);
      opt = util.set_field_if_undef(opt, 'gui_mode', 0);
      opt = util.set_field_if_undef(opt, 'notopen_is_ok', 0);
      opt = util.set_field_if_undef(opt, 'timo_is_ok', 0);
      me.dbg = opt.dbg;
      me.st.gui_mode=opt.gui_mode;
      me.st.running=0;
      me.st.timo_is_ok=opt.timo_is_ok;

      if (ischar(arg1))
	me.open(arg1, opt);
      elseif (~strcmp(class(arg1),'nc.ser_class'))
        error('first param must be portname or ser_class');
      else
        me.ser = arg1;
	if (~me.ser.isopen())
	  me.ser.open();
	end
	if (me.ser.isopen())
          % if already open, me.open() wont get idn or update devinfo.
	  % but for constructor we do always want that!
	  if (isempty(me.ser.idn))
            me.ser.get_idn_rsp; % identity structure	  
	  end
	  me.devinfo=me.parse_idn(me.ser.idn);
          me.set_nomenu(1);
          me.get_version_info();          
          me.get_settings();
	end
      end
      if (~opt.notopen_is_ok && ~me.ser.isopen())
        error('ERR: eps1000_class() cannot open device');
      end
    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function open(me, portname, opt)
    % inputs:
    %   port: optional string.  If omitted, uses port previously used
% should always do idn on a fresh open.      
      import nc.*

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
      freshopen = 1;
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      else
	freshopen = 0;
      end
      if (me.ser.isopen() && freshopen)
        me.ser.get_idn_rsp; % identity structure
        me.devinfo = me.parse_idn(me.ser.idn);
        me.set_nomenu(1);
        me.get_version_info();
        me.get_settings();	
      end
    end

    function close(me)
      me.ser.close;
    end

    function f=isopen(me)
      f=me.ser.isopen();
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    function set_nomenu(me, nomenu)
      me.settings.nomenu = 0;
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 0 0]))
        me.settings.nomenu = nomenu;
        if (nomenu)
          me.ser.do_cmd('n'); % nomenus
        else
          me.ser.do_cmd('i'); % nomenus
        end
      end
    end
    



    function err=cal_set_efpc_cal(me, pc_i, cal)
% NOTE: This code expects a sequence of prompts as supplied by
%       efpc_ask_cal() in "common code" efpc.c (which uses zero-base indexing)
      import nc.*
      err=0;

      if (me.goto_cal_menu())
        err=1;
        return;
      end
      
      k = size(cal.dac2ph_coef,1)/3;
      coef_per_wp = util.ifelse(k==round(k),3,2);
        
      for pc_i=1:cal.num_pc
        if (any(any(cal.dac2ph_coef(1:coef_per_wp+(pc_i-1)*coef_per_wp,:))))
          if (pc_i==1)
            me.ser.do_cmd('1');
            me.ser.do_cmd([cal.fname char(13)]);
            me.ser.do_cmd(['1' char(13)]); % num_pc =1
            me.ser.do_cmd(sprintf('%d\r', cal.no_wl_interp));
            num_wp = cal.num_wp(pc_i);
            [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', num_wp));
            if (~err && (m~= num_wp))
              fprintf('ERR: not as many physical waveplates as in calibration\n');
              num_wp = m;
            end
            % FUTURE: get pc_type which will be per-pc.
            me.ser.do_cmd([cal.pc_type char(13)]);
            
            for wp_i=1:num_wp
              for a_i=1:3
                me.ser.do_cmd(sprintf('%g\r', cal.wp_axes((pc_i-1)*3+a_i,wp_i)));
              end
            end

            rsp = me.ser.do_cmd(sprintf('%d\r', length(cal.pc_wavelens{pc_i})));
            for wl_i=1:length(cal.pc_wavelens{pc_i})
              if (~strfind(lower(rsp), sprintf('wl%d ',wl_i)))
                 fprintf('ERR: not being prompted for wl at expected time\n');
                 fprintf('     instead prompt was: ');
                 uio.print_all(rsp);
              end
              me.ser.do_cmd(sprintf('%f\r', cal.pc_wavelens{pc_i}(wl_i)));
              k=(wl_i-1)*cal.num_pc;
              for a_i=1:3
                me.ser.do_cmd(sprintf('%.5g\r', cal.int_align(k+pc_i, a_i)));
              end
              k=(wl_i-1)*cal.num_pc*coef_per_wp + (pc_i-1)*coef_per_wp;
              for wp_i=1:num_wp
                for co_i=1:2 % in teps, pc_i=1 is BATi, and only two coef used
                  rsp = me.ser.do_cmd(sprintf('%g\r', cal.dac2ph_coef(k+co_i, wp_i)));
                end
              end
            end
            break;

          else % pc_1==2
            me.ser.do_cmd('2');
            me.ser.do_cmd([cal.fname char(13)]);
            num_wp = cal.num_wp(pc_i);            
            [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', num_wp));
            if (~err && (m~= num_wp))
              fprintf('ERR: not as many physical waveplates as in calibration\n');
              num_wp = m;              
            end

            if (cal.pc_type=='o') % OZ
              if (coef_per_wp~=3)
                error('ERR: OZ fpc needs three coef for pc2 dac2ph map\n');
              end
            end

            for wp_i=1:num_wp
              k=(pc_i-1)*coef_per_wp;
              for co_i=1:coef_per_wp
                me.ser.do_cmd(sprintf('%g\r', cal.dac2ph_coef(k+co_i, wp_i)));
              end
            end
            for wp_i=1:num_wp
              k=(pc_i-1)*2;
              for r_i=1:2
                me.ser.do_cmd(sprintf('%d\r', cal.dac_range(k+r_i, wp_i)));
              end
            end
            
          end
          break;
        end % if any non-zero coef
      end % for pc
      
      me.ser.do_cmd('e');
    end

    function [err msg_rsp] = get_fpc_cal(me)
      import nc.*
      if (~me.goto_cal_menu())
        rsp=me.ser.do_cmd('x');
        [err msg_rsp me.efpc1_cal] = me.parse_printcal_rsp(me.devinfo, rsp);
        me.cal_ok = ~err;

        rsp=me.ser.do_cmd('y');
        [err msg_rsp me.efpc2_cal] = me.parse_printcal_rsp(me.devinfo, rsp);
        me.cal_ok = me.cal_ok && ~err;
        
        me.ser.do_cmd('e');        
      end
    end
    
    function get_cal_settings(me)
      if (~me.goto_cal_menu())
        rsp=me.ser.do_cmd('p'); % config menu
        me.ser.do_cmd('e');

        me.settings.waveplates_deg = me.ser.parse_keyword_val(rsp,'efpc1_deg',[]);
        me.settings.voa_calfiles=cell(me.devinfo.num_voa,1);
        me.settings.laser_temp_dac = me.ser.parse_keyword_val(rsp,'laser_temp_dac',0);
        me.settings.waveguide_temp_dac = me.ser.parse_keyword_val(rsp,'wg_temp_dac',0);


        if (~nc.util.ver_is_gte(me.devinfo.fwver, [7 3 3]))
          % as of 7.3.3, these settings revealed by "S' command,
          % and are no longer set in the config menu.
          me.settings.splitting_pct = me.ser.parse_keyword_val(rsp,'splitting_pct',50);
          me.settings.laser_temp_offset_dac = me.ser.parse_keyword_val(rsp,'laser_temp_offset',0);
          me.settings.waveguide_temp_offset_dac = me.ser.parse_keyword_val(rsp,'wg_temp_offset',0);
        end
        
        for k=1:me.devinfo.num_voa
          me.settings.voa_calfiles{k} = me.ser.parse_keyword_val(rsp, sprintf('voa%d_calfile', k),'');
          me.settings.voa_dB2dac{k} = me.ser.parse_keyword_val(rsp, sprintf('voa%d_dB2dac', k),'');

        end
      end
    end
    
    function get_version_info(me)
    % desc: futher fills out devinfo structure
      import nc.*
      if (util.ver_is_gte(me.devinfo.fwver, [7 2]))
        rsp = me.ser.do_cmd('v');
        me.devinfo.d_align_offset_deg = me.ser.parse_keyword_val(rsp, 'd_align_offset_deg', 0);
        me.devinfo.can_set_pump_phase = me.ser.parse_keyword_val(rsp, 'can_set_pump_phase', 0);
        me.devinfo.can_set_wavelen    = me.ser.parse_keyword_val(rsp, 'can_set_wavelen', 0);
        me.devinfo.can_switch_raw_out = me.ser.parse_keyword_val(rsp, 'can_switch_raw_out', 0);
        me.devinfo.efpc_pol_in_mid    = me.ser.parse_keyword_val(rsp, 'efpc_pol_in_mid', 0);
        if (me.devinfo.efpc_pol_in_mid)
          me.devinfo.num_fpc = 1;
        end
        % new as of 7 3 3:
        me.devinfo.laser_therm_beta_K = me.ser.parse_keyword_val(rsp, 'lsr_therm_beta_K', 3375);
      else
        me.devinfo.d_align_offset_deg = 0;
        me.devinfo.can_set_pump_phase = 0;
        me.devinfo.can_set_wavelen    = 0;
        me.devinfo.can_switch_raw_out = 0;
        me.devinfo.efpc_pol_in_mid    = 0;
        me.devinfo.num_fpc = 0;
        me.devinfo.laser_therm_beta_K = 3375;
        % fprintf('WARN: eps100_class.get_ver(): not supported by this firmware\n');
      end
    end
    
    function stat = get_status(me)
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 2]))
        rsp = me.ser.do_cmd('T');
        stat.pll_lock         = me.ser.parse_keyword_val(rsp, 'pll_lock', 0);
        stat.edfa_on          = me.ser.parse_keyword_val(rsp, 'edfa_on', 0);
        stat.oam_bias_fb_lock = me.ser.parse_keyword_val(rsp, 'oam_bias_fb_lock', 0);
        stat.laser_temp_mV    = me.ser.parse_keyword_val(rsp, 'laser_temp_mV', 0);
        stat.laser_temp_C     = me.laser_temp_mV2C(stat.laser_temp_mV);
        stat.laser_temp_mV    = me.ser.parse_keyword_val(rsp, 'laser_temp_mV', 0);
        stat.waveguide_temp_C  = me.ser.parse_keyword_val(rsp, 'waveguide_temp_C', 0);
        
        stat.waveguide_temp_mV = me.ser.parse_keyword_val(rsp, 'waveguide_temp_mV', 0);
        stat.waveguide_temp_alarm = 0;
        stat.waveguide_temp_err_C = 0;
        if (me.devinfo.has_temp_alarm)
          stat.waveguide_temp_alarm = me.ser.parse_keyword_val(rsp, 'waveguide_temp_alarm', 0);
          stat.waveguide_temp_err_C = me.ser.parse_keyword_val(rsp, 'waveguide_temp_err_C', 0);
        end
        stat.sagnac_1550      = me.ser.parse_keyword_val(rsp, 'sagnac_1550', 0);
        stat.sagnac_780       = me.ser.parse_keyword_val(rsp, 'sagnac_780', 0);
        stat.splitting_pct    = me.ser.parse_keyword_val(rsp, 'split_pct', 0);
        stat.clkout_lock      = me.ser.parse_keyword_val(rsp, 'clkout_lock', 0);
        stat.oam_lock_dur_s   = me.ser.parse_keyword_val(rsp, 'oam_lock_dur_s', -1);
      end
    end


    
    function get_settings(me)
     % desc: gets current settings.
     %   fills in a few devinfo fields too, although that is the old way
     %   of doing things, and new devinfo fields should be filled in by
     %   parse_idn or get_version_info().
      me.settings.atten_dac=[];
      me.settings.atten_dB=[];
      me.settings.wavelen_nm=[0 0];
      me.settings.wavelens_ochan=[0 0];
      me.settings.colinear = []; % not featured
      me.settings.alignment = '?'; %not featured
      me.settings.freq_MHz = [];
      me.settings.ref_freq_MHz = 0;
      me.settings.hd_atten_dB = 0;
      me.settings.clkout_freq_MHz = 0;
      me.settings.pump_phase_ps = 0;

      if (nc.util.ver_is_gte(me.devinfo.fwver, [5 0]))
%    rsp = pdev_cmd(pdev_h, 'p'); % print DAC values
%    state.pwr = str_val_find(rsp,'DAC2-0',0,1,0);
        rsp = me.ser.do_cmd('S'); % print "settings"
        me.settings.rf_phase = me.ser.parse_keyword_val(rsp, 'rf_phase', []); % v4.1 only?  or v7.0?  empty means cant optimize rf pulse using rf_phase
        me.devinfo.can_set_squeezer_rf_phase = ~isempty(me.settings.rf_phase);

        me.settings.hd_atten_dB = me.ser.parse_keyword_val(rsp, 'hd_attn_dB', []);
        if (isempty(me.settings.hd_atten_dB))
          % obsolete label was used in 7.2.0
          me.settings.hd_atten_dB = me.ser.parse_keyword_val(rsp, 'align_atten_dB', 0);
        end
        me.settings.clkdiv = me.ser.parse_keyword_val(rsp, 'clkdiv', 1);
        
        me.settings.freq_MHz = me.ser.parse_keyword_val(rsp, '\Wfreq_MHz', []);
        me.settings.ref_freq_MHz = me.ser.parse_keyword_val(rsp, 'ref_MHz', []);
        me.settings.pump_phase_ps = me.ser.parse_keyword_val(rsp, 'pump_phase_ps', 0);
        me.settings.clkout_freq_MHz = me.ser.parse_keyword_val(rsp, 'clkout_freq_MHz', []);
        me.settings.atten_dB = me.ser.parse_keyword_val(rsp, 'voa_setting_dB', []);
        me.settings.enable_raw_out = me.ser.parse_keyword_val(rsp, 'enable_raw_out', []);
        
        voa = me.ser.parse_keyword_val(rsp, 'voa_settings_dac', []);
        if (isempty(voa)) % prior to 7.2
          voa = me.ser.parse_keyword_val(rsp, 'voa_setting', []);
          if (isempty(voa)) % really OLD version
            voa = me.ser.parse_keyword_val(rsp, 'VOA setting', []);
          end
        end
        me.settings.atten_dac = voa;
        
        str = lower(me.ser.parse_keyword_val(rsp, 'colinear_output', 'x'));
	if (~isempty(str)) str = str(1); end
        % should be: x=not featured, u=unknown, n=not_colinear, e=colinear
	if (str=='u') str='n'; end
	if (str=='x') 
	  state.colinear = []; % means not featured
        else
	  state.colinear = (str=='e');
        end

	s = me.ser.parse_keyword_val(rsp,'align_setting','?');
	if (s=='?')
	  s = me.ser.parse_keyword_val(rsp,'Switch Status','?'); % OLD
        end
        if (isempty(s)) s = '?'; end
        me.settings.alignment = lower(s(1)); % should be: h, d, o, or ?
        % old version might be H or D but never O.  then just because its H or D
	% does not mean alignment light is on.
        
	% wavelens: 0=not readable/settable.  -1=unknown.  otherwise in nm
	me.settings.wavelens_ochan(1) = me.ser.parse_keyword_val(rsp,'idler_filter_channel',0);
	me.settings.wavelens_ochan(2) = me.ser.parse_keyword_val(rsp,'signal_filter_channel',0);
        me.settings.wavelen_nm(1) = me.wavelen_chan2nm(me.settings.wavelens_ochan(1));
        me.settings.wavelen_nm(2) = me.wavelen_chan2nm(me.settings.wavelens_ochan(2));

        me.settings.waveplates_deg = me.ser.parse_keyword_val(rsp,'efpc1_deg', [0 0 0 0]);
      end
      me.devinfo.can_switch_alignment = ~strcmp(me.settings.alignment,'?');

      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3 3]))
        me.settings.waveguide_temp_offset_dac = me.ser.parse_keyword_val(rsp,'wg_temp_offset', 0);
        me.settings.laser_temp_offset_dac = me.ser.parse_keyword_val(rsp,'laser_temp_offset', 0);
        me.settings.splitting_pct = me.ser.parse_keyword_val(rsp,'splitting_pct', 50);
      else
        me.settings.waveguide_temp_offset_dac = 0;
        me.settings.laser_temp_offset_dac = 0;
        me.settings.splitting_pct = 50;
      end

      if (me.devinfo.set_split_using_cal)
        me.ser.do_cmd('9'); % debug
        rsp = me.ser.do_cmd('o'); % print debug serttings
        me.settings.laser_temp_offset_dac     = me.ser.parse_keyword_val(rsp,'laser_temp_offset', 0);
        me.settings.waveguide_temp_offset_dac = me.ser.parse_keyword_val(rsp,'wg_temp_offset', 0);
        me.ser.do_cmd('e'); % debug
      end
    end

    function align_sagnac_polarization(me)
      if (~me.devinfo.is_timebin)
        me.ser.do_cmd('1');
      end
    end
    
    function [rsp done] = align_sagnac_polarization_and_get_rsp(me, start)
      % desc: This is an alternate way to do align_sagnac_loop(), typically
      %   used by GUIs that need to provide nice feedback to the user.
      %   This always returns after one second, whether or not rxed any rsp.
      % inputs: start: 1=issue command, 0=just check rsp
      % returns: done: 0=not done, 1=done
      if (me.devinfo.is_timebin) done=1; return; end
      if (start)
        [rsp err] = me.ser.do_cmd('1');
        done = (err==0);
      else
        [rsp done met_timo] = me.ser.read(-1, 1000, '>');
      end
    end

    function [rsp done] = align_sagnac_polarization_abort(me)
      me.ser.write('e');
    end
    
    function [rsp done] = issue_diag_and_get_rsp(me, start)
      % desc: typically
      %   used by GUIs that need to provide nice feedback to the user.
      %   This always returns after one second, whether or not rxed any rsp.
      % inputs: start: 1=issue command, 0=just check rsp
      % returns: done: 0=not done, 1=done
      if (start)
        [rsp err] = me.ser.do_cmd('d');
        done = (err==0);
      else
        [rsp done met_timo] = me.ser.read(-1, 1000, '>');
      end
    end

    
    
    function set_alignment(me, mode)
      % mode: 'h'=H, 'd'=D, 'o' = alignment source off
      % NOTE: EPS gives same response whether or not it implements H or D,
      % that is, it just reprints the main menu.
      % fprintf('DBG: eps1000_classs.set_alignment\n');
      if (~me.devinfo.can_switch_alignment)
        error('eps1000_class.set_alignment: unsupported by this firmware');
      end
      mode=lower(mode);
      if ((mode~='o')&&(mode~='h')&&(mode~='d'))
        error('eps1000_class.set_alignment: bad mode');
      end
      me.ser.do_cmd(upper(mode));
      me.settings.alignment=mode;
    end

    function set_colinear(me, en)
    % must do get_settings at least once sometime before calling this.
      if (~isempty(me.settings.colinear))
	if (en)
	  cmd='C';
	else
	  cmd='B';
	end
	me.ser.do_cmd(cmd);
	me.settings.colinear = en;
      end
    end

    function set_optical_atten_dB(me, atten_dB)
      % sets optical attenuation in dB units, inversely affecting quantum output power
      % newer EPSs may have more than one VOA, but the presumption here is that
      % we mean the main VOA that controls quantum power.
      if (~me.devinfo.can_set_optical_atten_dB)
        fprintf('ERR: eps100_class.set_optical_atten_dB: not supported by this firmware\n');
        return;
      end
      me.ser.do_cmd('V');
      me.ser.do_cmd('w');
      if (nc.util.ver_is_gte(me.devinfo.fwver, [6 2]))
        [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dB) 13]);
        if (~err && (length(m)==1))
          me.settings.atten_dB(1) = m;
        end
      else % older version does not respond with actual setting
        me.ser.do_cmd([num2str(atten_dB) 13]);
        me.get_settings(); % this is a slower way
      end
    end

    function set_hd_atten_dB(me, atten_dB)
      if (me.devinfo.can_set_hd_atten)
        me.ser.do_cmd('a');
        if (nc.util.ver_is_gte(me.devinfo.fwver, [7 2 1]))
          [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dB) 13]);
          if (~err && (length(m)==1))
            me.settings.hd_atten_dB = m;
          end
        else
          me.ser.do_cmd([num2str(atten_dB) 13]);
          me.settings.hd_atten_dB = atten_dB;
        end
      else
        fprintf('ERR: eps1000_class.set_hd_atten_dB():\n');
        fprintf('     cannot set the attenuation of the HD alignment signal with this hardware\n');
      end
    end
    
    function set_ref_freq_MHz(me, f_MHz)
      if (me.devinfo.can_set_ref_freq)
        me.ser.do_cmd('F');
        [m err]=me.ser.do_cmd_get_matrix([num2str(f_MHz) 13]);
	if (~err&& (length(m)==1))
          me.settings.ref_freq_MHz= m;
        end
      else
        fprintf('ERR: eps1000_class.set_ref_freq_MHz(%g)\n', f_MHz);
        fprintf('     cannot set clock ref with this hardware\n');
      end
    end
    
    function set_freq_MHz(me, f_MHz)
    % sets frequency of pump pulses
    % f_MHz - double
      if (me.devinfo.can_set_freq)
        me.ser.do_cmd('f');
        [m err]=me.ser.do_cmd_get_matrix([num2str(f_MHz) 13]);
	if (~err&& (length(m)==1))
          me.settings.freq_MHz= m;
          % if the EPS allows clkout to be set independently,
          % changing pump freq wont change clkout.  Otherwise it will
          if (~me.devinfo.can_set_clkout)
            me.settings.clkout_freq_MHz = m;
          end
        end
      else
        fprintf('ERR: eps1000_class.set_freq_MHz(%g)\n', f_MHz);
        fprintf('     this hardware cant change pump freq\n');
      end
    end
    
    function set_waveguide_temp_offset_dac(me, off)
      if (~me.devinfo.can_set_waveguide_temp_offset)
        error('eps1000_class.set_waveguide_temp_offset_dac()\nThis firmware does not have the waveguide temperature offset feature');
      end
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3 3]))
        me.ser.do_cmd('w'); % tweak menu
        me.ser.do_cmd('w');
      else % old method was in debug menu
        me.ser.do_cmd('9');
        me.ser.do_cmd('W');
      end
      me.ser.do_cmd('w');
      [m err] = me.ser.do_cmd_get_matrix([num2str(off) 13]);
      if (~err&& (length(m)==1))
        me.settings.waveguide_temp_offset_dac = m;
      end
      me.ser.do_cmd('e');
    end
    
    function cal_set_waveguide_temp_dac(me, temp)
      me.goto_cal_menu();
      me.ser.do_cmd('w');
      me.ser.do_cmd('w');
      [m err] = me.ser.do_cmd_get_matrix([num2str(temp) 13]);
      if (~err&& (length(m)==1))
        me.settings.waveguide_temp_dac = m;
      end
      me.ser.do_cmd('e');
    end

    function set_laser_temp_offset_dac(me, off)
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3 3]))
        me.ser.do_cmd('w'); % tweak menu
        me.ser.do_cmd('t');
      else % old method was in debug menu
        me.ser.do_cmd('9');
        me.ser.do_cmd('L');
      end
      me.ser.do_cmd('w');
      [m err] = me.ser.do_cmd_get_matrix([num2str(off) 13]);
      if (~err&& (length(m)==1))
        me.settings.laser_temp_offset_dac = m;
      end
      me.ser.do_cmd('e');
    end
    
    function cal_set_laser_temp_dac(me, temp)
      me.goto_cal_menu();
      me.ser.do_cmd('t');
      me.ser.do_cmd('w');
      [m err] = me.ser.do_cmd_get_matrix([num2str(temp) 13]);
      if (~err&& (length(m)==1))
        me.settings.laser_temp_dac = m;
      end
      me.ser.do_cmd('e');
    end

    function set_clkout_freq_MHz(me, f_MHz)
    % desc: sets frequency of clkout
    % f_MHz - double
      if (me.devinfo.can_set_clkout)
        me.ser.do_cmd('k');
        [m err]=me.ser.do_cmd_get_matrix([num2str(f_MHz) 13]);
	if (~err&& (length(m)==1))
          me.settings.clkout_freq_MHz= m;
        end
        me.ser.do_cmd(char(13));
      else
        fprintf('ERR: eps1000_class.set_clkout_freq_MHz(%g)\n', f_MHz);
        fprintf('     this hardware cant change clkout freq\n');
      end
    end
    
    function set_squeezer_rf_phase(me, ph_dac)
      % desc: sets phase of sinusoidal signal feeding an optical
      % phase modulator that acted to "squeeze" the pump pulse.
      % NOTE: was called set_rf_phase()
      % Only ever relevant to one or two EPSs.  obsolete hardware
      if (me.devinfo.can_set_squeezer_rf_phase)
        me.ser.do_cmd('P');
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(ph_dac) 13]);
        if (~err && (length(m)==1))
           me.settings.rf_phase = m;
        end
      else
        fprintf('ERR: eps1000_class.set_squeezer_rf_phase()\n');
        fprintf('     this hardware has no pump squeezer\n');
      end
    end

    function set_pump_phase_ps(me, ph_ps)
      if (me.devinfo.can_set_pump_phase)
        me.ser.do_cmd('P');
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(ph_ps) 13]);
        if (~err && (length(m)==1))
           me.settings.pump_phase_ps = m;
        end
      else
        fprintf('ERR: eps1000_class.set_pump_phase_ps(%g)\n', ph_ps);
        fprintf('     this hardware cant change pump phase\n');
      end
    end
    
    function err=save_settings_in_flash(me)
      rsp=me.ser.do_cmd('s');
      err = me.ser.parse_keyword_val(rsp, 'flash err', 0);
    end
    
    function cal_set_password(me, pwd)
      me.settings.password=pwd;
    end

    function err=goto_cal_menu(me, pwd)
    % The purpose of the password protection of the cal menu
    % is to prevent users from accidentally changing calibration
    % information (stored in the flash) that is required for
    % proper operation.
      err=0;
      if (nargin<2)
	pwd=me.settings.password;
      else
	me.settings.password=pwd;
      end
      rsp=me.ser.do_cmd('c'); % config menu
      if (strfind(rsp,'password'))
	[rsp err] = me.ser.do_cmd([pwd 13]);
        if (~strfind(rsp, 'onfiguration'))
          fprintf('ERR: maybe "%s" is the wrong password\n', pwd);
          return;
        end
      end
    end
    
    function cal_set_d_align_offset(me, offset_deg)
      if (me.goto_cal_menu())
	return;
      end
      offset_deg =round(offset_deg);
      rsp = me.ser.do_cmd('6');
      for ln=1:100
        if (~isempty(strfind(rsp,'d_align_offset_deg')))
          rsp = me.ser.do_cmd(sprintf('%d\r',offset_deg));
          me.devinfo.d_align_offset_deg = offset_deg;
          ok=1;
        elseif (strfind(rsp,'config menu'))
          break;
        % in nomenu mode it ought to still print "config menu"
        % but fwver 2.28 does not!  Just a CR then a >.
        elseif (length(rsp)==1)
          break;
        else
          rsp = me.ser.do_cmd(char(13));
        end
      end
      me.ser.do_cmd('e');
      me.ser.do_cmd('s'); % save settings 
   end
    
   function [rsp done] = set_splitting_pct(me, pct)
   % desc: This sets the splitting ratio through the beamsplitter of the sagnac loop.
   %       It invokes a search, which overall might take about one minute.
   % returns: if not using gui_mode, you can ignore all return values
   %  
      if (~me.devinfo.can_set_split)
        return;
      end
      ok = 0;
      pct = max(min(round(pct),100),0);
      if (me.st.gui_mode)
        if (me.st.running)
          [rsp done] = me.ser.accum_line();
          if (done)
            me.st.running=0;
            me.ser.do_cmd('e');
          end
          return;
        else
          me.st.running=1;
        end
      else
        me.ser.set_timo_ms(120e3);
      end
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3 3]))
        me.ser.do_cmd('w'); % the new tweak menu
        me.ser.do_cmd('s');
        cmd = sprintf('%d\r',pct);
        % This may take a minute or so.
        if (me.st.gui_mode)
          me.ser.start_cmd_accum(cmd);
          me.settings.splitting_pct = pct;
          rsp='';
          done=0;
        else
          [rsp err] = me.ser.do_cmd(cmd);
          if (~me.st.timo_is_ok && (err==3))
            error('timeout when reading from device');
          end
          done=1;
          me.settings.splitting_pct = pct;
          me.ser.do_cmd('e');
        end
      else % old way used pwd protected cal menu
        me.goto_cal_menu();
        rsp = me.ser.do_cmd('6');
        % This only set the goal
        while (1)
          if (~isempty(strfind(rsp,'splitting_pct')))
            rsp = me.ser.do_cmd(sprintf('%d\r',round(pct)));
            me.settings.splitting_pct = round(pct);          
            ok=1;
          elseif (strfind(rsp,'config menu'))
            break;
          else
            rsp = me.ser.do_cmd(char(13));
          end
        end
        me.ser.do_cmd('e');
        % So it had to be followed by a re-alignment
        me.align_sagnac_polarization()  % TODO: fix for gui
      end
      if (~me.st.gui_mode)
        me.ser.set_timo_ms(1000);
      end
    end
    
    function err=cal_set_voa_dB2dac_map(me, chan, fname, map, password)
    % chan: index of voa.
      err=1;
      me.ser.set_dbg(1);
      if (me.goto_cal_menu(password))
	return;
      end
      rsp = me.ser.do_cmd('v'); % set voa atten dB to dac mapping
      if (me.devinfo.num_voa>1)
        me.ser.do_cmd(sprintf('%d\r',chan));
      end
      rsp=me.ser.do_cmd([fname 13]);
      max_pieces = me.ser.parse_keyword_val(rsp, 'max', 0);
      err=0;
      if (size(map,1)>max_pieces)
	fprintf('\nERR: device accepts splines of no more than %d pieces\n', max_pieces);
	fprintf('     and spline in file has %d pieces\n', size(map,1));
        nc.uio.pause;
        err=1;
      end
      for k=1:min(size(map,1),max_pieces)
        cmd = sprintf(' %d', round(map(k,:)*1000));
        me.ser.do_cmd([cmd char(13)]);
      end
      me.ser.do_cmd(char(13));
      me.ser.do_cmd('e'); % return to main menu
      me.ser.do_cmd('s'); % save settings
    end

    function enable_raw_out(me, en)
      if (me.devinfo.can_switch_raw_out)
        me.ser.do_cmd('x');
        me.ser.do_cmd([char('0'+logical(en)) char(13)]);
        me.settings.enable_raw_out = logical(en);
      end
    end
    
    function cal_set_voa_attn_dB(me, chan, atten_dB)
                                % for use by calibration software.
      me.goto_cal_menu();
      me.ser.do_cmd('V');
      me.ser.do_cmd(sprintf('%d\r', chan));
      me.ser.do_cmd('w');
      [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dB) 13]);
      if (chan>1)
        me.ser.do_cmd('e');
      end
      if (~err && (length(m)==1))
        me.settings.atten_dB(chan) = m;
      end
    end
    
    function [errmsgs] = set_polarization(me, ch, v)
      % inputs:
      %   ch: 1..2 : specifies channel (IE the PA)  (base one)
      %              Currently you may only set polarization of PA 1.
      %   v: 3x1 stokes vector [S1 S2 S3] - desired output polarization.
      %              (need not be a unit vector... will be normalized automatically)
      %      or a char, one of: HVLRDA.
      %   Note: for [1 0 0].', all retardances are set to zero.
      import nc.*
      if (ischar(v)&&(length(v)==1))
        switch (lower(v(1)))
          case 'h'
            s=[1 0 0];
          case 'v'
            s=[-1 0 0];
          case 'd'
            s=[0 1 0];
          case 'a'
            s=[0 -1 0];
          case 'r'
            s=[0 0 1];
          case 'l'
            s=[0 0 -1];
          otherwise
            error('teps100.set_polarization(v): v must be one of HVLRDA');
        end
        me.settings.pol_name=lower(v(1));
      elseif isnumeric(v)
        if ((~isvector(v))||(length(v)~=3))
          error('teps100.set_polarization(v): v must be 3x1 matrix');
        end
        s = v;
        me.settings.pol_name=' ';
      else
        error('eps100.set_polarization(v): v must be 3x1 matrix or a char');
      end
      if (ch~=1)
        error('BUG: eps100.set_polarization(ch,v): you can only sey polarization on channel 1');
      end
      errmsgs='';
      if (isempty(me.cal))
        errmsgs='did not read waveplate calibration info from flash';
        return;
      end

      % In the teps100, light passes through FPC0 backwards, like:
      %    polarizer -> wp4(D) -> wp3(H) -> wp2(D) -> wp1(H) ->
      % If we don't vary wp4, wp3 is useless.  So we vary wp4, 3 & 2.

      % goal = pol.rot_tox(v);
      s=pol.unitize(s(:));
%      fprintf('DBG: set polarization %s\n',sprintf(' %g', s));
%      fprintf('     2:3 = %g\n',pol.mag(s(2:3)));
      %  me.settings.pol_stokes = s.'; % will be changed by set_wp
      if (pol.mag(s(2:3))<1e-3)
        mgoal = pol.muel_rot_to_h(s);
      else
        vp=pol.unitize([0; s(2); s(3)]); % project onto yz plane
        m = [1   0      0;
             0  vp(3) -vp(2);
             0  vp(2)  vp(3)];
        vr = m*s; % rotate around h to xz plane
        vr(2)=0;
        vr=pol.unitize(vr);
        m2 = [ vr(1) 0 vr(3);
               0    1  0
               -vr(3) 0 vr(1)];
        m = m2*m;
        mgoal=eye(4);
        mgoal(2:4,2:4)=m;
      end

      wp0 = 2;

      wp_axes = me.cal.wp_axes(1:3,wp0+(0:2));

      [ret_rad muel err_ms] =pol.muel_ph_for_ideal_wp(round(wp_axes), mgoal);
      [ret_rad, err_ms]= pol.muel_solve_for_xform(wp_axes, ret_rad);

% vo = pol.muel_wp(wp_axes, ret_rad)*[1 1 0 0].';
%      fprintf('diff is: %g deg\n', pol.angdiff_deg(v, vo(2:4)));

      ret_deg=zeros(1,4);
      ret_deg(wp0+(0:2)) = mod(ret_rad*180/pi,360);
      me.set_waveplates_deg(ch,1,ret_deg);

      fprintf('DBG: wps %s deg\n', sprintf(' %6.2f', me.settings.waveplates_deg));

    end

    function cal_set_voa_attn_dac(me, chan, atten_dac)
    % sets output optical attenuation in dac units
    % The relationship to optical power may be inverse or proportional, depending
    % on the type of VOA ("bright" or "dark") inside the eps1000.
    % On newer firmware versions, this function is typically only used during calibration.
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 2]))
        if (me.goto_cal_menu())
          return;
        end
        % fprintf('DBG: set_voa %d %d\n', chan, atten_dac);
        me.ser.do_cmd('7');
        me.ser.do_cmd(sprintf('%d\r', chan));
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dac) 13]);
        me.ser.do_cmd('e');
        if (~err && (length(m)==1))
          me.settings.atten_dac = m;
        end
      elseif (nc.util.ver_is_gte(me.devinfo.fwver, [6 2]))
        if (chan~=1)
          error(sprintf(' cal_set_voa_attn_dac(): chan=%d does not exist in this fw', chan));
        end
        me.ser.do_cmd('v');
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dac) 13]);
        if (chan>1)
          me.ser.do_cmd('e');
        end
        if (~err && (length(m)==1))
          me.settings.atten_dac = m;
        end
      else % old versions
        if (chan~=1)
          error(sprintf('cal_set_voa_attn_dac(): chan=%d does not exist in this fw ver', chan));
        end
        me.ser.do_cmd('w'); % ask to change DAC setting
        % Note: eps 6.0.1 has "2" cmd "set optical pwr",
        %       but eps 4.0 has "2" cmd to "adjust pulse"
        % GHz systems use register 11 (b)
        % and MHz systems use register 8
        if (me.devinfo.rate=='g')
          regsel='b';
        else
          regsel='8';
        end
        me.ser.do_cmd(regsel);
        me.ser.do_cmd([num2str(atten_dac) 13]);
        me.settings.atten_dac = atten_dac;
      end
    end
    
    function set_waveplates_deg(me, pc, wp, rets_deg)
    % desc:
    %   sets angles of one or more waveplates
    % inputs:  
    %   chan: 1..2 : specifies channel   (base one)
    %   wp: 1..6 : specifies starting waveplate   (base one)
    %   rets_deg: 0..? : vector of retardances (in deg) to set the waveplate to
    %                 range is limited in a device-calibration-specific manner.
    % changes:
    %    me.settings.waveplates_deg(chan,wp)
      if (pc~=1)
	error(sprintf('this device can only set retardance of PC %d in dac units', pc));
      end
      if (me.goto_cal_menu())
	return;
      end
      for k=1:length(rets_deg)
        if ((wp<1)||(wp>me.devinfo.num_wp(pc)))
          error(sprintf('eps1000_class.set_waveplates_deg: pc %d waveplate %d nonexistant', pc, wp));
	end
	ret_deg = rets_deg(k);
        rsp = me.ser.do_cmd('g'); % set efpc waveplate (deg units)
	me.ser.do_cmd([num2str(pc) 13]);
	me.ser.do_cmd([num2str(wp-1) 13]);
	[m err]=me.ser.do_cmd_get_matrix([num2str(ret_deg) 13]);
        if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3]))
          if (~err && (length(m)==1))
	    me.settings.waveplates_deg(pc,wp)=m;
          end
        else
  	  me.settings.waveplates_deg(pc,wp)=ret_deg;
        end
	wp=wp+1;
      end
      me.ser.do_cmd('e');      
    end
      
    function cal_set_waveplate_dac(me, pc, wp, val, pwd)
     %inputs: wp:1..6
    % introduced for eps fwv 7.2
      if (nargin<5)
        pwd = me.settings.password;
      end
      if ((wp<1)||(wp>me.devinfo.num_wp(pc)))
        error(sprintf('eps1000_class.cal_set_waveplates_dac: waveplate %d of pc %d nonexistant', wp, pc));
      end
      if (me.goto_cal_menu(pwd))
	return;
      end
      rsp = me.ser.do_cmd('f'); % set efpc waveplate (dac units)
      me.ser.do_cmd([num2str(pc) 13]);
      me.ser.do_cmd([num2str(wp-1) 13]);
      me.ser.do_cmd([num2str(val) 13]);
      me.ser.do_cmd('e');
    end
    
    function [err err_str] = set_wavelen_nm(me, chan, wl_nm)
      % inputs:
      %   chan: 1=sig, 2=idler
      %   wl_nm: wavelength in nm
      % returns:
      %   err: 0=success, 1=failed
      %   err_str: further description of error
      if (~me.devinfo.can_set_wavelen)
        error('eps1000_class.set_wavelen_nm(): no TBF in this EPS');
      end
      err=0;	     
      [ochan ech wl_nm] = me.wavelen_nm2chan(wl_nm);
      err = ~ochan || (ech ~= chan);
      if (err)
        err_str='bad wavelength';
        return;
      end

      me.ser.do_cmd('t');
      me.ser.do_cmd(char(chan+'0'));
      me.ser.do_cmd('1'); % 1=by chan num

      cmd = [num2str(ochan) char(13)];

      me.ser.set_timo_ms(10000);
      rsp = me.ser.do_cmd(cmd);
      me.ser.set_timo_ms(500);

      eidx = strfind(rsp, 'ERR');
      if (eidx)
	 sidx=strfind(rsp(eidx:end),'\n');
	 if (isempty(sidx))
	   err_str=rsp(eidx:end);
         else
	   err_str=rsp(eidx+(0:(sidx(1)-2)));
         end
	 err=1;
	 return;
      end
      if (~strfind(rsp, 'Success'))
	 err_str = 'no positive confirmation of success';
	 err=1;
	 return;
      end
      me.settings.wavelens_ochan(chan)=ochan
      me.settings.wavelen_nm(chan)=wl_nm;
    end


    function temp_C = laser_temp_set_dac2C(me, dac)
    % desc: convert laser temperature setpoint in DAC units to C
    %       NOTE: before calling this, call get_version_info to learn thermistor beta.
      r_Ohms = (dac * 4.0960 / 2^12) / 100e-6;
      % A7PA circuit pushes 100uA through thermistor.
      temp_C = me.therm_Ohms2C(me.devinfo.laser_therm_beta_K, r_Ohms);
    end

    function temp_C = laser_temp_mV2C(me, temp_mV)
    % desc: convert laser temperature setpoint or indication from mV to C
    %       NOTE: before calling this, call get_version_info to learn thermistor beta.
      % A7PA circuit pushes 100uA through thermistor.
      temp_C = me.therm_Ohms2C(me.devinfo.laser_therm_beta_K, temp_mV/1000/100e-6);
    end
    
    function dac = laser_temp_set_C2dac(me, temp_C)
    % desc: convert laser temperature setpoint in C to DAC units   
    %       NOTE: before calling this, call get_version_info to learn thermistor beta.
      r_Ohms = me.therm_C2Ohms(me.devinfo.laser_therm_beta_K, temp_C);
      % A7PA circuit pushes 100uA through thermistor.
      dac = (r_Ohms * 100e-6) * 2^12 / 4.0960;
    end
    
  end
end
