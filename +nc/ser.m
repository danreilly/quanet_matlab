classdef ser

  properties (Constant=true)

  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug cpds reads

    ser_h

  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class


    function init()
      global SERS
      SERS.sershare_ipaddr = '';
      SERS.sershare_h = -1;
      SERS.dbg_print=0;
      SERS.log=0;
      ser_mex(0);
			%This GUI will be acting as a sershare client.
%      SERS.ssc = sershare(); % create sershare client object
      for k=1:4
	SERS.ser(k).open_cnt = 0;
	SERS.ser(k).is_ser  = 1;
      end
      if (1)
      warning('off','MATLAB:serial:fread:unsuccessfulRead');
      warning('off','MATLAB:serial:fgets:unsuccessfulRead');
	      % warning('off','MATLAB:serial:fgetl:unsuccessfulRead');
	      % Clean up serial objects that were not properly closed
      instrs = instrfind();
      for k=1:length(instrs)
	fprintf('WARN: port %s was not cleaned up\n', instrs(k).Port);
	if (strcmpi(instrs(k).Status,'open'))
	  fprintf('WARN: port %s was already open\n', instrs(k).Port);
	  fclose(instrs(k));
	end
	delete(instrs(k));
      end
      end
    end
    
    function ser_h = get_unused_ser_h()
      global SERS
      for k=1:length(SERS.ser)
	if (~SERS.ser(k).open_cnt)
	  ser_h = k;
	  return;
	end
      end
				% grow list
      k=length(SERS.ser)+1;
      SERS.ser(k).open_cnt=0;
      SERS.ser(k).is_ser=1;
      ser_h = k;
    end
  end

  methods

    function me = ser(portname, baud)
% desc: Opens the specified local or remote serial port.
%   If the port is already open, returns the handle to it.
%   there may be multiple connections to same ser port
% inputs:
%   portname: a string.  If a sershare port, is of the form '<ipaddr> <portname>'
%   baud: baud rate
%   use_rts: 0=dont, 1=use rts handshake
% returns: 
%   ser_h = handle to the open port, or 0 if failed.
      global SERS PROG

      if (~exist(SERS))
	ser.init;
      end
      
      % fprintf('DBG: ser_open(%s,%d)\n', portname, baud);
      ser_h = 0;
      idx = strfind(portname, ' ');
      if (length(idx)>1)
	msg('ERR: too many spaces in port name');
	return;
      end

				% check to see if port is already open
      for k=1:length(SERS.ser)
	if (SERS.ser(k).open_cnt && strcmp(SERS.ser(k).portname, portname))
	  ser_h = k;
	  SERS.ser(k).open_cnt = SERS.ser(k).open_cnt + 1;

	  if (PROG.dbg_ser_open)
            fprintf('DBG: ser_open(%s)=%d, cnt %d\n', ...
                    portname, ser_h, SERS.ser(ser_h).open_cnt);
	  end
	  return;
	end
      end

      if (isempty(idx))
	[e port_h] = ser_mex(1, portname, baud);
				% if (e) showerr(); return; end

	if (e)
	  return;
	end

				% success
	ser_h = ser.get_unused_ser_h();
	SERS.ser(ser_h).open_cnt  = 1;
	SERS.ser(ser_h).is_ser   = 1;
	SERS.ser(ser_h).portname = portname;
	SERS.ser(ser_h).port_h   = port_h;
			   %    SERS.ser(ser_h).terminator = char(13);
	SERS.ser(ser_h).timo     = -1; % local copy
				%    SERS.ser(ser_h).ser_buf  = '';
				%    SERS.ser(ser_h).ser_ptr  = 1;
	if (PROG.dbg_ser_open)
	  fprintf('DBG: ser_open(%s)=%d, cnt %d\n', ...
		  portname, ser_h, SERS.ser(ser_h).open_cnt);
	end


				% open a remote serial port
      elseif (idx<2)
	msg('ERR: malformed port name');
      elseif (   (SERS.sershare_h>=0) ...
		 && ~strcmp(portname(1:idx-1), SERS.sershare_ipaddr))
	msg('ERR: cant do simultaneous connections to more than one server');
      else
	if (SERS.sershare_h < 0)
	  connect_to_server(portname(1:idx-1));
	end
	if (SERS.sershare_h>=0)
	  [e port_h] = sershare_open(SERS.ssc, SERS.sershare_h, portname(idx+1:end));
	  if (e)
            return;
	  end

	  e = sershare_set_prop(SERS.ssc, SERS.sershare_h, port_h, 'baud', num2str(baud));
	  if (e)
     %	'DBG: cant set prop'
     %        le = lasterror;
     %le.identifier	
     %        if (~strcmpi(le.identifier, 'sershare:set_prop:failed'))
     %          rethrow(le);
     %        end
            e = sershare_close(SERS.ssc, SERS.sershare_h, port_h);
            if (e)
              msg('WARN: difficulty closing remote port');
            end
            msg(['ERR: ' portname ' set baud ' num2str(baud) ' failed']);
            return;
	  end

	  % success
	  ser_h = ser.get_unused_ser_h();
	  SERS.ser(ser_h).portname = portname;
	  SERS.ser(ser_h).port_h = port_h;
	  SERS.ser(ser_h).open_cnt = 1;
	  SERS.ser(ser_h).is_ser = 0;

	else
	  msg(['ERR: no connection to server ' portname]);
	end
      end

      me.ser_h=ser_h;
    end


    function close(me)
