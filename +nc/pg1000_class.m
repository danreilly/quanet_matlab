% pg1000_class
%
% class ("static") functions
%   pg1000_class.parse_idn(idn)
%




% member variables ("properties")
%   pg.settings.
%         wavelen_nm: 1x2 vector of wavelengths in nm
%         pwr_dac: pump power in dac units
%         waveplates_deg: 1x4 vector of waveplate retardances in deg
%
% member functions
%   pg=pg1000_class(port) CONSTRUCTOR. calls open, then get_settings.
%   pg.close              you may close and then re-open
%   pg.open(port)         if port absent, uses prior port
%   b=pg.isopen           returns logical
%   pg.get_settings       call, then access pg.settings structure


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

classdef pg1000_class < nc.ncdev_class

  properties
    dbg  % 0=none, 1=debug io
    port
    ser
    devinfo % structure of info about device
%     devinfo.can_set_alignment - 1=can set H vs D alignment
%     devinfo.can_ctl_align_pwr - 1=has op swicth to turn on/off alignment pwr
%     devinfo.opt_pwr_ctl  -  from pwr ctl field in info string. p,n,b,d
%     devinfo.num_voa
    settings % structure containing current settings
%     settings.wavelen_nm(chan)    - current wavelenths in nm
%     settings.wavelens_ochan(chan) - current wavelenths as optical channel number
%     settings.atten_dac            - optical attenuation in dac units []=not featured
%     settings.atten_dB             - opt atten in dBs. []=not featured
%     settings.colinear             - []=not featured, 0=not colinear, 1=colinear
%     settings.alignment            - o=off, h=horiz, v=vert, ?=not featured
%     settings.nomenu               - 0=verbose 1=not printing menus
%     settings.password    
    cal
    cal_ok
  end


  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    % static
    function devinfo = parse_idn(idn)
      import nc.*
      if (~isstruct(idn))
        error('pg1000_class.parse_idn: idn must be a structure');
      end
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      
      % default PG
      devinfo = idn;
      devinfo.num_chan = 1; % one entangled pair

      % C1
      k=3;
      if(k>num_flds)
	return;
      end

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
      if(k>num_flds)
        return;
      end

      % C4
      k = k + 1;
      if(k>num_flds)
        return;
      end

    end

  end

  methods

    % CONSTRUCTOR
    function me = pg1000_class(arg1, opt)
    % desc: constructor
      % use:
      %   obj = pg1000_class(ser, opt)
      %           ser: a ser_class object
      %   obj = pg1000_class(port, opt)
      import nc.*
      me.ser = [];
      me.devinfo = [];
      if (nargin<1)
	port='';
      end
      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'baud', 115200);

      me.dbg = opt.dbg;

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

          me.get_settings();
	end
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

    function get_settings(me)
      rsp=me.ser.do_cmd(sprintf('dbg set\r'));
      me.settings.wavelen_nm = me.ser.parse_keyword_val(rsp, 'wl',0);
      me.settings.bias_dac = me.ser.parse_keyword_val(rsp, 'bias',0);
    end
    
    function dbg_set_bias_dac(me, bias_dac)
      me.ser.do_cmd(sprintf('dbg bias %d\r', bias_dac));
      me.settings.bias = bias_dac;
    end
    
    function wl_nm  = set_wavelen_nm(me, wl_nm)
      [m, err]=me.ser.do_cmd_get_matrix(sprintf('wl %d\r', wl_nm));
      if (~err && (length(m)==1))
        me.settings.wavelen_nm = m;
      end
    end
    
    function status = get_status(me)
      rsp=me.ser.do_cmd(['dbg stat' char(13)]);
      status.bias = me.ser.parse_keyword_val(rsp, 'bias',0);
      status.pwr = me.ser.parse_keyword_val(rsp, 'pwr',0);
    end
    
    function err=save_settings_in_flash(me)
      rsp=me.ser.do_cmd('s');
      err = me.ser.parse_keyword_val(rsp, 'flash err', 0);
    end
    
    function cal_set_password(me, pwd)
      me.settings.password=pwd;
    end


  end
end
