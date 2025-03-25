classdef qswitch1000_class < handle
  properties (Constant=true)

  end

  % instance members
  properties
    dbg     
    ser      % obj of type serclass
    idn      % NuCrypt identity structure
%     .name
%     .model
%     .sn
%     .pwr_rating (30=one watt, 20=20dBm , 18=18dBm, 0=unknown) based on model name
    devinfo  % 
    settings % current settings
%      .pump_cur_ma(1:3)
%      .pump_limit_ma(1:3)
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function devinfo = parse_idn(idn)
      import nc.*
      devinfo = idn;
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);

      % default QSWITCH
      devinfo.num_chan = 3;

      % C1
      k=3;
      if (k>num_flds) return;  end
      devinfo.num_chan    = parse_word(flds{k}, '%d', 2);
      k = k + 1;
      if (k>num_flds)
	return;
      end

      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
          v = default;
        end
      end

    end


  end
  methods % instance methods

    % CONSTRUCTOR
    function me = qswitch1000_class(port, opt)
    % desc: constructor
      if (nargin<2)
	opt.dbg=0;
      end
      me.dbg=opt.dbg;
      opt=nc.util.set_field_if_undef(opt,'baud',115200);
      me.ser=[];
      % me.ser = nc.ser_class(port, opt.baud, opt);
      me.open(port, opt.baud, opt);
    end

    % DESTRUCTOR
    function delete(me)
      me.close;
    end

    function bool = isopen(me)
      bool = me.ser.isopen();
    end

    function close(me)
      if (me.ser.isopen())
	me.ser.close;
      end
    end

    function open(me, portname, baud, opt)
      import nc.*
      if (isempty(me.ser))
        if (nargin<4)  opt.dbg=0; end
        if (nargin<3)  baud=115200;  end
        if (nargin<2)  portname='';   end
        me.ser = ser_class(portname, baud, opt);
      else
        if (me.ser.isopen())
          fprintf('WARN: qswitch1000_class.open(): already open\n');
	  return;
        end
	if (nargin <2) portname=me.ser.portname; end
	if (nargin <3) baud=me.ser.baud; end
	if (nargin <4)
          me.ser.open(portname, baud);
        else
          me.ser.open(portname, baud, opt);
        end
      end
      if (~me.ser.isopen())
        return;
      end
      me.idn = me.ser.get_idn_rsp();
      me.devinfo = me.parse_idn(me.idn);
      me.get_settings();
    end

    function set_arb_en(me, en)
      rsp = me.ser.do_cmd(sprintf('arb %d\r', en));
      me.settings.arb_en=en;
    end

%    function set_locklight_voa(me, chan, val)
%      rsp = me.ser.do_cmd(sprintf('arb %d\r', en));
%      me.settings.arb_en=en;
%    end


    function get_settings(me)
      rsp = me.ser.do_cmd(sprintf('set\r'));
      me.settings.arb_en = me.ser.parse_keyword_val(rsp, 'arb', 0);
      me.settings.refin = me.ser.parse_keyword_val(rsp, 'refin', 0);
      me.settings.refclk_onboard = me.ser.parse_keyword_val(rsp, 'refclk_onboard', 0);
      me.settings.vco_MHz = me.ser.parse_keyword_val(rsp, 'vco_MHz', 0);
      me.settings.freq_MHz = me.ser.parse_keyword_val(rsp, 'freq', 0);
      me.settings.voadly_us = me.ser.parse_keyword_val(rsp, 'voadly_us', 0);
    end

    function status = get_status(me)
      rsp = me.ser.do_cmd(sprintf('stat\r'));
      status.mmcm_lock = me.ser.parse_keyword_val(rsp, 'mmcm_lock', 0);
      status.com_chan_alive = me.ser.parse_keyword_val(rsp, 'com_chan_alive', 0);
    end

    function str = inq_chan(me, ch)
    % ch: 1 to 3
      me.ser.do_cmd(sprintf('r %d t 300\r', ch-1)); % change to 200ms timeout

      cmd = sprintf('r %d ci\r', ch-1);
      % nc.uio.print_all(cmd);
      rsp = me.ser.do_cmd(cmd);

      me.ser.do_cmd(sprintf('r %d t 2000\r', ch-1)); % back to 2s timeout

      [sidxs eidxs] = regexp(rsp,'[^\n]+');
      str='';
      k=find(eidxs-sidxs>=16,1);
      if (~isempty(k))
	str = rsp(sidxs(k):eidxs(k));
      end
    end

    function bridged_get_idn(me, chan)
      cmd = sprintf('r %d ci\r', chan-1);
      me.ser.write(cmd);
    end

    function bridged_cmd_start(me, ser, chan, cmd)
      cmd = sprintf('r %d c%s\r', chan-1, cmd);
      ser.write(cmd);
    end

    function set_bridge_timo_ms(me, ser, chan, timo_ms)
      cmd = sprintf('r %d t %d\r', chan-1, timo_ms);
      ser.write(cmd);
      ser.get_cmd_rsp(cmd);
    end

    function rsp = bridged_rsp(me, chan, rsp)
      % could verify local echo, but for now just strip it
      idxs = strfind(rsp, char(10));
      if (~isempty(idxs))
	rsp=rsp((idxs(1)+1):end);
      end
    end

  end
end
