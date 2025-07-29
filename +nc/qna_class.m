
classdef qna_class < nc.ncdev_class
    % NuCrypt qna device
    % s750 board in quanet qnic
  
  properties (Constant=true)
    c_mps = 299792458;
  end
  
  properties
    
    ser
    % ser_class used to access pulser
    idn
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
      devinfo = idn;
    end
  end

  methods

    % CONSTRUCTOR
    function me = qna_class(arg1, opt)
    % desc: qna_class constructor. Opens device, reads all settings.
    % usages:
    %   obj = qna_class(opt)
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
      me.ser.cmd_nchar = 100000;
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

    function get_version_info(me)
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

    function set_beat_fbdk_tc_us(me, tc_us)
      rsp = me.ser.do_cmd_get_matrix(sprintf('beat tc %d\r', tc_us));
      if (~isempty(rsp))
        me.settings.beat_tc_us = rsp;
      end
    end
    
    function set_beat_goal(me, kHz)
    % kHz: 0= turn off feedback and reset FM to midpoint.
      rsp = me.ser.do_cmd_get_matrix(sprintf('beat goal %d\r', kHz));
      if (~isempty(rsp))
        me.settings.beak_goal_kHz = rsp;
      end
      if (kHz==0)
        rsp = me.ser.do_cmd(sprintf('cfg it fm 2047\r'));
      end
    end
    
    function status = get_status(me)
      rsp = me.ser.do_cmd(['stat' char(13)]);
      status.beat_kHz = me.ser.parse_keyword_val(rsp, 'beat_freq_kHz', 0);
    end
  
    function get_settings(me)
      rsp = me.ser.do_cmd(['set' char(13)]);
      me.settings.wavelen_nm = me.ser.parse_keyword_val(rsp, 'wavelen', 0);
      rsp = me.ser.do_cmd(['beat set' char(13)]);
      me.settings.beat_en = me.ser.parse_keyword_val(rsp, 'en', 0);
      me.settings.beat_dur_us = me.ser.parse_keyword_val(rsp, 'dur', 0);
      me.settings.beat_tc_us = me.ser.parse_keyword_val(rsp, 'tc', 0);
      me.settings.beat_goal_kHz = me.ser.parse_keyword_val(rsp, 'goal', 0);
    end

    
    function [hdr, data] = cap(me, len, type, step, dsamp)
    % usage:
    %   qna.cap(len) - captures <len> samples.  No step.
    %   qna.cap(len,type,step) - captures <len> samples and applies
    %     a "step" of the specified type after the tenth sample.
    %       type: f=fm step, g=goal step
    %       step: in dac units for fm step, in kHz for goal step.
      if (nargin<3)
        type='g';
        amt=0;
      end
      me.ser.set_timo_ms(10000);
      
      rsp = me.ser.do_cmd(sprintf('cap step %c %d\r', type, step));
      
      rsp = me.ser.do_cmd(['cap set' char(13)]);
      hdr = me.ser.parse_keyword_val(rsp, 'hdr', '');
      [data err] = me.ser.do_cmd_get_matrix(sprintf('cap go %d %d\r', len, dsamp));
      if (err)
        fprintf('ERR: qna_class.cap(): bad rsp: err %d, size %d x %d\n', ...
                  err, size(data));
      end
      if (size(data,1)~=len)
          fprintf('ERR: qna_class.cap(): requested %d, got %d\n', ...
                  len, size(data,1));
      end
    end
    
  end
end
