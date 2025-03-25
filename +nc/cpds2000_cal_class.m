classdef cpds2000_cal_class < nc.cpds2000_class

  
  properties (Constant=true)
    JUNK = 0;
  end
  
  properties
    pwd
  end
  
  methods

    % CONSTRUCTOR
    function me = cpds2000_cal_class(arg1, arg2)
    % desc: cpds2000 constructor
      import nc.*
      args{1}=arg1;
      if (nargin==1)
        arg2.dbg=0;
      end
      me = me@nc.cpds2000_class(arg1, arg2);
    end
    
    function set_password(me, pwd)
      me.pwd = pwd;
      % fprintf('eps1000_cal_class dbg: SET PASSWORD\n');
    end
    
    function err = set_num_flink(me, num_sfp)
      me.pwd = pwd;
      %      me.ser.set_dbg(1);
      % fprintf('eps1000_cal_class dbg: SET PASSWORD\n');
      rsp = me.ser.do_cmd(['cfg write' char(13)]);
      if (strfind(rsp,'pswd'))
        rsp = me.ser.do_cmd(sprintf('%s\r', me.pwd));
      end
      me.ser.set_last_bridge_term(':');
      me.ser.set_timo_ms(2000);
      for k=1:20
        if (strfind(rsp,'has_sfp'))
          [rsp err] = me.ser.do_cmd(sprintf('%d\r', num_sfp));
        else
          [rsp err] = me.ser.do_cmd(sprintf('\r'));
        end
        if (err==3) % This is eventually expected.
          err=0;
          break;
        end
        if (err) % This is not.
          err
          rsp
          break;
        end
      end
      me.ser.set_last_bridge_term('>');
    end
    
  end
end
