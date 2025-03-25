% agilent DCA sampling oscillioscope
% via prologix GPIB-USB dongle

classdef agilent86100_class < handle

  properties
    ser_obj
    devinfo
    settings
    dbg
  end

  methods (Static=true)
     % matlab "static" methods do not require an instance of the class

    function rsp = inq(port)
      rsp='';
      ser_obj = serial(port);
      set(ser_obj,'Timeout',1) % 0.2);
% get(ser_obj,'Terminator') is LF
      ok=0;
      try
%        tic
	fopen(ser_obj); % takes 0.2 seconds
%        toc
	ok = strcmp(ser_obj.Status, 'open');
      catch
        % fprintf('ERR: cant open %s\n', port);
        return;
      end
      if (ok)
	fprintf(ser_obj, ['++addr 5' char(10)]);
	fprintf(ser_obj, ['++addr' char(10)]);
	ad = fgetl(ser_obj);
	if (isempty(ad) || (ad(1)~='5'))
          fprintf('WARN: Bad response from Prologix dongle\n');
	else
	  %        fprintf(ser_obj, [char(10)]);
	  %        ad = fgetl(ser_obj); % junk
	  %length(ad)
          fprintf(ser_obj, ['*IDN?' char(10)]);
          rsp = fgetl(ser_obj);
          if (isempty(rsp))
	    fprintf('trying again\n');
            fprintf(ser_obj, ['*IDN?' char(10)]);
            rsp = fgetl(ser_obj);
          end
        end
      end
      fclose(ser_obj);      
    end

  end

  methods

    % CONSTRUCTOR
    function me = agilent86100_class(port)
    % desc: constructor
      me.dbg=1;
      me.ser_obj = [];
      me.settings.hscale=1;
      me.settings.chan=1;
      me.open(port);
    end
    
    % DESTRUCTOR
    function delete(me)
      if (me.isopen())
        me.close();
      end
      delete(me.ser_obj);
    end
    
    function close(me)
      fclose(me.ser_obj);
    end
    
    function b = isopen(me)
      b = strcmp(me.ser_obj.Status,'open');
    end
    
    function open(me, portname)
      ser_obj = serial(portname);
      set(me.ser_obj,'Timeout',4); % 0.2);
      ok=0;
      me.ser_obj = ser_obj;
      try
	fopen(ser_obj); % takes 0.2 seconds
	ok = strcmp(ser_obj.Status,'open');
      catch
        fprintf('ERR: cant open %s\n', portname);
      end
      if (ok)
	fprintf(ser_obj, ['++addr 5' char(10)]);
        me.get_settings();
        me.do_cmd(':MEAS:SEND 1'); % current val returned for quest results.  a comma.  then an errcode.
      end
      me.ser_obj = ser_obj;
    end
    
    function do_cmd(me, cmd)
      if (me.dbg)
        fprintf('tx: %s\n', cmd);
      end
      fprintf(me.ser_obj, [cmd char(10)]);
    end
    
    function rsp=do_cmd_get_rsp(me, cmd)
      rsp='';
      me.do_cmd(cmd);
      for kk=1:2
        rsp = fgetl(me.ser_obj);
        if (length(rsp))
	  break;
	end
      end
      if (me.dbg)
        nc.uio.print_all(rsp);
      end
    end
    
    function m=do_cmd_get_m(me, cmd, dflt)
      m=dflt;
      rsp = me.do_cmd_get_rsp(cmd);
      [v ct] = sscanf(rsp,'%g',1);
      if (ct>0)
        m=v;
      end
    end
    
    
    function set_wavelen_nm(me, nm)
      if ((nm~=1550)&&(nm~=1310))
        error('agilent86100_class.set_wavelen_nm(): only calibrated for 1550 and 1310 ');
      end
      me.do_cmd(sprintf(':CHAN3:WAV WAV%d', 1+(nm==1550)));
    end
    
    function set_averaging(me, num_samps)
      if (num_samps>0)
        me.do_cmd(sprintf(':ACQ:COUN %d',num_samps));
      end
      me.do_cmd(sprintf(':MEAS:ACQ:AVER %d',(num_samps>0)));
      me.settings.averaging = num_samps;
      % rsp = me.do_cmd_get_rsp(':ACQ:AVER?')
    end
    
    function get_settings(me)
      if (~me.isopen())
        return;
      end
      set(me.ser_obj,'Timeout',4);
      
      me.devinfo.sn = me.do_cmd_get_rsp('*IDN?');
      
      me.settings.range = me.do_cmd_get_m(':TIMEBASE:RANGE?',0);
    end

    function set_channel(me, chan)
% chan: 1..3.   3=optical channle      
      me.do_cmd(sprintf(':WAV:SOUR CHAN%d', chan));
      me.settings.chan = chan;
% This returns "VOLT" or "WATT" depending on channel:
%      me.do_cmd_get_m(':WAV:YUN?',0);
    end
    
    function wl = get_wavelen(me)
      if (~me.isopen())
        return;
      end
      set(me.ser_obj,'Timeout',2);
      wl = me.do_cmd_get_m(':CHAN3:WAV?',0);
    end
    
    function amp_V = meas_amplitude_V(me)
      set(me.ser_obj,'Timeout',10);
       %      rsp=me.do_cmd_get_rsp(':MEAS:AMP:SAMP?'); % 86100d only
%      rsp=me.do_cmd_get_rsp(':MEAS:CGR:AMPL? ');
      amp_V = me.do_cmd_get_m(':MEAS:VAMP?',0);
    end

    function max = meas_max(me)
% on optical chan, returnes peak optical power in Watts      
      set(me.ser_obj,'Timeout',4);
      %      rsp=me.do_cmd_get_rsp(':MEAS:AMP:SAMP?'); % 86100d only
%      rsp=me.do_cmd_get_rsp(':MEAS:CGR:AMPL? ');
%      vpp_V = me.do_cmd_get_m(':MEAS:VPP?',0);
      max = me.do_cmd_get_m(sprintf(':MEAS:VMAX? CHAN%d', me.settings.chan),0);
    end

    function amp_V = meas_avg_optical_pwr_W(me)
% NEVER WORKS!      
      amp_V = me.do_cmd_get_m(':MEAS:APOW? WATT',0);      
    end
    
  end
end