% desc: throws no errors
      global SERS PROG
      ser_h=me.ser_h;
      if ((ser_h>0) && ~SERS.ser(ser_h).open_cnt)
	fprintf('DBG: ser_close(%d) already closed!!\n', ser_h);
      end
      if ((ser_h>0) && SERS.ser(ser_h).open_cnt)
	SERS.ser(ser_h).open_cnt = SERS.ser(ser_h).open_cnt-1;
	if (PROG.dbg_ser_open)
	  fprintf('DBG: ser_close(%s)=%d, cnt=%d\n', ...
		  SERS.ser(ser_h).portname, ser_h, SERS.ser(ser_h).open_cnt);
	end
	if (~SERS.ser(ser_h).open_cnt)
	  if (SERS.ser(ser_h).is_ser)
            e = ser_mex(2, SERS.ser(ser_h).port_h);
            if (e)
              msg('WARN: difficulty closing local port');
            end
	  else
            e = sershare_close(SERS.ssc, SERS.sershare_h, SERS.ser(ser_h).port_h);
            if (e)
              msg('WARN: difficulty closing remote port');
            end
	  end
	end
      end
    end


    function ser_write(me, str)
      global SERS PROG
      ser_h=me.ser_h;
      if ((ser_h>0) && SERS.ser(ser_h).open_cnt)
	if (ser_h==PROG.dbg_dev)
	  fprintf('write: ');
	  uio.print_safe(str);
	end
	if (SERS.ser(ser_h).is_ser)
	  e = ser_mex(3, SERS.ser(ser_h).port_h, str);
	  if (e)
            msg(['ERR: cant write ' SERS.ser(ser_h).portname]);
	  end
	else
	  port_h = SERS.ser(ser_h).port_h;
	  sershare_write(SERS.ssc, SERS.sershare_h, port_h, str);
	end
      end
    end
    
    function bytes_read = ser_flush(me)
      ser_h=me.ser_h;
      [bytes_read, ~, ~] = ser_skip(ser_h, 200, '');
    end
    
    function [str found_key met_timo] = ser_read(me, nchar, timo_ms, search_key)
  % might throw an error
  % reads from device until terminator or timeout or nchar chars read.
  %   search_key = string of chars that cause read to terminate
      global SERS PROG
      found_key=0;
      met_timo=0;
      str='';
      if ((ser_h<1) || ~SERS.ser(ser_h).open_cnt)
	return;
      elseif (SERS.ser(ser_h).is_ser)
	[e str , ~, found_key met_timo] = ...
        ser_mex(4, SERS.ser(ser_h).port_h, nchar, timo_ms, search_key);
	if (ser_h==PROG.dbg_dev)
	  fprintf('read: ');
	  uio.print_safe(str);
	end
      else
	[str found_key met_timo] = ...
        sershare_read(SERS.ssc, SERS.sershare_h, ...
                      SERS.ser(ser_h).port_h, nchar, timo_ms, search_key);
      end
    end
    
  end
  
end
