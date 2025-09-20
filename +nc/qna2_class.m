
classdef qna2_class < nc.ncdev_class
% For NuCrypt qna2 device
% Which is the Quanet Nic Aux device

  
  properties (Constant=true)
    c_mps = 299792458;
  end
  
  properties
    
    ser
    % ser_class used to access QNA
    
    devinfo
    % Customization and capability information about this QNA
    %   devinfo.num_voa             1,2, etc

    
    settings
    % Current settings of this pulser.
    % Note: This is a read-only structure.
    %   settings.

    cal
    
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
      devinfo.num_voa = 0;
      devinfo.num_efpc = 0;
      devinfo.supports_flash_write=1;


      for_fwver = [2 0 1];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: qna20_class(): This software was written for pulser firmwares %s and below\n', nc.util.ver_vect2str(for_fwver));
        fprintf('      but PG has firmware %s and might not work with this +nc package\n', ...
                nc.util.ver_vect2str(devinfo.fwver));
      end
      
      % C1
      k=3;
      if(k>num_flds)
	return;
      end
      % devinfo.num_chan = parse_word(flds{k}, '%d', devinfo.num_chan);
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
    function me = qna2_class(arg1, opt)
    % desc: qna2_class constructor. Opens device, reads all settings.
    % usages:
    %   obj = qna2_class(opt)
    %           opt: a structure
    %             opt.dbg: 1=debug all io, 0 =dont
    %   obj = qna2_class(ser)
    %   obj = qna2_class(ser, opt)
    %           ser: a ser_class object that is open, stays open
    %   obj = qna2_class(port)
    %   obj = qna2_class(port, opt)
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
    % desc: opens qna2 device, does 'i' command, fills in me.devinfo.
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
	  fprintf('WARN: qna2_class.open failed\n');
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
      me.devinfo.num_voa  = me.ser.parse_keyword_val(rsp,'num_voa', 0);
      me.devinfo.num_fpc = me.ser.parse_keyword_val(rsp,'num_efpc', 0);
      n=me.ser.parse_keyword_val(rsp,'num_wp', 0);
      % num wp stored per PC even though all same for now.
      me.devinfo.num_wp = repmat(n,1,me.devinfo.num_fpc);
    end
    
    function get_settings(me)
      rsp = me.ser.do_cmd(['set' char(13)]);
      for ch=1:me.devinfo.num_voa
        me.settings.voa_dB(ch)     = me.ser.parse_keyword_val(rsp,sprintf('voa %d', ch), 0);
      end
      for ch=1:3
        me.settings.opsw(ch)     = me.ser.parse_keyword_val(rsp,sprintf('opsw %d', ch), 0);
      end
      me.settings.rxefpc = me.ser.parse_keyword_val(rsp, 'rxefpc', 0);      
      me.settings.wavelen_nm = me.ser.parse_keyword_val(rsp, 'wavelen', 0);

      rsp = me.ser.do_cmd(['cfg set' char(13)]);
      for k=1:me.devinfo.num_voa
        key = sprintf('voa%d_calfile', k);
        me.settings.voa_calfiles{k} = me.ser.parse_keyword_val(rsp, key, '');
      end
      for pc=1:me.devinfo.num_efpc
        key=sprintf('efpc %d', pc);
        me.settings.efpc_ret_deg = me.ser.parse_keword_val(rsp, key, [0 0 0]);
      end
      
    end
    
    function status = get_status(me)
      import nc.*
      rsp = me.ser.do_cmd(sprintf('stat\r'));
      status.oam_bias_fb_lock = me.ser.parse_keyword_val(rsp, 'oam_bias_fb_lock', 0);
      status.oam_lock_dur_s   = me.ser.parse_keyword_val(rsp, 'oam_lock_dur_s', 0);

    end
    
    function set_voa_attn_dB(me, ch, attn_dB)
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
    
    
    function [err msg]=get_cal(me)
      err=0;
      cal.dbg=1;
      cal.calfile='';
      me.cal=cal;
      msg='';
    end
    
    function cal = read_calfile(me, fname)
      cal = nc.pa1000_class.read_calfile(fname);
    end
      
    function set_optical_freq_MHz(me, ch, f_MHz)
      me.ser.set_timo_ms(60000);
      [m err] = me.ser.do_cmd_get_matrix(sprintf('ofreq %d %d\r', ch, f_MHz));
      me.ser.set_timo_ms(1000);
      if (~err && (length(m)==1))
        me.settings.ofreq_MHz(ch)=m;
        me.settings.wavelen_nm(ch)=me.c_mps * 1000 / m;
      else
        fprintf('WARN: qna2_class.set_optical_freq: FAILED\n');
      end
    end
    
  end
end

    
