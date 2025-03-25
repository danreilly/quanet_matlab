% NuCrypt tsteff device
% This is our detector efficiency tester.  It has a voa.


classdef tsteff_class < handle

  properties (Constant=true)
    JUNK=0;
  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug
    idn_rsp
    port_str % name of windows com port.  a string.
    devinfo
    settings
    ser
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class
  end

  methods

    % CONSTRUCTOR
    function me = tsteff_class(port)
      import nc.*
    % desc: returns handle to tsteff in "open" state if possible
      me.idn_rsp = '';
      me.port_str = port;
      me.ser = ser_class(port, 115200);
      me.devinfo = me.ser.get_idn_rsp;
      me.settings.attn_dB = 0;
      pause(0.05);
      me.ser.flush();
    end

    % DESTRUCTOR
    function delete(me)
      me.ser.delete;
    end

    function close(me)
      me.ser.close;
    end

    function open(me)
      import nc.*
      me.ser = ser_class(me.port_str, 115200);
    end

    function b=isopen(me)
      b=me.ser.isopen();
    end
    
    function lims_dB = get_attn_lims_dB(me)
      % todo: really we should ask device
      lims_dB = [0 60];
    end

    function v = set_attn_dB(me, attn_dB)
      attn_dB = min(attn_dB, 60);
      [rsp err]= me.ser.do_cmd(sprintf('attn %g\r', attn_dB));
      me.settings.attn_dB = attn_dB;
    end
      
    function v = set_voa(me, v)
      [rsp err]= me.ser.do_cmd(sprintf('voa %d\r', v));
      v = me.ser.parse_matrix(rsp);
    end
    
  end    

end
