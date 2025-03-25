% epspump_class
%
% used if the epspump is a separate EDFA of
% a specific brand that stands alone on a separate
% usb virtual port, and the eps cannot control the pump power directly
%
classdef epspump_class < handle 

  properties
    dbg  % 0=none, 1=debug io
    port
    ser
    idn
    devinfo % structure of info about device
    settings % structure containing current settings
  end

  methods (Static=true)
  end

  methods

    % CONSTRUCTOR
    function me = epspump_class(arg1, opt)
    % desc: constructor
      % use:
      %   obj = epspump_class(ser, opt)
      %           ser: a ser_class object
      %   obj = epspump_class(port, opt)
      import nc.*
      me.ser = [];
      me.idn = [];
      me.devinfo = [];
      if (nargin<1)
	port='';
      end
      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'baud', 115200);

      me.dbg = opt.dbg;
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.idn = me.ser.idn;
        me.devinfo = me.idn;
        me.devinfo.num_chan=1;
      elseif (ischar(arg1))
        me.ser = nc.ser_class(arg1, opt.baud, opt);
        me.open();
      else
        error('first param must be portname or ser_class');
      end

%      me.ser.set_cmd_params(me.ser.cmd_nchar*4, me.ser.cmd_timo_ms);
      if (me.isopen())

        me.ser.do_cmd(['mode acc' 13]); % const current mode is best
        % NOTE: expect the "mode acc" cmd to respond with FAILURE
        %       if it's already in constant current mode.
        %       But it really did't fail.
        % fprintf('DBG: rsp to mode acc:\n'); nc.uio.print_all(rsp);

        rsp = me.ser.do_cmd(['fline' 13]);
        if (isempty(strfind(rsp, 'ACC')) || isempty(strfind(rsp, 'LDON')))
          fprintf('ERR: EDFA might not be in ON and in ACC mode');
          nc.uio.print_all(rsp);
        end

      end
    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function set_io_dbg(en)
      me.ser.set_dbg(en);
    end
    
    function open(me, portname, opt)
    % inputs:
    %   port: optional string.  If omitted, uses port previously used
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
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      end
      if (me.ser.isopen())
        me.idn = me.ser.get_idn_rsp; % identity structure
        me.devinfo = me.idn; % me.parse_idn(me.idn);
        me.devinfo.num_chan=1;
%        me.set_nomenu(1);
      end
      me.settings.pwr=0; % TODO: fix?
    end

    function close(me)
      me.ser.close;
    end

    function f=isopen(me)
      f=me.ser.isopen();
    end

    function set_pwr(me, p)
       % this edfa response with F or S.
      [rsp err] = me.ser.do_cmd(sprintf('ldc ba %d\r', p), '', 'S');
      if (~err)
        me.settings.pwr = p;
      end
    end

  end

end



