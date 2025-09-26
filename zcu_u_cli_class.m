
classdef zcu_u_cli_class < nc.ncdev_class
% For NuCrypt qna1 device

  properties (Constant=true)
    c_mps = 299792458;
  end
  
  properties
    ser
    % ser_class used to access QNA
    
    devinfo
    % Customization and capability information about this QNA
    %   devinfo.num_voa             1,2, etc

    
    settings
    % Current settings of this pulser.
    % Note: This is a read-only structure.
    %   settings.
    
  end

  methods (Static=true)

  end


  
  methods

    % CONSTRUCTOR
    function me = zcu_u_cli_class(ipaddr)
      import nc.*
      opt.dbg=0;
      me.ser = ser_class(ipaddr, opt);
      if (~me.ser.isopen())
        error('cant open');
      end
      me.ser.cmd_term_char=char(10);
      me.ser.cmd_strip_echo=0;
      me.open();
    end


    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function open(me, arg1, arg2)
      me.get_settings();
    end

    function b=isopen(me)
      b=me.ser.isopen();
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    
    function close(me)
      me.ser.close();
    end
    
    function set=get_settings(me)
      [m err]=me.ser.do_cmd_get_matrix(sprintf('set\r'));
      if (~err && (length(m)==3))
        me.settings.corr_thresh = m(1);
        me.settings.syn_dly     = m(2);
        me.settings.tx_always   = m(3);
      end
    end
    
    function m = dsweep(me)
      [m err]=me.ser.do_cmd_get_matrix(['dsweep' 13]);
    end
    
    function h = set_tx_always(me, en)
      [m err]=me.ser.do_cmd_get_matrix(sprintf('always %d\r', en));
      if (~err && (length(m)==3))
        me.settings.tx_always = m;
      end
    end
    
    function h = set_sync_dly(me, dly_cycs)
      [m err]=me.ser.do_cmd_get_matrix(sprintf('dly %d\r', dly_cycs));
      if (~err && (length(m)==1))
        me.settings.syn_dly=m;
      end
    end

    function h = set_corr_thresh(me, th)
      [m err]=me.ser.do_cmd_get_matrix(sprintf('thresh %d\r', th));
      me.settings.corr_thresh=m;
    end
    
    function [cnt] = meas_cnt(me)
      cnt=0;
      [m err]=me.ser.do_cmd_get_matrix(['cnt' 13]);
      if (~err && (length(m)==1))
        cnt=m;
      end
    end
    
    function [avg mx cnt] = meas_pwr(me)
      [m err]=me.ser.do_cmd_get_matrix(['pwr' 13]);
      if (~err && (length(m)==3))
        avg=m(1);
        mx =m(2);
        cnt=m(3);
      end
    end
    
  end
end
