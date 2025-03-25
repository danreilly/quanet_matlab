classdef tcpclient_class < handle

% 6/7/21 Dan Reilly
% I had been using matlab 2017a, and the tcpclient(), send(), and recv() routines.
% Then I tried to use that on matlab 2010b and they don't exist.  They were introduced
% in matlab 2014b.  Instead of paying for an upgrade, I wrote this mex code.

  properties (Constant=true)
  end

  % instance members
  properties
    soc_h
    Timeout % s   can this be lowercase?
  end

  methods (Static=true)
     % matlab "static" methods do not require an instance of the class
  end

  methods

    % CONSTRUCTOR
    function me = tcpclient_class(ipaddr, port)
      % desc: Opens the specified local or remote serial port.
      % inputs:
      [err soc_h] = nc.tcpclient_mex(0, ipaddr, port);
      if (err)
        error(sprintf('cannot connect to %s:%d', ipaddr, port));
	soc_h=-1;  % should be -1 anyway, but just in case.
      end
      me.soc_h=soc_h;
    end

    function bool = isopen(me)
      bool = (me.soc_h>=0);
    end
    
    % DESTRUCTOR
    function delete(me)
      fprintf('DBG: disconnecting\n');
      err = nc.tcpclient_mex(4, me.soc_h);
    end

    % PROPERTY SET METHODS
    function set.Timeout(me, timo_s)
      me.Timeout = timo_s;
      err = nc.tcpclient_mex(3, me.soc_h, 'Timeout', timo_s);
      if (err)
        printf('ERR: fauled to set property\n');
      end
    end

    function [n_sent, err]= send(me, data)
      [n_sent, err]= nc.tcpclient_mex(1, me.soc_h, typecast(data(:).','uint8'));
    end

    function data = recv(me, nobjs, classstr)
    % data will be uint8.  TIP: use typecast()
      if (~isnumeric(nobjs))
        error('tcpclient_classs.recv(nobjs, classstr): nobjs must be numeric');
      end
      nobjs=double(nobjs); % in case it's int32 or something like that
      if (nargin<3)     nbytes = nobjs;
      elseif (strcmp(classstr,'int32')||strcmp(classstr,'uint32')) nbytes = nobjs*4;
      elseif (strcmp(classstr, 'int8')||strcmp(classstr, 'uint8')) nbytes = nobjs;
      else  error('TODO: class not implemented yet');   end
%      fprintf('DBG: tcpclient_class.recv(%d)\n', nbytes);
      [data, err] = nc.tcpclient_mex(2, me.soc_h, nbytes);
      if (nargin==3)
        data = typecast(data, classstr);
      end
    end

  end

end
