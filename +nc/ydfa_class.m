classdef ydfa_class < handle
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

    function idn = get_idn_rsp(ser,dbg)
% Sets:
%   idn.name
%   idn.model
%   idn.sn
%   idn.pwr_rating (30=one watt, 20=20dBm , 18=18dBm, 0=unknown) based on model name
      if (nargin<2) dbg=0; end	     
      ser.set_cmd_params(1000, 200);
      ser.write(['READ' char(13) char(10)]);
%
% Never got any rsp from YDFA-20B-B or YDFA-30B-B
%

% The YDFA-18 needs an entire command line sent to it within a short period of time.
% If you try typing it into teraterm, thats too slow.  You can use the teraterm
% Paste<CR> to paste a buffer followed by a CR, and use transmit option CR+LF.

%  Expected response of YDFA-18
% 
%    Optilab,LLC
%    Model Type:YDFA-18-R
%    SN: 9077108
%    Version:V2.0.0
%    Input:Low
%    Output:Low
%
      to=0;
      li=1;
      idn.name='';
      idn.model='';
      idn.sn='';
      idn.pwr_rating_dBm = 0; 
      while(~to)
	[rsp, fk, to] = ser.read(1000, 200, char(10));
	if (isempty(rsp) || to) break; end
	if (dbg)
	  fprintf("L%d: ", li);
	  nc.uio.print_all(rsp);
        end
	li=li+1;
	if (regexp(rsp, 'optilab','ignorecase')) % models have inconsisent case
	  idn.name = 'ydfa';
        elseif (regexp(rsp, '^Model'))
	  idn.model = nc.ydfa_class.after_colon(rsp);
	  % power rating is after the dash
	  n = sscanf(regexprep(idn.model,'^[^-]*-',''),'%d');
	  if (~isempty(n)) idn.pwr_rating_dBm = n(1); end
        elseif (regexp(rsp, '^Serial')) % for: ydfa-30-r 
	  idn.sn = nc.ydfa_class.after_colon(rsp);
        elseif (regexp(rsp, '^SN')) % for: ydfa-18 r
	  idn.sn = nc.ydfa_class.after_colon(rsp);
	elseif (regexp(rsp,'Output'))
	  break; % stop reading lines from port
        end
      end
      ser.set_cmd_params(1000, 500);
    end


    % stupid parsing routines
    function s = after_colon(str)
      s = regexprep(regexprep(str,'^.*: *',''),' *\r?\n?','');
    end

    function n = n_after_colon(str, default)
      if (nargin>1) n=default; else n=0; end
      [v vc]=sscanf(nc.ydfa_class.after_colon(str),'%g');
      if (vc) n=v(1); end
    end

    function v = parse_current_indic(str)
      if (regexp(str,'LOW','ignorecase'))
	v=-100;
      else
	v=sscanf(str,'%g');
	if (isempty(v))
          v=1000; % deliberately ridiculous
        else
          v=v(1);
        end
      end
    end

  end

  methods % instance methods

    % CONSTRUCTOR
    function me = ydfa_class(port, opt)
    % desc: constructor
      if (nargin<2)
	opt.dbg=0;
      end
      me.dbg=opt.dbg;
      opt=nc.util.set_field_if_undef(opt,'baud',9600);
      me.ser = nc.ser_class('', opt.baud, opt);
      me.open(port);
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

    function open(me, port, baud)
      import nc.*
      if (nargin<2)
        port='';
      end
      if (nargin<3)
        baud=9600;
      end
      if (isempty(me.ser))
        me.ser = ser_class(port, baud);
      else
        if (me.ser.isopen())
          fprintf('WARN: ydfa_class.open(): already open\n');
	  return;
        end
        me.ser.open(port, baud);
      end
      if (~me.ser.isopen())
        return;
      end

      me.idn = me.get_idn_rsp(me.ser);
      me.get_settings();

    end

    function status = get_status(me)
