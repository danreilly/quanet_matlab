
classdef pg300_class < nc.ncdev_class
% NuCrypt pg300 device
  
  properties (Constant=true)
    c_mps = 299792458;
  end
  
  properties
    
    ser
    % ser_class used to access pulser
    
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
    % always sets:
    %      devinfo.num_chan: 1 or 2
      if (~isstruct(idn))
        error('idn must be a structure');
      end
      
      % import nc.*
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      model=0;
      if (num_flds>=2)
        model = parse_word(flds{2}, '%d', model);
      end
      
      % default PG
%      devinfo.sn = '?';
      devinfo = idn;
      devinfo.num_chan = 1;

      for_fwver = [1 1 1];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: pg3000_class(): This software was written for pulser firmwares %s and below\n', nc.util.ver_vect2str(for_fwver));
        fprintf('      but PG has firmware %s and might not work with this +nc package\n', ...
                nc.util.ver_vect2str(devinfo.fwver));
      end
      
      % C1
      k=3;
      if(k>num_flds)
	return;
      end
      devinfo.num_chan = parse_word(flds{k}, '%d', devinfo.num_chan);
      k = k + 1;
      if(k>num_flds)
        return;
      end

      % C2
      k = k + 1;
      if(k>num_flds)
        return;
      end

      % C3
      k = k + 1;

      % C4
      k = k + 1; % (C4 not used)

      % nested
      function v=parse_word(str, fmt, default)
	[v ct]=sscanf(str, fmt, 1);
	if (~ct)
          v = default;
	end
      end
      
    end
    
  end


  
  methods

    % CONSTRUCTOR
    function me = pg300_class(arg1, opt)
    % desc: pg300_class constructor. Opens device, reads all settings.
    % usages:
    %   obj = pg300_class(opt)
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

    function ver = get_version_info(me)
      rsp = me.ser.do_cmd(['ver' char(13)]);
      % set up for OFC
      me.devinfo.can_set_pulse_delay = me.ser.parse_keyword_val(rsp,'can_set_dly',0);
      me.devinfo.can_set_pulse_width = me.ser.parse_keyword_val(rsp,'can_set_width',0);
      me.devinfo.can_set_voa = me.ser.parse_keyword_val(rsp,'can_set_voa',0);
      me.devinfo.can_set_wavelen = me.ser.parse_keyword_val(rsp,'can_set_wavelen',0);
      %      me.devinfo.has_freqgen = me.ser.parse_keyword_val(rsp,'has_freqgen', 0);
      me.devinfo.num_dlyrs_per_chan = me.ser.parse_keyword_val(rsp,'num_dlyrs_per_chan', 2);
    end
    
    function get_settings(me)
      rsp = me.ser.do_cmd(['set' char(13)]);
      for ch=1:me.devinfo.num_chan
        me.settings.delay_ps(ch)     = me.ser.parse_keyword_val(rsp,sprintf('dly %d', ch),0);
        me.settings.width_ps(ch) = me.ser.parse_keyword_val(rsp,sprintf('width %d', ch),0);
        me.settings.voa_dB(ch)   = me.ser.parse_keyword_val(rsp,sprintf('voa %d', ch),0);
        me.settings.wavelen_nm(ch) = me.ser.parse_keyword_val(rsp,sprintf('wavelen %d', ch),0);
        me.settings.ofreq_MHz(ch)  = me.ser.parse_keyword_val(rsp,sprintf('ofreq %d', ch),0);
        me.settings.ref_MHz  = me.ser.parse_keyword_val(rsp, 'ref', 0);
        me.settings.freq_MHz       = me.ser.parse_keyword_val(rsp, '\sfreq', 0);
      end
    end
    
    function status = get_status(me)
      import nc.*
      rsp = me.ser.do_cmd(sprintf('stat\r'));
      status.oam_bias_fb_lock = me.ser.parse_keyword_val(rsp, 'oam_bias_fb_lock', 0);
      status.oam_lock_dur_s = me.ser.parse_keyword_val(rsp, 'oam_lock_dur_s', 0);
      status.pll_lock = me.ser.parse_keyword_val(rsp, 'pll_lock', 0);
    end
    
    function set_voa_dB(me, ch, attn_dB)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('voa %d %g\r', ch, attn_dB));
      if (~err && (length(m)==1))
        me.settings.voa_dB(ch)=m;
      end
    end
    
    function set_wavelen_nm(me, ch, wl_nm)
      me.ser.set_timo_ms(10000);
      [m err] = me.ser.do_cmd_get_matrix(sprintf('wavelen %d %g\r', ch, wl_nm));
      me.ser.set_timo_ms(1000);
      if (~err && (length(m)==1))
        me.settings.wavelen_nm(ch)=m;
        me.settings.ofreq_MHz(ch)= me.c_mps * 1000 / m;
      end
    end
    
    function set_pll_ref_MHz(me, f_MHz)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('ref %d\r', f_MHz));
      if (~err && (length(m)==1))
        me.settings.ref_MHz=m;
      end
    end
    
    function set_pulse_freq_MHz(me, freq_MHz)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('freq %g\r', freq_MHz));
      if (~err && (length(m)==1))
        me.settings.freq_MHz=m;
      end
    end
    
      
    function set_optical_freq_MHz(me, ch, f_MHz)
      me.ser.set_timo_ms(60000);
      [m err] = me.ser.do_cmd_get_matrix(sprintf('ofreq %d %d\r', ch, f_MHz));
      me.ser.set_timo_ms(1000);
      if (~err && (length(m)==1))
        me.settings.ofreq_MHz(ch)=m;
        me.settings.wavelen_nm(ch)=me.c_mps * 1000 / m;
      else
        fprintf('WARN: pg300_class.set_optical_freq: FAILED\n');
      end
    end
    
    
    function set_pulse_width_ps(me, ch, wid_ps)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('width %d %g\r', ch, wid_ps));
      if (~err && (length(m)==1))
        me.settings.width_ps(ch)=m;
      end
    end
    
    function set_pulse_delay_ps(me, ch, delay_ps)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('dly %d %g\r', ch, delay_ps));
      if (~err && (length(m)==1))
        me.settings.delay_ps(ch)=m;
      end
    end
    
  end
end

    
