classdef ser_class < handle

% 1/10/2020 Dan Reilly
  
% This class accesses a local or remote (via sershare) serial port.
% Also includes few utility methods, such as one that gets a nucrypt-style
% identify (i) response, and one that performs line oriented commands.
% Now this is a member of the nc package.  

% Bridging
%   This class supports serial connections to "bridged" components.
% What this means is that in addtion to the usual direct serial connection
% to an attached USB device (such as to A below), it also supports
% connections that "bridge" through one unit to another. (Such as through
% A to B below)
%
%      PC  ---  A  --- B
%
%   The device classes for A and B are written such that higher-level software
% opens each of them, and closes each of them, as if they were indepenent USB devices.
% Higher-level software doesn't have to treat B differently just because it's "bridged".
% At a lower level (ser_mex.c), opening B really opens a serial port to A.  The lower
% level of software keeps an "open count" of the number of "connections" open to that serial
% port.  So for example, if software opens both A and B, the "open count" will be two.
% Then if A is closed, the open count decreases to 1, and the serial port is not actually
% closed yet.
%
%   If you construct a ser_class object with a list of devices
% in opt.bridge_objs, it will bridge through that chain of devices
% to communicate with a "bridged" device.
%
% Every device that can "bridge" commands must have some corresponding
% functions in the device class that encapsulate and deencapsulate commands
% in the appropriate manner for that device.  Specicially, each class must
% implement:
%    cmd = bridge_params_cmd(me, chan, params); - set params like baud
%    cmd = bridge_idn_cmd(me, chan);     - forms an identify command
%    [cmd ncmds] = bridge_timo_cmd(me, chan, timo_ms);  - forms one or more cmds to set timo
%    [cmd ncmds] = bridge_set_term_cmd(me, chan, term_char); - forms one or more cmds to set term
%    cmd = bridge_flush_cmd(me, chan);   - forms a cmd to flush
%    cmd = bridge_cmd(me, chan, cmd);    - encapsulates a command
%    rsp = bridge_rsp(me, chan, rsp)     - deencapsulates a response
%    str = bridge_chan_idx2name(me, chan) - for user messages
%          
  
% bridged timeouts
%   The timeouts for devices through which we bridge must be greater
%  than the timout of the final bridged device.

  properties (Constant=true)

  end

  % instance members
  properties
    dbg  % 0=none, 1=debug IO
    dbg_alias
    dbg_ctr
    do_cmd_bug_responses
    is_ser % 1=local com port   0=remote serlink port
%    cpdsser OBSOLETE
%    cpdsfib OBSOLETE
    timo
    port_h
    srv_h % sershare server handle
    portname
    baud
    idn
    cmd_nchar
    cmd_timo_ms
    cmd_term_char % command termination character. Usually '>'.
    cmd_strip_echo

    bridge_objs %  vector of objects (devices) to bridge through
    bridge_chans % vector of "bridge channels". The "bridge channel"
      %                 on each obj through which to bridge.  Channels are
      %                 device specific.
    bridge_params % structure.  device specific.
    last_bridge_term %

    done % for accum_line
    line % for accum_line
    mtrx % for accum_matrix
    mtrx_h
    mtrx_w
    parseline_i % for parseline
    parseline_str
    sersharecli
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function portname = portname_root(portname)
      % strips off "bridging indication" and the colon, if any.
      % For example, [ipaddr:]com#:XXX -> [ipaddr:]com#
      idx = regexpi(portname,'com\d*:','end');
      if (~isempty(idx))
        portname=portname(1:idx(end)-1);
      end
    end
    
    function check_for_unclosed_ports() % static
    % Closes all open matlab serial objects in the run time.
    % (not to be confused with the newer serialport objects.)      
    % This has no effect on ser_class objects, which are
    % all automatically closed by their destructors.
    % This caused trouble for Kieth.
      warning('off','MATLAB:serial:fread:unsuccessfulRead');
      warning('off','MATLAB:serial:fgets:unsuccessfulRead');
      % warning('off','MATLAB:serial:fgetl:unsuccessfulRead');
      % Clean up serial objects that were not properly deleted or closed
      check_instrs=0;
      v=regexp(version(),'\S+','match');
      if (length(v)>1)
        v=str2double(regexp(v{2},'\d*','match'));
        check_instrs = (v<2022);
      end
      if (check_instrs)
        % This gets a list of all matlab serial objects in the run time.
        instrs = instrfind();
        for k=1:length(instrs)
          fprintf('WARN: matlab serial object %s was not cleaned up\n', instrs(k).Port);
          if (strcmpi(instrs(k).Status,'open'))
            fprintf('WARN: matlab serial object %s was already open\n', instrs(k).Port);
            fclose(instrs(k));
          end
          delete(instrs(k));
        end
      end
    end
    
    function init() % static
      global SER_CLASS_G
      nc.ser_class.check_for_unclosed_ports;
      nc.ser_mex(0);
      SER_CLASS_G=1;
    end

    function m = parse_matrix(str) % static
      % NOTE: no longer skips first line
      m=[];
      idxs=regexp(str, '\n');
      if (isempty(idxs))
        return;
      end
      is=1;
      r=0; % row
      for k=1:length(idxs)
        ie=idxs(k)-1;
        [v, ct] = sscanf(str(is:ie), '%g');
% fprintf('  PM: %s -> %g %d', str(is:ie), v, ct);
        if (ct>0)
          r=r+1;
          m(r,1:ct)=v.';
        elseif (r)
          break;
        end
        is=ie+2;
      end
    end

