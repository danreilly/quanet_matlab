classdef sershareport_class < handle

  properties (Constant=true)

  end

  % instance members
  properties
    dbg  % 0=none, 1=debug IO
    ipaddr
    srv_h
    port_h
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function e=disconnect_all
      %DISCONNECT_ALL Disconnect from all remote sershare servers
      e = nc.sershare_mex(10);
    end

  end

  methods

    % CONSTRUCTOR
    function me = sershareport_class(cli, ipaddr, port)
      % desc: makes a connection to a port on a remote sershare server
      % inputs:
      %   cli: sersharecli_class that manages all connections
      %   ipaddr is of form "192.168.1.2"
      %   port: 
      me.dbg=0;
      me.cli=cli;
      me.srv_h=cli.connect(ipaddr);
      if (me.srv_h>=0)
        e=me.open(port);
	if (e)
	  return;
        end
      end
      %  sets srv_h to -1 on error
    end

    % DESTRUCTOR
    function delete(me)
      me.close();
    end

    function isopen(me)
      if (me.port_h>=0)
        me.close();
      end
    end

    function msg = get_err_msg(me)
      msg = nc.sershare_mex(11);
    end

    function e = open(me, serportname)
      %OPEN open remote serial port
      [e me.port_h] = nc.sershare_mex(3, me.srv_h, serportname);
    end

    function e = close(me)
      %CLOSE close remote serial port
      e = nc.sershare_mex(8, me.srv_h, me.port_h);
      me.port_h=-1;
    end


    function [e portlist] = mswait(me, ms)
      %MSWAIT
      %   ms = milliseconds to wait on remote machine
      % NOTE: yes, you could wait on the local machine.  But the IO latency
      %   to the remote machine can vary greatly, even by seconds!
      e = nc.sershare_mex(2, me.srv_h, ms);
    end

    function e = set_prop(me, name, val)
      %SET_PROP
      %   ssc = sershare client object
      %   con_h = connection handle to remote server
      %   port_h = handle to serial port on that server
      %   name = property name (a string)
      %   val = property value (a string)
      e = nc.sershare_mex(4, me.srv_h, me.port_h, name, val);
    end

    function e = write(me, str)
      %WRITE   Write to remote serial port.
      %   WRITE(PORT_H, STR) writes to the serial port
      %   specified by the port handle PORT_H.  This serial port exists on
      %   a remote machine, and the tcpip connection to the server on that
      %   machine is specified by sershare object.  STR is the string
      %   to write to the port.
      e = nc.sershare_mex(5, me.srv_h, me.port_h, str);
    end

    function [e str found_key met_timo] = read(me, nchar, timo_ms, search_key)
      %READ Gets data from remote serial port
      %   nchar = max num chars to read
      %   timo_ms = timeout in ms (-1 means forever)
      %   search_key = string to search for (may be empty string)
      %  returns:
      %   e = 0=ok, 1=communication error
      %   str = data recieved from port
      %   found_key = 0=didn't find,  1=found search_key
      %
      %   The read will time out if you set a finite timeout
      %   The read will also end if the "search key" is encountered.
      [e str found_key met_timo] = nc.sershare_mex(6, me.srv_h, me.port_h, nchar, timo_ms, search_key);
    end

    function [e bytes_read found_key met_timo] = skip(me, nchar, timo_ms, search_key)
%SKIP   Reads and discards chars from serial port.
%   [BYTES_READ FOUND_KEY MET_TIMO] = SKIP(SSC, CON_H, PORT_H, NCHAR, TIMO_MS, SEARCH_KEY)
%   reads from the serial port specified by the port handle PORT_H.
%   This serial port exists on a remote machine, and the tcpip connection
%   to the server on that machine is specified by connection handle CON_H.
%   NCHAR is the max num chars to read. (-1 means infinite).  
%   TIMO_MS is the read timeout in ms (-1 means forever), and if the timeout
%   is reached first, MET_TIMO is set to 1.
%   SEARCH_KEY is a string (of any length) to search for, and if it is
%   found, FOUND_KEY is set to 1.  BYTES_READ is set to the number of bytes
%   to write to the port.  SSC is a sershare client object. (of which
%   there should only be one, even if multiple connections exist.)
     [e bytes_read found_key met_timo] = nc.sershare_mex(7, me.srv_h, me.port_h, nchar, timo_ms, search_key);
   end

  end

end
