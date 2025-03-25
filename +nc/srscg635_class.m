% SRS frequency generator
classdef srscg635_class < handle

  properties (Constant=true)
    JUNK = 0;
  end


  properties
    ser
    devinfo
    settings
    st
  end


  methods (Static=true)
     % matlab "static" methods do not require an instance of the class
    function devinfo = get_devinfo(ser) % STATIC
      import nc.*
      
      devinfo.irsp = '';
      devinfo.mfg = '?';
      devinfo.model = '?';
      devinfo.sn = '?';

      ser.write(['++addr 23' char(10)]);
      rsp = ser.do_cmd(['++addr' char(10)]);

      if (isempty(rsp) || (~strncmp(rsp,'23',2)))
        fprintf('WARN: Bad response from Prologix dongle\n');
        devinfo.irsp = rsp;
        return;
      end
      
      irsp = ser.do_cmd(['*IDN?' char(10)]);
      devinfo.irsp = irsp;
      irsp_ca = regexp(irsp,'[^,]+','match');
      irsp_l = length(irsp_ca);
      if (irsp_l<2)
        fprintf('WARN: Got response from Prologix dongle, but not DCA\n');
      end

      if (irsp_l>=1)
        devinfo.mfg = irsp_ca{1};
      end
      if (irsp_l>=2)
        devinfo.model = irsp_ca{2};
      end
      if (irsp_l>=3)
        devinfo.sn = irsp_ca{3};
      end
    end
    
    function rsp = inq(port)
      import nc.*
      rsp='';
      opt.st.dbg=0;
      opt.baud=9600;
      ser = ser_class(port, opt);
      ser.cmd_term_char = char(10);
      ser.cmd_strip_echo = 0;
      ser.set_cmd_params(1000, 1000);
      if (ser.isopen())
        ser.write(['++addr 23' char(10)]);
        rsp = ser.do_cmd(['++addr' char(10)]);
	if (isempty(rsp) || ~strncmp(rsp,'23',2))
          fprintf('WARN: Bad response from Prologix dongle\n');
	else
          rsp = ser.do_cmd(['*IDN?' char(10)]);
          if (isempty(rsp))
	    fprintf('trying again\n');
            rsp = ser.do_cmd(['*IDN?' char(10)]);
          end
        end
      end
    end

  end

  methods

    % CONSTRUCTOR
    function me = srscg635_class(arg1, opt)
    % desc: constructor
      % use:
      %   obj = srscg635_class(ser, opt)
      %           ser: an open ser_class object
      %   obj = srscg635_class(port, opt)
      % inputs: port: windows port name that cpds is attached to. a string.
      %         opt: optional structure. optional fields are:
      import nc.*

      me.ser = [];
      me.settings.hscale=1;
      me.settings.chan=1;
      if (nargin<2)
        opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'throw_errors', 1);
      opt = util.set_field_if_undef(opt, 'print_warnings', 1);
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      me.st.dbg=opt.dbg;
      me.st.throw_errors = opt.throw_errors;
      me.st.print_warnings = opt.print_warnings;
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.ser.cmd_rsp_col_sep=',';
        me.open();
      elseif (ischar(arg1))
        me.open(arg1);
      else
        error('first param must be portname or ser_class');
      end
    end
      

    
    % DESTRUCTOR
    function delete(me)
      if (me.isopen())
        me.close();
      end
      delete(me.ser);
    end



    function open(me, portname)
      if (isempty(me.ser))
        opt.dbg=me.st.dbg;
        opt.baud=9600;
        me.ser = nc.ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open();
      end
      if (me.ser.isopen())
        me.ser.cmd_rsp_col_sep=',';
        me.ser.set_timo_ms(1000);
        me.ser.cmd_term_char = char(10);
        me.ser.cmd_strip_echo = 0;
        % serial port params such as baud rate, data bits, stop bits
        % and flow control should not affect the ++ commands with Prologix.
        me.ser.write(['++addr 23' char(10)]);
        rsp = me.ser.do_cmd(['++addr' char(10)]);
	if (me.st.throw_errors && (isempty(rsp) || ~strncmp(rsp,'23',2)))
          error('srscg635_class.open(): Bad response from Prologix dongle\n');
	end

        me.devinfo = me.get_devinfo(me.ser);

        if (me.st.throw_errors)
          if (isempty(strfind(lower(me.devinfo.mfg),'stanford')))
            error('srscg635_class.open(): not a Standford Reasarch System');
          end
          if (isempty(strfind(lower(me.devinfo.model),'cg635')))
            error('srscg635_class.open(): not an cg635');
          end
        end

        
        me.ser.write([':MEAS:SEND 1' char(10)]);
        % current val returned for quest results.  a comma.  then an errcode.

        me.get_settings();
        
      elseif (me.st.throw_errors)
        error('agilent86100_class.open(): failed to open');
      end
    end
    
    function set_print_warnings(me, en)
      me.st.print_warnings=en;
    end
    
    function close(me)
      me.ser.close();
    end
    
    function b = isopen(me)
      b = me.ser.isopen();
    end
    
    function get_settings(me)
      m = me.ser.do_cmd_get_matrix(sprintf('FREQ?\n'));
      me.settings.freq_Hz = m;

      m = me.ser.do_cmd_get_matrix(sprintf('RUNS?\n'));
      me.settings.run = m;
    end
    
    function set_run(me, en)
      m = me.ser.do_cmd_get_matrix(sprintf('RUNS %d\n', en));
      me.settings.run = m;
    end
    
    function set_freq_Hz(me, Hz)
      me.ser.write(sprintf('FREQ %g\n', Hz));
      m = me.ser.do_cmd_get_matrix(sprintf('FREQ?\n'));
      me.settings.freq_Hz = m;
    end

  end
end