%  function flds = parse_idn_rsp(irsp) % static
%  now we use "get_idn_rsp"

    function v = parse_keyword_val(str, regexpr, dflt, opt)
      % usage:
      %   v = parse_keyword_val(str, regexpr, dflt)
      %   v = parse_keyword_val(str, regexpr, dflt, opt)
      % desc:
      %   searches str for keyword.  Then skips any number of spaces, and optionally an
      %   equal sign. (NOTE: the use of equal signs is DISCOURAGED).  Then this function
      %   reads in a 1xn vector if present.  If number is preceeded by "x" or "0x" it is
      %   considered hexadecimal, otherwise, decimal floating point.  If surrounded by
      %   single quotes, it's parsed as a string value, interpreting double quotes as
      %   a single quote within the string. By default string is also terminated by char 10.
      %   If dflt is a string, quotes are not necessary.  In that case, it skips spaces
      %   (and equal sign if present), parses rest of line as a string, terminated by
      %    char(10) and omitting char(13) if present.
      % intended use:
      %   parsing responses from devices attached by serial ports.
      %   SERIAL PORTS MAY DROP CHARACTERS and do not let that crash your code!
      %   device might not respond with expeced number of values or garbled values.
      %   This function silently tries to continue as best it can.
      % inputs:
      %   regexpr: string to search for.  case insensitive.
      %            or it may be a matlab regular expression.
      %            Some examples (for convenience, but also see Matlab help)
      %               'mask[^=]*'  matches 'mask', 'mask afterpulse', but not any trailing = sign
      %               'clk div'    matches 'clk' followed by one space, followed by 'div'
      %               '\Wfoo\W'    exact match of foo
      %   dflt: default value.
      %   opt: optional stucture of parse options
      %      opt.dbg: 0=normal, 1=print debug msgs
      n=0;
      v=dflt;
      if (nargin<4)
        opt.dbg=0;
      end

