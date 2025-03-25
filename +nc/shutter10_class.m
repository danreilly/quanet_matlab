classdef shutter10_class < nc.cpds_class

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
    ini_vars
    settings
  end

  methods

    % CONSTRUCTOR
    function me = shutter10_class(port, opt)
      % desc: constructor
      % inputs: port: windows port name that cpds is attached to. a string.
      %         opt: optional structure. optional fields are:
      %           opt.dbg: 0=normal, 1=print all low level IO
      %           opt.baud: baud rate to use
      %           opt.cpds2000_exe: full pathname to cpds2000.exe utility. a string.
      %                    used to invoke the utility to run *.c2k scripts,
      %                    and to read the cpds2000.ini and calibration file.
      import nc.*
      me.port = port;
      if (nargin<2)
        opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'baud', 115200);

      me.ser=[];
      me.open(port, opt.baud);
      if (~me.ser.isopen())
        return;
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

    function bool = isopen(me)
      bool = me.ser.isopen();
    end

    function bool = set_shutter(me val)
      me.ser.do_cmd(sprintf('shut %d\r', val));
    end

  end

end

