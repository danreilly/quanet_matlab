% agilent tunable laser
classdef agilent81689a_class < handle

  properties
    ser
    settings
  end

  methods (Static=true)
     % matlab "static" methods do not require an instance of the class

    function rsp = inq(port)
      import nc.*
      rsp='';
      opt.dbg=0;
      opt.baud=9600;
      ser = ser_class(port, opt);
      ser.cmd_term_char = char(10);
      ser.cmd_strip_echo = 0;
      ser.set_cmd_params(1000, 1000);
      if (ser.isopen())
        ser.write(['++addr 4' char(10)]);
        rsp = ser.do_cmd(['++addr' char(10)]);
	if (isempty(rsp) || (rsp(1)~='4'))
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
    function me = agilent81689a_class(port)
    % desc: constructor
      import nc.*

      opt.dbg=0;
      opt.baud=9600;
      me.ser = nc.ser_class(port, opt);

      if (me.ser.isopen())
        me.ser.cmd_term_char = char(10);
        me.ser.cmd_strip_echo = 0;
        me.ser.set_timo_ms(4000);
        me.ser.write(['++addr 4' char(10)]);
      end
      me.settings.wl_nm = 0;
      me.settings.wl_lims_nm =[1524 1576];
    end
    
    % DESTRUCTOR
    function delete(me)
      if (me.isopen())
        me.close();
      end
      delete(me.ser);
    end

    function close(me)
      me.ser.close();
    end
    
    function b = isopen(me)
      b = me.ser.isopen();
    end
    
    function get_settings(me)
% NOT FINISHED
      cmd = sprintf(':sour:chan:wav?%c', char(10));
      rsp = me.ser.do_cmd(cmd);
      rsp
    end

    function set_wavelen_nm(me, wl_nm)
      cmd = sprintf(':sour:chan:wav %.3fnm%c', wl_nm, char(10));
      me.ser.write(cmd);
      pause(0.2); % if you skip this, does not work for some reason!
      me.ser.set_timo_ms(10000);
      cmd = sprintf(':sour:chan:wav?%c', char(10));
      rsp = me.ser.do_cmd(cmd);
      
      [wl_echo ct]=sscanf(rsp,'%g',1);
      if (ct)
        wl_echo=wl_echo*1e9;
        me.settings.wl_nm = wl_echo;
        if (round(wl_echo*1000) ~= round(wl_nm*1000))
          fprintf('WARN: agilent81689a_class.set_wavelen_nm(): laser is at %.5f nm, not %.5f nm\n', wl_echo, wl_nm);
        end
      else
        fprintf('WARN: agilent81689a_class.set_wavelen_nm(): no rsp from laser\n');
      end
    end

  end
end