%      opt = nc.util.set_if_undef(opt, 'ischar', ischar(dflt));
      l = length(str);
      [sidxs, eidxs] = regexpi(str, regexpr);
      if (~isempty(eidxs))

        if (opt.dbg)
          fprintf('DBG: ser_class().parse_keyword_val()\n     %d matches for "%s":\n', length(eidxs), regexpr);
          cridxs=[0 strfind(str,char(10))];
          for k=1:length(eidxs)
            sli = find(cridxs < sidxs(k), 1, 'last');
            eli = find(cridxs > eidxs(k), 1);
            fprintf('   %d: ', sli);
            nc.uio.print_all(str((cridxs(sli)+1):(cridxs(eli)-1)));
          end
        end

        idx=eidxs(1)+1;
        while((idx<=l)&&iswhite(str(idx))) % skip space
          idx=idx+1;
        end
        if ((idx<=l)&&(str(idx)=='='))
          idx=idx+1;
        end
        while((idx<=l)&&iswhite(str(idx))) % skip more space
          idx=idx+1;
        end
        if ((idx<=l)&&(str(idx)=='['))
          v=[];
          idx=idx+1;
          idxs=strfind(str(idx:end),char(10))+idx-1;
          if (idxs(1)==idx+1) % if is left bracket followed immediately by cr
            idxs=idxs(2:end);
          end
          for k=1:length(idxs)
            [vv, vv_n] = sscanf(str(idx:idxs(k)), '%g');
            idx=idxs(k);
            if (k==1)
              v=vv.';
            else
              if (vv_n ~= size(v,2))
                break;
              end
              v(k,1:vv_n)=vv.';
            end                       
            if (~isempty(strfind(str(idx:idxs(k)),']'))); break; end;
          end
          return;
        elseif ((idx<=l)&&(str(idx)==''''))
          idx=idx+1;
          ie=idx;
          io=1;
          v='';
          while(ie<=l)
            c=str(ie);
            if (c=='''')
              ie=ie+1;
              if ((ie>l)||(str(ie)~=''''))
                break;
              end
            elseif ((c==char(10))||(c==char(13)))
              break;
            end
            v(io)=c;
            ie=ie+1;
            io=io+1;
          end
          idx=ie;
          return;
        elseif (ischar(dflt))
          ie=regexpi(str(idx:end), '[\012\015]')+idx-1; % char 10 or 13
          if (isempty(ie))
            ie=length(str);
          else
            ie=ie(1)-1;
          end
          v=str(idx:ie);
          return;
        elseif ((idx<=l-1)&&(str(idx)=='0')&&(str(idx+1)=='x'))
          [a, n] = sscanf(str(idx:end),' 0x%x');
          v(1:n)=a.';
        elseif ((idx<=l) && (str(idx)=='x'))
          [a, n] = sscanf(str(idx:end),' x%x');
          v(1:n)=a.';
        else
          [a, n] = sscanf(str(idx:end),' %g');
          v(1:n)=a.';
        end
      end
      if (opt.dbg)
        fprintf('DBG: ser_class.parse_keyword_val(%s) ok=%d\n', regexpr,  n);
        fprintf(' %g',  v);
        fprintf('\n');
      end
      if (~n)
        v = dflt;
      end

      %nested
      function b=iswhite(c)
        b = (c==char(32)) || (c==char(9));
      end

    end


    function idn = parse_idn(str)
    % desc: get NuCrypt-style identification response as defined in:
    %  
    % /network_drive/shareddocs/projects/nucrypt_standards/info_command_docver#.doc
    %
    % inputs:
    %     str: string response
    % returns:
    %     idn: identification structure with these fields:
    %      .irsp      : string of idn rsp (case preserved)
    %      .name      : string name (all lowercased)
    %      .model     : model number as a number (though model "numbers" might have alpha!)
    %      .model_str : model number as string
    %      .hwver     : row vector of firmware version
    %      .hwver_str : string firmware version (AVOID USING THIS)
    %      .fwver     : row vector of firmware version
    %      .fwver_str : string firmware version (AVOID USING THIS)
    %      .sn        : lowcase string serial number (WITHOUT SN PREFIX)
    %    
    % NOTE:  The _str fields are included just as emergency bug work-arounds.
    %     If devices are properly written to conform to standard they are superfluous
      idn.irsp='';
      idn.name = '';
      idn.model = 0;
      idn.model_str = '';
      idn.hwver = 0;
      idn.hwver_str = '';
      idn.fwver = 0;
      idn.fwver_str = '';
      idn.sn = '?';

      idn.irsp = str;
  
      flds   = regexp(str, '\S+', 'match');

      flds_l = length(flds);

      while(1) % just so we can break;
        % name
        if (1>flds_l)
          break;
        end
        idn.name = lower(flds{1});
        if (~all(isstrprop(idn.name, 'alphanum')))
          break;
        end
  
        % model
        if (2>flds_l)
          break;
        end
        idn.model_str = flds{2};
        idn.model=sscanf(flds{2},'%d',1);
        
        % hwver
        if (7>flds_l)
          break;
        end
        idn.hwver_str = flds{7};
        verc = regexp(flds{7}, '\d+', 'match');
        idn.hwver = zeros(1, length(verc));
        for m=1:length(verc)
          idn.hwver(m)=sscanf(verc{m},'%d',1);
        end
  
        % fwver
        if (8>flds_l)
          break;
        end
        idn.fwver_str = flds{8};
        verc = regexp(flds{8}, '\d+', 'match');
        idn.fwver = zeros(1, length(verc));
        for m=1:length(verc)
          idn.fwver(m)=sscanf(verc{m},'%d',1);
        end
  
        % sn
        if ((9>flds_l)||(length(flds{9})<2) || ...
            ~(strcmp('sn',lower(flds{9}(1:2)))))
          break;
        end
        idn.sn = lower(flds{9}(3:end));
        break;
      end
    end

  end

  methods (Access = private)

    function rsp = l_get_rsp(me) 
      % desc: low-level get rsp
      ts=tic();
      [rsp, ~, to] = me.read(me.cmd_nchar, me.cmd_timo_ms, me.cmd_term_char);
      if (logical(me.dbg) && to)
        fprintf('WARN: ser_class.do_cmd() timo (after %g ms) on port %s\n', ...
                me.cmd_timo_ms, me.dbg_alias);
        fprintf('  actual time %g s\n', toc(ts));
        fprintf('     in rsp: ');
        nc.uio.print_all(rsp);
        fprintf('\n');
%        error('DBG');
        err=3;
      end
    end

    function private_start_cmd(me, cmd)
      import nc.*                        
      me.line='';
      me.mtrx=[];
      if (~me.isopen())
        fprintf('DBG %s: ser_class.start_cmd() called but ser not open\n', me.dbg_alias);
        me.done=1;
        return;
      end
      
      me.done=0;
      if (me.dbg) 
        % fprintf('DBG %s: ser_class.start_cmd ', me.dbg_alias);
        % uio.print_all(cmd);
      end

      for k=length(me.bridge_objs):-1:1
        % fprintf('DBG: bridge to %s\n', me.bridge_objs(k).idn.name);
        cmd = me.bridge_objs(k).bridge_cmd(me.bridge_chans(k), cmd);
      end
      me.write(cmd);
    end
    
  end

  methods

    % CONSTRUCTOR
    function me = ser_class(portname, baud, opt)
      % desc: Opens the specified local or remote serial port.
      % usage:
      %    ser_class(portname, baud)
      %    ser_class(portname, opt)
      %    ser_class(portname, baud, opt)
      %
      % inputs:
      %   portname: a string. General format (where square brackets
      %        indicate optional stuff) is:
      %           [ipaddr:]com#[:[f][s]]
      %        Where ipaddr is ipaddress or machine name of sershare server,
      %        com# is com port name.  f indicates remote cpds over fiberlink,
      %        and s indicates serial device attached to cpds via serlink.
      %      TODO: is this [f] and [s] stuff really used now that we have opt.bridge_objs ??
      %   baud: baud rate
      %   opt: optional structure of fields:
      %     opt.dbg: 0=normal, 1=debug
      %     opt.baud: buad rate (Hz)
      %     opt.sersharecli: sershare client object
      %     opt.bridge_objs : vector of objects (devices) to bridge through
      %     opt.bridge_chans: vector of "bridge channels". The "bridge channel"
      %                 on each obj through which to bridge.  Channels are
      %                 device specific.
      global SER_CLASS_G
      import nc.*

      if (isempty(SER_CLASS_G) || ~SER_CLASS_G)
        ser_class.init;
      end

      if (nargin<3)
        if (isstruct(baud))
          opt = baud;
          baud = opt.baud;
        else
          opt.dbg=0;
        end
      end
      if (~isfield(opt, 'dbg'))
        opt.dbg=0;
      end
      if (numel(opt.dbg)~=1)
        opt.dbg=0;
      end
      if (~isfield(opt, 'sersharecli'))
        opt.sersharecli=[];
      end
      if (~isfield(opt, 'bridge_objs'))
        opt.bridge_objs=[];
      end
      if (~isfield(opt, 'bridge_chans'))
        opt.bridge_chans=[];
      end
      if (~isfield(opt, 'bridge_params'))
        opt.bridge_params=[];
      end
      if (length(opt.bridge_objs) ~= length(opt.bridge_chans))
        error('opt.bridge_objs must be same length as opt.bridge.chans');
      end

      me.idn = [];
      me.dbg = logical(opt.dbg);
      me.dbg_ctr=0;
      me.do_cmd_bug_responses={};
      me.port_h=-1;
      me.srv_h=-1;
      me.portname = portname;
      me.dbg_alias = portname;
      me.baud = baud;
      me.cmd_nchar = 10000;
      me.cmd_timo_ms = 2000;
      me.cmd_term_char = '>';
      me.last_bridge_term = 0;
      me.cmd_strip_echo = 1;
      me.bridge_objs = opt.bridge_objs;
      me.bridge_chans = opt.bridge_chans;
      me.bridge_params = opt.bridge_params;
      me.open(opt);
    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
        if (me.dbg)
          fprintf('DBG %s: ser_class.delete calls close\n', me.dbg_alias);
        end
        me.close;
      end
    end

    function f=isopen(me)
      f = (me.port_h>=0);
    end

    function open(me, portname, opt)
    % ser_class.open()
    % use:
    %   ser.open()
    %   ser.open(portname)
    %   ser.open(opt)
    %   ser.open(portname, opt)
    % desc:
    %   opens device and gets identity and current settings
		 % maybe it should not get idn?
    % inputs:
    %   portname: string. if omitted or '', uses prior.
%            if nonempty, overrides opt.portname
%              General format (where square brackets
%              indicate optional stuff) is:
%                 [ipaddr:]com#[:[f][s][2]]
%              Where ipaddr is ipaddress or machine name of sershare server,
%              com# is com port name.
%              Empt string=use prior port
    %   opt: optional structure of options
    %     opt.portname: optional string.  If omitted, or '', uses prior
    %     opt.baud: optional int.  0=use prior baud
    %     opt.dbg: prints all tx and rx to monitor
      import nc.*
      if (me.dbg)
        fprintf('DBG %s: ser.open()\n', me.dbg_alias);
      end

      if (me.isopen())
        fprintf('WARN: ser_class.open: %s already open\n', me.dbg_alias);
        return;
      end

      % guarantee existance and types of portname and opt structure
      if (nargin==1)
        portname='';
        opt.dbg=0;
      elseif (nargin==2)
        if (isstruct(portname))
          opt = portname;
          portname='';
        else
          opt.dbg=0;
        end
      end
      if (~ischar(portname))
        error('BUG: ser_class.open(portname): portname not a string');
      end
      if (~isstruct(opt))
        error('BUG: ser_class.open(portname, opt): opt not a struct');
      end
      me.dbg=logical(opt.dbg);
      me.dbg_ctr=0;


      % determine params based on default hierarchy
      if (isempty(portname) && isfield(opt, 'portname'))
        portname = opt.portname;
      end
      if (isempty(portname))
        portname = me.portname; % use prior
      end
      if (isempty(portname))
        error('BUG: ser_class.open(): portname unspecified');
      end


      baud = 0;
      if (isfield(opt,'baud'))
        baud=opt.baud;
      end
      if (baud==0)
        baud=me.baud;
      end
      if (baud==0)
        baud=115200; % nucrypt-wide default baud
      end


      me.portname = portname;

      idx = strfind(portname, ' ');
      if (length(idx)>1)
        error(sprintf('BUG: ser_class.open(%s): spaces not allowed in port name', portname));
        return;
      end
      colidxs = strfind(portname, ':');
      portonlyname=portname;
      me.is_ser=1;
      if (~isempty(colidxs))
        % TODO: does not work for ip host names starting with "com"!
        if (strcmpi(portname(1:min(3,(colidxs(1)-1))),'com'))
          portonlyname=portname(1:(colidxs(1)-1));
        else
          me.is_ser=0;
        end
      end

      if (me.is_ser)

        [e port_h] = nc.ser_mex(1, portonlyname, baud);
        if (e)
          me.port_h = -1;
          % showerr();
          return;
        end
        me.port_h   = port_h;
        me.timo     = -1; % local copy
        if (me.dbg)
          fprintf('DBG %s: ser_open(%s, baud %d)=%d\n', me.dbg_alias, portname, baud, port_h);
        end
        if (baud==460800)  % TODO: FIX
          e = nc.ser_mex(8, port_h, 1); % set use RTS. works for now.
          if (e)
            error(['ERR: cant use RTS on ' portname]);
          end
        end

        if (~isempty(me.bridge_objs) && ~isempty(me.bridge_params))
          me.set_bridge_params(me.bridge_params);
        end

        
      else % open a remote serial port

        colidx = colidxs(end);
        ipaddr = portname(1:colidx-1);

	me.sersharecli = opt.sersharecli;
        me.srv_h = me.sersharecli.connect(ipaddr);
        if (me.srv_h<0)
          fprintf('ERR: cant connect to sershare server at %s\n', ipaddr);
        else
          [e port_h] = nc.sershare_mex(3, me.srv_h, portname(idx+1:end));
          if (e)
            return;
          end
          e = nc.sershare_mex(4, me.srv_h, port_h, 'baud', num2str(baud));
          if (e)
            e = nc.sershare_mex(8, me.srv_h, port_h);
            if (e)
              fprintf('WARN: difficulty closing remote port');
            end
            fprintf('ERR: %s set baud %d failed\n', portname, baud);
            return;
          end
          me.baud=baud;

          % success
          me.port_h = port_h;
        end
      end

    end

    function close(me)
        % desc: throws no errors
      import nc.*
      if (~me.isopen)
        fprintf('DBG %s: ser_close(%s) already closed!!\n', me.dbg_alias, me.portname);
        return;
      end
      if (me.dbg)
        fprintf('DBG %s: ser.close(%s)\n', me.dbg_alias, me.portname);
      end
      if (me.is_ser)
        e = ser_mex(2, me.port_h);
        if (e)
          fprintf('WARN: difficulty closing local port, e=%d\n', e);
        end
        me.port_h=-1;
      else
        e = nc.sershare_mex(8, me.srv_h, me.port_h);
        if (e)
          fprintf('WARN: difficulty closing remote port\n');
        end
        me.port_h=-1;
      end
    end

    function set_dbg(me, val, alias)
    % alias = name to print in debug messages to identify com port
      if (nargin>2)
        me.dbg_alias=alias;
      else
        me.dbg_alias = me.portname;
      end
      me.dbg = logical(val);
    end

    
    function e=write(me, str)
    % e: 0=ok, otherise timo or other failure
      import nc.*
      e=0;             
      if (me.isopen)
        if (me.dbg)
          fprintf('DBG %s: write: ', me.dbg_alias);
          uio.print_all(str);
        end
        if (me.is_ser)
          e = ser_mex(3, me.port_h, str);
        else
          e = sershare_mex(5, me.srv_h, me.port_h, str);
        end
        if (e && logical(me.dbg))
          fprintf(['ERR: cant write ' me.portname '\n']);
        end
      end
    end

    function set_bridge_params(me, params)
    % sets com params of last bridging objet
      if (~isempty(me.bridge_objs))
        l = length(me.bridge_objs);
        ca = me.bridge_objs(l).bridge_params_cmd(me.bridge_chans(l),me.bridge_params);
        for k=1:length(ca)
          cmd=ca{k};
          for m=l-1:-1:1
            % fprintf('DBG: timo %s\n', me.bridge_objs(m).ser.dbg_alias);
            cmd = me.bridge_objs(m).bridge_cmd(me.bridge_chans(m), cmd);
          end
          if (1) % me.dbg)
            fprintf('DBG %s: ser_class.set_bridge_params\n  cmd:', me.dbg_alias);
            nc.uio.print_all(cmd);
            % fprintf(')\n');
          end
          me.write(cmd);
          %      [me.cmd_nchar, me.cmd_timo_ms, double(me.cmd_term_char)]
          me.l_get_rsp(); % dont bother checking rsp
        end
      end
    end
    
    function bytes_read = flush(me)
      if (~isempty(me.bridge_objs))
        l = length(me.bridge_objs);
        cmd = me.bridge_objs(l).bridge_flush_cmd(me.bridge_chans(l));
        if (isempty(cmd))
          return; % cant do it so do nothing
        end

        for m=l-1:-1:1
          % fprintf('DBG: timo %s\n', me.bridge_objs(m).ser.dbg_alias);
          cmd = me.bridge_objs(m).bridge_cmd(me.bridge_chans(m), cmd);
        end
        if (me.dbg)
          fprintf('DBG %s: ser_class.flush()\n  cmd:', me.dbg_alias);
          uio.print_all(cmd);
          fprintf(')\n');
        end
        me.write(cmd);
        me.l_get_rsp(); % dont bother checking rsp

      else  
        [bytes_read, ~, ~] = me.skip(200, '');
        if (me.dbg)
          fprintf('DBG %s: flushed %d input bytes.\n', me.dbg_alias, bytes_read);
        end
      end
%      if (~me.cpdsfib && (me.cpdsser==1))
%        cmd_l = ['ser f' cmd 13];
%        me.write(cmd);
%      elseif (~me.cpdsfib && (me.cpdsser==2))
%        cmd_l = ['ser1 f' cmd 13];
%        me.write(cmd);
%      end
    end

    function [bytes_read found_key met_timo] = skip(me, timo_ms, search_keys)
      import nc.*
       % reads from device until terminator or timeout
      found_key=0;
      met_timo=0;
      bytes_read=0;
      if (~me.isopen)
        return;
      elseif (me.is_ser)
        [~, bytes_read, found_key, met_timo] = ...
          ser_mex(5, me.port_h, -1, timo_ms, search_keys);
      else
        % NCHAR is the max num chars to read. (-1 means infinite).
        nchar=-1;
        [e bytes_read found_key met_timo] = ...
          sershare_mex(7, me.srv_h, me.port_h, nchar, timo_ms, search_keys);
      end
    end
    
    function [str, found_key met_timo dt] = read(me, nchar, timo_ms, search_keys)
   % reads from device until terminator or timeout or nchar chars read.
   %  inputs:
   %    search_keys: string of chars that cause read to terminate
   %    nchar:= -1=unlimited.  otherwise, max num chars to read
   %    timo_ms: must be >= 0
   % outputs:
   %   str: string received.
   %   found_key: 1=found one of search_kesy.  0=did not.
   %   met_timo:  1=reached timeout.  0=did not.
   %   dt: actual time elapsed. added for debug. May be removed in future version!
      import nc.*
      found_key=0;
      met_timo=0;
      str='';
      dt=0;
      if (~me.isopen)
        return;
      elseif (me.is_ser)
        if (length(search_keys)>1)
          error('no more');
        end

        [e str nread found_key met_timo dt] = ...
             ser_mex(4, me.port_h, nchar, timo_ms, search_keys);
        if (logical(met_timo) && logical(me.dbg) && (me.dbg_ctr<20))
          if (me.dbg)
            fprintf('DBG: %s: timo (%d ms) from ser_mex, nread = %d keys %s\n', ...
                    me.dbg_alias, timo_ms, nread, sprintf('%d ',double(search_keys)));
          end
          me.dbg_ctr = me.dbg_ctr+1;
        end
      else
        [e str found_key met_timo] = ...
             sershare_mex(6, me.srv_h, me.port_h, nchar, timo_ms, search_keys);
      end
      if (logical(me.dbg) && (~isempty(str) || (me.dbg_ctr<20)))
        if (e)
          fprintf('DBG %s: read returned e=%d!  met_timo %d\n', e, met_timo);
        end
        fprintf('DBG %s: read: ', me.dbg_alias);
        nc.uio.print_all(str);
   %     fprintf('    numchar %d\n', length(str));
%        fprintf('e %d  nr %d (%d) fk %d to %d\n', e, nread, ...
%                nchar, found_key, met_timo);
      end
    end


    function parseline_set_str(me, str)
      me.parseline_str = strrep(str, char(13), ''); % strip stupid CRs
      me.parseline_i = 1;
    end
 
    function str=parseline_getline(me)
    % first call parseline_set_str to declare the string to parse lines out of.
    % skips empty lines and spaces.
    % returns one line, or [] when nothing left to parse.
    % does not return char(10) as part of the line.
      k=me.parseline_i;
      l = length(me.parseline_str);
      while ((k<l) && (me.parseline_str(k)<=char(32)))
        k=k+1;
      end
      ke=k;
      while ((ke<l) && (me.parseline_str(ke)~=char(10)))
        ke=ke+1;
      end
      me.parseline_i = ke+1;
      % fprintf('me.parseline_strparse %d %d %d\n',l, k, ke);
      if (k>l)
        str=[]; % past end
      else
        str=me.parseline_str(k:ke-1);
        % fprintf('parseline %s\n', rsp(k:ke-1));
      end
    end

    function idn = get_idn_rsp(me)
    % desc: get NuCrypt-style identification response as defined in:
    %  
    % /network_drive/shareddocs/projects/nucrypt_standards/info_command_docver#.doc
    %
    % inputs:
    %     me: ser_class object representing a serial port
    % returns:
    %     idn: identification structure with these fields:
    %      .irsp      : string of idn rsp (case preserved)
    %      .name      : string name (all lowercased)
    %      .model     : model number as a number (though model "numbers" might have alpha!)
    %      .model_str : model number as string
    %      .hwver     : row vector of firmware version
    %      .hwver_str : string firmware version (AVOID USING THIS)
    %      .fwver     : row vector of firmware version
    %      .fwver_str : string firmware version (AVOID USING THIS)
    %      .sn        : lowcase string serial number (WITHOUT SN PREFIX)
    %  This also sets me.idn to this structure, for future use.  
    %    
    % NOTE:  The _str fields are included just as emergency bug work-arounds.
    %     If devices are properly written to conform to standard they are superfluous
      import nc.*                                        

      
      
      str='';
      timo_sav_ms = me.cmd_timo_ms;
      while(1) % just so we can break      

        if (~me.isopen)
          break;
        end

        l=length(me.bridge_objs);
        if (me.dbg)
          fprintf('\nDBG %s: ser_class.get_idn_rsp()\n', me.dbg_alias);
          if (l)
            fprintf('  bridging: ');
            for bi=1:l
              fprintf('   %s %d', class(me.bridge_objs(bi)), me.bridge_chans(bi));
            end
            fprintf('\n');
          end
        end

        if (l) % if bridging


          
          % set large timeout for first device,
          % and decreasing timeouts for each subsequent device the
          % communication passes through
          me.cmd_timo_ms = 500+l*100;
          timo_ms=me.cmd_timo_ms-100;
          for k=1:l
            [cmd ncmds] = me.bridge_objs(k).bridge_timo_cmd(me.bridge_chans(k), timo_ms);
            for ci=1:ncmds % This annoying ncmds garbage is thanks to the cpds 1000 menu interface
              if (ci>1)
                cmd='';
              end
              for m=k-1:-1:1
                % fprintf('DBG: timo %s\n', me.bridge_objs(m).ser.dbg_alias);
                cmd = me.bridge_objs(m).bridge_cmd(me.bridge_chans(m), cmd);
              end
              if (me.dbg || (ncmds>1))
                fprintf('  encapsulated timo cmd for bridge obj %d: ', k);
                uio.print_all(cmd);
              end
              if (~isempty(cmd))
                me.write(cmd);
                me.l_get_rsp(); % dont bother checking rsp
              end
            end
            timo_ms=timo_ms-100;
          end


          cmd = me.bridge_objs(l).bridge_idn_cmd(me.bridge_chans(l));
          if (me.dbg)
            fprintf('  raw idn cmd: ');
            uio.print_all(cmd);
          end
          
          if (isempty(cmd))
            rsp='';
          else
            for k=l-1:-1:1
              cmd = me.bridge_objs(k).bridge_cmd(me.bridge_chans(k), cmd);
            end
            if (me.dbg)
              fprintf('  encaps idn cmd: ', me.dbg_alias);
              uio.print_all(cmd);
            end
            me.write(cmd);
            rsp = me.l_get_rsp();
          end
          
          % 6/1/23: bridge device may or may not have lcl echo.
          % So dont strip that here.  Let that be done in obj.bridge_rsp().
%          idx=strfind(rsp,char(10));
%          if (~isempty(idx))
%            if (me.dbg)
%              fprintf('DBG %s: ser_class.get_idn_rsp: strip lcl echo:', me.dbg_alias);
%              nc.uio.print_all(rsp(1:idx(1)-1));
%            end
%            rsp=rsp(idx(1)+1:end);
%          end

% 6/22/20: changed loop to be 1:l instead of 1:l-1.
% don't know why it was the way it was.
          for k=1:l
            if (me.dbg)
              fprintf('  rsp: ');
              uio.print_all(rsp);
              fprintf('\n');
            end
            rsp = me.bridge_objs(k).bridge_rsp(me.bridge_chans(k), rsp);
            if (me.dbg)
              fprintf('  de-encapsulated rsp: ');
              uio.print_all(rsp);
              fprintf('\n');
            end
          end


         if (0)
            % DBG try flush
            cmd = me.bridge_objs(l).bridge_flush_cmd(me.bridge_chans(l));
            for k=l-1:-1:1
            cmd = me.bridge_objs(k).bridge_cmd(me.bridge_chans(k), cmd);
            end
            me.write(cmd);
            frsp = me.l_get_rsp();
            if (me.dbg)
              frsp
            end
          end
          
          % fprintf('done get_idn_rsp(%s)\n', me.dbg_alias);

% TODO: maybe should restore to previous instead.
          % set 1000ms timo for last bridger
          l=length(me.bridge_objs);
          [cmd, ncmds] = me.bridge_objs(l).bridge_timo_cmd(me.bridge_chans(l), 1000);
          if (me.dbg)
            fprintf('DBG: timo 1000 for %s\n', me.bridge_objs(l).ser.dbg_alias);
          end
          if (~isempty(cmd))

            for k=l-1:-1:1
              cmd = me.bridge_objs(k).bridge_cmd(me.bridge_chans(k), cmd);
            end
            me.write(cmd);
            me.l_get_rsp(); % dont bother checking rsp
            
            if (ncmds>1)
              cmd='';
              for k=l-1:-1:1
                cmd = me.bridge_objs(k).bridge_cmd(me.bridge_chans(k), cmd);
              end
              for ci=2:ncmds
                if (me.dbg)
                  fprintf('ci %d\n', ci);
                end
                if (~isempty(cmd))
                  me.write(cmd);
                end
                rsp2 = me.l_get_rsp(); % dont bother checking rsp
              end
            end
          end
          
          rsp = strrep(rsp, char(13), ''); % strip stupid CRs
          
          % set str to first line longer than 16 chars.
          idxs=[strfind(rsp, char(10)) length(rsp)+1];
          ii=1;
          for k=1:length(idxs)
            if ((k==length(idxs)) || (idxs(k)-ii >= 16))
              str=rsp(ii:idxs(k)-1);
              break;
            end
            ii=idxs(k)+1;
          end

        else
          % If the device is in some kind of push-any-key pause loop,
          % then sending it an abitrary char would make the device continue,
          % possibly beginning an action that takes a long time (such as when
          % the cpds is in "manual" mode.)  We want a fast response.
          % We expect that in such loops, all devices recognize 'i' as an
          % "identify and go to top" command.
          %
          % But what if the device is in some kind of get-decimal-number routine?
          % It will be looping and getting chars until it gets a return char.
          % We don't expect the device to interpret the 'i' command in such a case.
          if (me.dbg)
            fprintf('DBG %s: local idn\n', me.dbg_alias);
          end
          e=me.write(['i' char(13)]);
          if (e)
            if (me.dbg)
              fprintf('DBG %s: write failure!\n');
            end
            break;
          end

          % After that, the device might respond with valid info,
          % an echo and then valid info, or with garbage.
          while(1)
            [str found_key to] = me.read(256, 100, char(10));
            if (to)
              break;
            end
            str = regexprep(str,'[\n\r]*','');
            % i rsp should be at least 16 chars long
            if (length(str)>16)
              break;
            end
          end
          if (length(strfind(str,' '))==8)
            pause(0.05);
            me.flush;
            break;
          end
          me.flush;
    
          % Now we expect that the device will recognize 'i' as an identify command.
          % In the case of command-line type interfaces (as opposed to menu type
          % interfaces) we send a return char after the 'i'.
          e=me.write(['i' char(13)]);
          if (e) break; end
    
          str='';
          while(1)
            [str found_key to] = me.read(256, 100, char(10));
            if (to)
              break;
            end
            str = regexprep(str,'[\n\r]*','');
            % i rsp should be at least 16 chars long
            if (length(str)>16)
              break
            end
          end
          % some devices re-display the menu. skip that.
          pause(0.05);
          me.flush;
          break;
        end
              
        break;
      end % breakable while 
      me.cmd_timo_ms = timo_sav_ms;
      if (~isempty(str) && (str(end)==me.cmd_term_char))
        str = str(1:end-1);
      end
      idn=me.parse_idn(str);
      me.idn = idn;
    end




    function set_last_bridge_term(me, ch)
    % called from do_cmd or start_cmd_accum      
      if (me.last_bridge_term ~= ch)
        l = length(me.bridge_objs);
        [cmd ncmds] = me.bridge_objs(l).bridge_set_term_cmd(me.bridge_chans(l),ch);
        if (~isempty(cmd))
          for ci=1:ncmds
            if (ci>1)
              cmd='';
            end
            for m=l-1:-1:1
              % fprintf('DBG: timo %s\n', me.bridge_objs(m).ser.dbg_alias);
              cmd = me.bridge_objs(m).bridge_cmd(me.bridge_chans(m), cmd);
            end
            if (0) % me.dbg)
              fprintf('DBG %s: ser_class.set_term ncmds %d  ci %d\n  cmd:',  me.dbg_alias, ncmds, ci);
              nc.uio.print_all(cmd);
              % fprintf(')\n');
            end
            % cant call do_cmd or would recurse forever.
            me.write(cmd);
            me.l_get_rsp(); % dont bother checking rsp
          end
        end
      end
      me.last_bridge_term = ch;
    end
    
    function [line done] = accum_line(me)
    % desc: Returns a line (ending in chr(10)) as soon as one has been accumulated.
    %       If no line accumulated within one second, then it returns empty string.
    %       If reading through a bridging device, and the bridged read
    %       times out, it gets re-issued and done is not set.  Only the terminator from
    %       the ultimate device causes done to be set.
    %       works for bridged communictions too.
    % returns:      
    %   line: ''=no line yet.  otherwise, will at least have a CR char in it.
    %   done: 1=done command (got cmd terminator from ultimate target)
      line='';
      gotline=0;
      if (~me.isopen)
        me.done=1;
        done=1;
        return;
      end
      done=0;
      %      % 7/18/23: attempt to wean myself off the multi-char search.
      %      % in pathological cases there may be an extra 1-second delay but who cares.
      %      [rsp found_key to] = me.read(-1, 1000, char(10));
      %   However did not work when reading continuous mode from remote CPDS
      %   via the RCS fiberlink.  Because the rcs "r" cmd must time out.

      
      if (isempty(me.bridge_objs))
        cmd_term = char(10);
      else
        if (me.done)
          % me.done is state of most immediate bridge, whether got > yet.
          % fprintf('DBG: read more\n');
          me.private_start_cmd(''); % read more from remote.  zeros me.done.
        end
        cmd_term = me.cmd_term_char;
      end
      [rsp found_key to] = me.read(-1, 1000, cmd_term);
      fcr=0;
      fgt=0;
      if (~isempty(me.bridge_objs))
        me.done = found_key;
        if (found_key)
          rsp=rsp(1:(end-1));
        end

        % fprintf('   al1: ');    nc.uio.print_all(rsp);
        for k=1:length(me.bridge_objs)
          rsp = me.bridge_objs(k).bridge_rsp(me.bridge_chans(k), rsp);
        end
        if (me.dbg)
          fprintf('   acc2: ');    nc.uio.print_all(rsp);
        end
        fgt = any(strfind(rsp,me.cmd_term_char));
        fcr = any(strfind(rsp,char(10)));
      else
        fgt = any(strfind(rsp,me.cmd_term_char));
        fcr = any(strfind(rsp,char(10)));
        me.done = fgt;
      end
      
      if (fcr)
        line = [me.line  rsp];
        me.line='';
      else
        line=[];
        me.line=[me.line  rsp];
      end
      done = fgt;
    end

    
    function accum_stop(me)
    % NOT USED YET!
      if (~me.done)
        fprintf('ERR: accum not done!!!\n');
      end
      me.done=1;
    end

    function [m done] = accum_matrix(me)
      % desc: always returns after one second, may return sooner
      % m:  matrix accumulated so far
      % done: 1=done command (got > prompt)
      start_tic=tic();
      done=0;
      while(~done)
        [line done] = me.accum_line();
        if (~isempty(line))
          [v ct]=sscanf(line, '%d');
          if (ct>0)
            r = size(me.mtrx,1)+1;
            me.mtrx(r,1:ct)=v.';
          end
        end
        if (done || (toc(start_tic)>1))
        end
      end
      if (done)
        m=me.mtrx;
      else
        m=[];
      end
    end

    function set_timo_ms(me, timo_ms)
      if (me.dbg)
        fprintf('DBG %s: set_timo %d\n', me.dbg_alias, timo_ms);
      end
      % set large timeout for first device,
      % and decreasing timeouts for each subsequent device the
      % communication passes through
      l=length(me.bridge_objs);
      me.cmd_timo_ms = timo_ms+l*100;
      timo_ms=me.cmd_timo_ms-100;
      for k=1:l
        [cmd ncmds] = me.bridge_objs(k).bridge_timo_cmd(me.bridge_chans(k), timo_ms);
        for ci=1:ncmds
          if (ci>1)
            cmd='';
          end
          for m=k-1:-1:1
            % fprintf('DBG: timo %s\n', me.bridge_objs(m).ser.dbg_alias);
            cmd = me.bridge_objs(m).bridge_cmd(me.bridge_chans(m), cmd);
          end
          if (me.dbg || (ncmds>1))
            nc.uio.print_all(cmd);
%           fprintf(')\n');
          end
          if (~isempty(cmd))
            me.write(cmd);
            me.l_get_rsp(); % dont bother checking rsp
          end
        end
        timo_ms=timo_ms-100;
      end

      
      % TODO: restore intervening timeouts?
    end

    function set_cmd_params(me, nchar, timo_ms)
  %    nchar= -1=unlimited.  otherwise, max num chars to read
  %    timo_ms: passed to ser_mex. must be >=0
      if (me.dbg)                           
        fprintf('DBG %s: set_cmd_params %d %d\n', me.dbg_alias, nchar, timo_ms);
      end
      me.cmd_nchar = nchar;
      me.set_timo_ms(timo_ms);
    end

    function set_do_cmd_bug_responses(me, strs)
    % strs = cell array of strings
      me.do_cmd_bug_responses = strs;
    end

    function [rsp, err] = do_cmds(me, cmd, num_cmds, timo)
% desc: may be aborted by user
%   Many of the commands will do somthing, such as change to a sub-menu,
%   and then print a prompt.  This can routine will send the command
%   and examines the response as a confirmation of success.
%   If device is not open, returns [] without any error
%   may contain multiple commands, if num_cmds>1                              
% inputs:
%   cmd: string to send as a command.
%        typically, cpds2000 commands end with char(13)
%        but most of the time, cpds1000 and pa commands do not.
%   pdev_h: handle to pdev (index into DEVS.pdevs)                     
%   timo: optional.  If omitted, infinite timeout.
% returns:
%   rsp
%   err                      
      me.private_start_cmd(cmd);

      rsp='';

      cmd_ctr=0;
      while (1)
        [rsp_part, found_key met_timo] = me.read(-1, 1000, me.cmd_term_char);
  %     if (DEVS.rsp_to_msg)
  %       msg_no_nl(rsp_part)
  %       drawnow;
  %     end
        if (logical(me.dbg) && ~isempty(rsp_part))
          dbgs = [char(9) sprintf_safe(rsp_part) char(10)];
          fprintf('%s', dbgs);
          if (PROG.dbg_log>=0)
            fprintf(PROG.dbg_log, dbgs);
          end
          % fprintf(' len %d\n', length(rsp_part));
        end
        rsp = [rsp rsp_part];
        if (found_key)
          cmd_ctr=cmd_ctr+1;
          if (cmd_ctr>=num_cmds)
            break;
          end
        end
  
        if ((timo~=inf) && (toc > timo))
  %        msg_red_nl('ERR: cmd timeout');
          err=1;
          break;
        end
  %    drawnow;
  %    if (USER.abort_flag)
  %      err=1;
  %      if ((vdi~=DEVS.VEPS)&&(vdi~=DEVS.VCPDS))
  %$        break;
  %      end
  %      if (~aborting)
  %        dev.abort()
  %        aborting=1;
  %      else
  %        break;
  %      end
      end
    end

    function [rsp, err] = start_cmd_accum(me, cmd)
    % desc: call this to start a command, but not finish it.
    %       next you repeatedly call accum_line().
      if (length(me.bridge_objs)>0)
        set_last_bridge_term(me, char(10));
      end
      me.private_start_cmd(cmd);
    end
    
    function [rsp, err] = finish_cmd(me)
    % after using accum line, if expecting a CR next can just call this
      if (length(me.bridge_objs)>0)
        set_last_bridge_term(me, '>');
        me.private_start_cmd('');
      end
      [rsp, err] = me.get_cmd_rsp('');
    end
    
    function [rsp, err] = do_cmd(me, cmd, rsp_need, rsp_err)
    % desc: sends cmd to serial device, then reads response until
    %       terminating character '>' is received.  Strips all echos.
    % inputs:
    %     me: this ser_class object
    %     cmd: string to send to that port
    %     rsp_need: optional string which is required in the response
    %     rsp_err: optional string which will cause error if present in response
    % uses:
    %     me.cmd_timo_ms
    %     me.cmd_nchar
    % returns:
    %     err: 0=ok, 1=missing rsp_need, 2=has rsp_err, 3=missing '>'
    %     rsp: response as a string
      if (0)
        fprintf('DBG %s: ser_class.do_cmd(', me.dbg_alias);
        nc.uio.print_all(cmd);
        fprintf(')\n');
      end
      if (length(me.bridge_objs)>0)
        set_last_bridge_term(me, '>');
      end
      me.private_start_cmd(cmd);
      if (nargin<3)
        [rsp, err] = me.get_cmd_rsp(cmd);
      elseif (nargin<4)
        [rsp, err] = me.get_cmd_rsp(cmd, rsp_need);
      else
        [rsp, err] = me.get_cmd_rsp(cmd, rsp_need, rsp_err);
      end
    end



    function [rsp, err, errmsg] = get_cmd_rsp(me, cmd, rsp_need, rsp_err)
    % desc: reads response until
    %       terminating character '>' is received.  Strips all echos.
    % inputs:
    %     me: this ser_class object
    %     cmd: string sent to that port. used for dbg messages only
    %     rsp_need: optional string which is required in the response
    %     rsp_err: optional string which will cause error if present in response
    % uses:
    %     me.cmd_timo_ms
    %     me.cmd_nchar
    % returns:
    %     err: 0=ok, 1=missing rsp_need, 2=missing rsp_err, 3=missing '>'
    %     rsp: response as a string
      import nc.*                                   
     
      err=0;
      errmsg='';

      [rsp , ~, to] = me.read(me.cmd_nchar, me.cmd_timo_ms, me.cmd_term_char);
      
      if (logical(to))
        if (logical(me.dbg))
          fprintf('WARN: ser_class.get_cmd_rsp() timo (after %g ms) on port %s\n', ...
                   me.cmd_timo_ms, me.dbg_alias);
          fprintf('     cmd was: ');
          uio.print_all(cmd);
          fprintf('     in rsp: ');
          uio.print_all(rsp);
        end
        err=3;
      end


      for k=1:length(me.bridge_objs)
        rsp = me.bridge_objs(k).bridge_rsp(me.bridge_chans(k), rsp);
      end

      if (me.cmd_strip_echo && ~isempty(cmd))
        % might be mt string if a continuation of reading from remote rcs
        % in which case dont strip any lines.
        % I used to verify echo, but no more
        
        idx=strfind(rsp, char(10));
        if (~isempty(idx))
%        if (me.dbg)
          % if (cmd(end)==char(13)) % local cmd might have cr, so strip it
          %  cmd=cmd(1:end-1);
          % end
          % fprintf('DBG lcl echo:');
          % nc.uio.print_all(rsp(1:idx(1)));
          % fprintf('is cmd %d\n', strcmp(cmd, rsp(1:idx(1)-1)));
%        end
          rsp=rsp(idx(1)+1:end);
        end
      end

      if (~err)
        err = ~isempty(errmsg);
      end
      
      if ((nargin>2)&&~isempty(rsp_need))
        if (isempty(strfind(rsp, rsp_need)))
          fprintf('ERR: ser_class detects missing ')
          uio.print_all(rsp_need);
          fprintf('\n     in rsp ');
          uio.print_all(rsp);
          fprintf('\n');
          err=1;
        end
      end
      if ((nargin>3)&&~isempty(rsp_err))
        if (~isempty(strfind(rsp, rsp_err)))
          fprintf('ERR: ser_class found %s\n', rsp_err);
          fprintf('     in rsp ');
          uio.print_all(rsp);
          fprintf('\n');
          err=2;
        end
      end
    end

    function [m, err] = do_cmd_get_matrix(me, cmd, dflt)
      % inputs:
      %   dflt: default value if could not parse a matrix
      [rsp, err] = do_cmd(me, cmd);
      m=me.parse_matrix(rsp);
      if (nargin>2)
        if (any(size(m)~=size(dflt)))
          m=dflt;
          err=1;
        end
      end
    end
    
  end
  
end
