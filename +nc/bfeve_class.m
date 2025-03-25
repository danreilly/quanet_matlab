% bfeve_class.m
% NuCrypt Proprietary
% Matlab API for eve as part of the beamfind project
% version 1.0

classdef bfeve_class < handle

  properties (Constant=true)
    pitch_m_per_rev = 0.008; % 8mm per rev
    steps_per_rev = 800;
  end

  properties
    dbg  % 0=none, 1=debug
    port
    ser
    idn
    devinfo
    settings
%      settings.pos
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function m = pos_steps2m(steps)
      m = steps/nc.bfeve_class.steps_per_rev*nc.bfeve_class.pitch_m_per_rev;
    end

    function steps = pos_m2steps(m)
      steps = round(m*nc.bfeve_class.steps_per_rev/nc.bfeve_class.pitch_m_per_rev);
    end

  end


  methods

    % CONSTRUCTOR
    function me = bfeve_class(port, opt)
    % desc: constructor
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
      me.dbg = opt.dbg;
      me.port = port;
      me.ser = nc.ser_class('', 115200, opt);
      me.open();
    end % constructor

    % DESTRUCTOR
    function me = delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function close(me)
      me.ser.close;
    end

    function f=isopen(me)
      f=me.ser.isopen;
    end

    function open(me, port)
    % inputs:
    %   port: optional string.  If omitted, uses port previously used
      import nc.*
      if (nargin>1)
        me.port = port;
      end
      opt.dbg = me.dbg;
      me.ser.open(me.port, 115200, opt);
      if (me.ser.isopen)
        me.idn = me.ser.get_idn_rsp; % identity structure
      end
    end

    function get_settings(me)
      [rsp errp] = me.ser.do_cmd(sprintf('set\r'));
      me.settings.pos = me.ser.parse_keyword_val(rsp, 'pos', 1);
      me.settings.disable = me.ser.parse_keyword_val(rsp, 'disable', 1);
      [rsp errp] = me.ser.do_cmd(sprintf('cfg set\r'));
      pul_us = me.ser.parse_keyword_val(rsp, 'pul', 1);
      me.settings.speed_pps = 1e6/pul_us;
    end

    function status = get_status(me)
    % status: structure containg the fields:
    %   pos: 2x1 vector [h v] in units of stepper motor controller steps
    %   moving: 2x1 vector [hm vm] where 0=still, 1=moving
      [rsp errp] = me.ser.do_cmd(sprintf('status\r'));
      status.pos    = me.ser.parse_keyword_val(rsp, 'pos', 1);
      status.moving = me.ser.parse_keyword_val(rsp, 'moving', 1);
    end

    function home(me)
    % moves linear stages to the home position and zeros them
      me.ser.do_cmd(sprintf('home\r'));
      me.settings.pos = [0 0];
    end

    function disable(me, dis)
    % disables motor drivers so you can turn the shaft by hand
      me.ser.do_cmd(sprintf('disable %d\r', dis));
      me.settings.disable = dis;
    end


    function b=is_moving(me)
      status=me.get_status();
      b = any(status.moving);
    end

    function wait_until_still(me)
      while(me.is_moving())
	pause(0.1);
      end
    end

    function set_pos(me, h, v)
    % h and v in units of steps
      if (nargin==2)
        me.ser.do_cmd(sprintf('pos %d\r', h));
	me.settings.pos(1) = h;
      else
        me.ser.do_cmd(sprintf('pos %d %d\r', h, v));
	me.settings.pos = [h v];
      end
    end

    function set_speed_pps(me, pulses_per_sec)
    % pulses_per_sec in units of pulses per second
      pulse_dur_us = round(1e6/pulses_per_sec);
      [m err]= me.ser.do_cmd_get_matrix(sprintf('cfg pul %d\r', pulse_dur_us));
      if (~err)
        me.settings.speed_pps = 1/(m(1,1)*1e-6);
      end
    end


  end
end