% status.in_pwr_dBm  = input optical pwr
% status.out_pwr_dBm = output optical pwr 
fprintf('DBG YDFA: get status()\n');
      status.in_pwr_dBm=9999;
      status.out_pwr_dBm=9999;
      me.ser.write(['READ' char(13) char(10)]);      
      to=0;
      li=1;
      while(~to)
	[rsp, fk, to] = me.ser.read(1000, 200, char(10));
	if (isempty(rsp) || to) break; end
	if (regexp(rsp, 'input','ignorecase')) % models have inconsisent case
	  str = me.after_colon(rsp);
          status.in_pwr_dBm=me.parse_current_indic(str);
        elseif (regexp(rsp, 'output','ignorecase')) % models have inconsisent case
	  str = me.after_colon(rsp);
          status.out_pwr_dBm=me.parse_current_indic(str);
	  break;
        end
      end
%      me.ser.write(['SENS:CUR:CH1?' char(13) char(10)]);
%      while(~to)
%	[rsp, fk, to] = me.ser.read(1000, 200, char(10));
%	if (isempty(rsp) || to) break; end
%      end
    end

    function get_settings(me)
fprintf('DBG YDFA: get settings()\n');
      if (me.idn.pwr_rating_dBm==18)
	me.ser.write(['READC' char(13) char(10)]);
%  Expected response of YDFA-18
% 
%    the Current:100
      else
	me.ser.write(['READ' char(13) char(10)]);
      end
      me.settings.pump_cur_ma=[];
      li=1;
      while(1)
	[rsp, fk, to] = me.ser.read(1000, 200, char(10));
	if (isempty(rsp) || to) break; end
	if (me.dbg)
	  nc.uio.print_all(rsp);
        end
	li=li+1;
	if (me.idn.pwr_rating_dBm==30)
          if (regexp(rsp, 'Pump'))
            [chan nc] = sscanf(rsp(5:end),'%d');
	    if (nc>0)
              chan = chan(1);
	      if (regexp(rsp, 'Current'))
		me.settings.pump_cur_ma(chan)=me.n_after_colon(rsp);
              elseif (regexp(rsp, 'Limit'))
		me.settings.pump_limit_ma(chan)=me.n_after_colon(rsp);
              end
            end
          end
        elseif (me.idn.pwr_rating_dBm==18)
          if (regexp(rsp, 'Current'))
	    me.settings.pump_cur_ma=me.n_after_colon(rsp);
	    break;
          end
        end 
	if (regexp(rsp,'Output'))
	  break; % stop reading lines from port
        end
      end
    end

    function set_current_mA(me, ampsel, mA)
    % desc: sets curerent of specified amplifier.
    %       Some YDFAs feature up to three cascaded amplifiers,
    %       each with an independently settable current.
    % inputs: ampsel: 1..3
    %         mA : current settinf in milliamps
      mA=round(mA);
      if (me.idn.pwr_rating_dBm==18)
	if (ampsel~=1)
	  error('ydfa.set_current_ma: ampsel out of range');
	end
	cmd=sprintf('SETC:%03d\r\n', mA);
      elseif (me.idn.pwr_rating_dBm==30)
	if ((ampsel<0)||(ampsel>3))
	  error('ydfa.set_current_ma: ampsel out of range');
	end
	cmd=sprintf('SETLD%d:%04d\r\n', ampsel, mA);
	% response is: "<13><10>Successful"  with no cr after that!
      else
        fprintf('ERR: ydfa has unknown power rating\n');
	return;
      end
      me.ser.write(cmd);
      while(1)
	[rsp, fk, to] = me.ser.read(1000, 200, char(10));
	if (isempty(rsp) || to) break; end
	if (me.dbg)
	  nc.uio.print_all(rsp);
        end
        if (regexp(rsp, 'Successful', 'ignorecase'))
	  % Note: the ydfa-30 actually sets current to something
	  % approximately close, but not exactly.
	  me.settings.pump_cur_ma(ampsel)=mA;
	  % TODO: out to read settings now.
	  break;
        end
      end
    end

  end % block

end
