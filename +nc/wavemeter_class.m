classdef wavemeter_class < handle

% TIPS:
%  must set communication mode on burleigh to GPIB
%  and use GPIB addr 20.
%  Remote=off is ok and maybe best.
%  get_wavelen only works when burleigh "monitor mode"
%     has blue region surrounding data.
%     But you can switch to spectrum mode while using this API.
%  burleigh is case insensitive.
%
%  sometimes after hooking it up I have a hard time getting it to respond,
%  but then after that it will work.
%  maybe after hookup, quit all teraterm and restart matlab,
%  maybe there is some funny thing about ports.

% *RST changes pwr units to uW, sets wavelen range to 1520-1625 
% Burleigh has many more commands than just those in the manual. do:
%      SYST:HELP:HEAD?

% USES
%   uio  

  properties (Constant=true)
    RANGES=[1270 1680 % 0
            1270 1475
            1450 1680
            1270 1355
            1350 1445
            1435 1535
            1520 1625];
  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug cpds reads
    ser_obj
    is_open
    idn_rsp
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function rsp = prologix_cmd(ser_obj, cmd)
      % fprintf('DBG: %s\n', cmd);
      fprintf(ser_obj, cmd);
      for k=1:3
        rsp = fgetl(ser_obj);
        if (~isempty(rsp))
	  return;
        end
	fprintf('DBG: timo waiting for prologix rsp\n');
	fprintf(ser_obj, ['++read eoi' char(10)]);
      end
      rsp='';
      fprintf('ERR wavemeter: gave up waiting for prologix rsp\n');
    end      

    function rsp = get_idn_rsp(ser_obj)
      fprintf(ser_obj, ['*IDN?' char(10)]);
      rsp = fgetl(ser_obj);
      if (isempty(rsp))
        fprintf('ERR: wavemeter_class.get_idn_rsp no response from wavemeter\n');
        fprintf('     Did you set its System/Communication to GPIB addr 20,\n');
        fprintf('     then change back to Spectrum mode? (you MUST change back)\n');
        nc.uio.pause();
	fprintf('Trying again...\n');
        fprintf(ser_obj, ['*IDN?' char(10)]);
        % Note: burleigh is case insensitive. (*idn? works too!)
        rsp = fgetl(ser_obj);
        if (isempty(rsp))
          fprintf('ERR: wavemeter_class.get_idn_rsp: still no response.  Giving up!\n');
        end
      end
    end



  end


  methods

    function me = wavemeter_class(port)
    % desc: constructor
      me.idn_rsp = '';
      me.ser_obj = serial(port);
      set(me.ser_obj,'Timeout',1) % in units of seconds
      % burleigh can return a lot of chars in rsp to the xxx command
      % by default, buffer is only 512 bytes
      me.ser_obj.InputBufferSize = 2048; % must be done before it's open
      ok=0;
      me.is_open=0;
      try
	fprintf('DBG: wavemeter: will do fopen. Why does this take so long?\n');
	tic
	fopen(me.ser_obj);
	toc
	ok = strcmp(me.ser_obj.Status,'open');
	me.is_open = ok;
      catch
      end
      if (~ok)
	fprintf('\nERR wavemeter: cant open port %s\n', port);
      else
        fprintf(me.ser_obj, ['++addr 20' char(10)]);
        fprintf(me.ser_obj, ['++addr' char(10)]);
        ad = fgetl(me.ser_obj);
        if (~strcmp(ad(1:end-1),'20')) % ends with CR (char 13)
 	  fprintf('WARN: Bad response from Prologix dongle\n');
	  ok=0;
	else
	  % set timeout of the Prologix dongle to the max possible (3 sec)
          fprintf(me.ser_obj, ['++read_tmo_ms 3000' char(10)]); % the max

	  % burleigh s: uses char 10 at end of responses

	  % burleigh recommends that "ctlr" (prologix) assert eoi with last char
          fprintf(me.ser_obj, ['++eoi 1' char(10)]); %

	  % When prologix fowards a line to the gpib device, it appends:
          %   eos 0 = append CR+LF to intrument cmds
          %   eos 1 = append CR=char(13) to intrument cmds
          %   eos 2 = append LF=char(10) to intrument cmds
	  %   eos 3 = dont' append anything. device relies on signal.
          fprintf(me.ser_obj, ['++eos 2' char(10)]);



	  % When prologix gets a line from the gpib device,
          % if it detects eoi signal, it appends to the line:
          %   ++eot_enable 0 = dont append anything
          %   ++eot_enable 1 = append EOT char
          % the EOT char is user-defined, not part of GPIB std,
          % used only for device->host direction.
          %
	  % burleigh wavemeter terminates all its messages with eos,
	  % which appears to be char(10).  So no further appending is needed
          fprintf(me.ser_obj, ['++eot_enable 0' char(10)]);
          fprintf(me.ser_obj, ['++eot_char 10' char(10)]);

          set(me.ser_obj,'Timeout',4) % 4 sec. no sense waiting longer

 	  me.idn_rsp = nc.wavemeter_class.get_idn_rsp(me.ser_obj);


          fprintf(me.ser_obj, ['DISP:UNIT:POW DBM' char(10)]);
          fprintf(me.ser_obj, ['DISP:UNIT:WAV NAN' char(10)]);

	end
      end
    end

    function delete(me)
      me.close;
      delete(me.ser_obj);
    end

    function close(me)
      if (strcmp(me.ser_obj.Status,'open'))
        fclose(me.ser_obj);
      end
    end      
    
    function pwr_dbm = meas_pwr_dbm(me)
      rsp = wavemeter_class.prologix_cmd(me.ser_obj, ...
	    [':meas:scal:pow?' char(10)]);
%      rsp = fgetl(me.ser_obj);
      [pwr_dbm cnt]=sscanf(rsp,'%f');
      if (cnt~=1)
	fprintf('ERR wavemeter: wavemeter gave bad rsp to pow cmd: %s\n', rsp);
      end
    end
    
    function wl_m = meas_wavelen_m(me)
    % desc: returns wavelen in nm with 8 digits of precision
%      fprintf(me.ser_obj, [':MEAS:SCAL:WAV?' char(10)]); % returns nm
%      fprintf(me.ser_obj, [':CALC3:WAV:DATA? CUR' char(10)]); % returns nm
    % only works when burleigh "monitor mode" has blue region surrounding data
      rsp = wavemeter_class.prologix_cmd(me.ser_obj, [':CALC3:WAV:DATA? CURR' char(10)]);
%      rsp = fgetl(me.ser_obj);
      [wl_m cnt]=sscanf(rsp,'%f');
      if (cnt~=1)
	fprintf('ERR wavemeter: wavemeter gave bad rsp to wav cmd: %s\n', rsp);
      end
      wl_m = wl_m*1e-9;
    end

    function [wl_m pwr_dbm] = meas_wl_and_pwr(me)
 % desc:
 %   measures wavelen and power for multiple "channels"
 %   returns wavelen (in meters) and power (in dBm) of *strongest* channel
 %   If no channel is above the threshold, prompts user to adjust threshhold
 % returns:
 %   wl_m - wavelength in meters
 %   pwr_dbm - power in dBm
      nch=0;
      import nc.*
      while (nch~=1)
        arr=me.meas_wpo;
        nch = size(arr,1);
        if (nch>0)
          break;
        end
        fprintf('WARN: wavemeter sees %d channels\n', nch);
        if (nch==0)
          fprintf('    maybe there is no optical power?\n');
        end
        fprintf('    maybe you must adjust "CH threshold"\n');
        if (~uio.ask_yn(1))
	  break;
        end
      end
      wl_nm=0;
      pwr_dbm=-1000;
      if (nch>=1)
        pwrs_dbm = arr(:,2);
        idx=find(pwrs_dbm==max(pwrs_dbm),1);
        wl_m   = arr(idx,1)*1e-9;
        pwr_dbm = arr(idx,2);
      end
    end
    
    function arr = meas_wpo(me)
      me.meas_wpo_req;
      arr=me.meas_wpo_rsp(1);
    end
    
    function meas_wpo_req(me)
% split req and rsp because wavemeter can take a few seconds!
      fprintf(me.ser_obj, [':meas:arr:wpo?' char(10)]);
    end

    function arr = meas_wpo_rsp(me, autoretry)
 % desc:
 %   measures wavelen, power, and optical SNR for multiple "channels"
 %   returns nx3 array.  if empty, you must set threshold
 %   each row is : wl_nm pwr_dbm  snr_db
 %   NOTE: channels are not sorted by power!
      import nc.*	     
      wtcnt=0;
      if (nargin<2)
        autoretry=0;
      end
      while(1)
	[rsp ct msg] = fgetl(me.ser_obj);
		     % Burleigh uses a coma to separate numeric values
	sa = regexp(rsp, '[^,]+', 'match');
	sa_l = length(sa);
	err=0;
	arr=[];
	if (sa_l<1)
          err=1;
	else
          [n cnt] = sscanf(sa{1},'%f');
	  arr = zeros(n,3);
	  k=2;
          for r=1:n
	    for c=1:3
	      if (k>sa_l)
		err = 1;
		break;
	      end
              [v cnt] = sscanf(sa{k},'%f');
	      if (cnt==1)
		arr(r,c)=v;
	      else
		err=1;
	      end
	      k = k+1;
            end
          end
	end
	if (~err)
          return;
	end
	if (isempty(rsp) && (wtcnt<3))
          ba = me.ser_obj.BytesAvailable;
          fprintf('DBG wavemeter: bytes avail is now: %d\n', ba);
          fprintf('DBG wavemeter: waiting longer\n');
	  % pause(1);
	  wtcnt=wtcnt+1;
	else
          fprintf('ERR wavemeter: bad rsp to WPO cmd: ');
          uio.print_all(rsp);
          fprintf('  errmsg: %s\n', msg);
          ba = me.ser_obj.BytesAvailable;
          fprintf('bytes avail is now: %d\n', ba);
          doretry=autoretry;
         
          if (~autoretry)       
  	    fprintf('re-issue req and retry?')
            doretry = uio.ask_yn(1);
          end
          if (doretry)
            if (ba)
    	      junk = fread(me.ser_obj); 
            end
            me.meas_wpo_req;
          else
            fprintf('give up and return nothing?');
            if (uio.ask_yn(1))
              return;
            end
          end
        end
      end
    end

    function err = set_wl_range(me, range_nm)
    % desc: sets wavemeter to show specified range 
    %       using the range setting that provides best resolution
    % inputs: range_nm: specifies wavelength(s) (in nm) being used.
    %               either a single wl or a [min  max] vector.
    % warn: slow because it causes a "recalibration"
      cur=-1;

      fprintf(me.ser_obj, [':sens:rang?' char(10)]);
      rsp = fgetl(me.ser_obj);
      [v cnt] = sscanf(rsp,'%d');
      if (cnt==1)
	cur=v;
      else
	fprintf('ERR wavemeter: bad rsp to range querry: %s\n', rsp);
      end
      rr=wavemeter_class.RANGES;
      n = size(rr,1);
      for k=n:-1:1
        r = rr(k, :);
        if ((r(1)<=min(range_nm)) && (r(2)>=max(range_nm)))
	  if ((k-1)~=cur)
  	    fprintf(me.ser_obj, [sprintf(':sens:rang %d\n', k-1)]);
	  end
          break;
        end
      end
      err=1; % supplied range is invalid
    end

    function f_hz = meas_freq_hz(me)
    % desc: returns freq in Hz with 8 digits of precision
    % only works when burleigh "monitor mode" has blue region surrounding data
      f_hz=0;
      for k=1:3
        %rsp = wavemeter_class.prologix_cmd(me.ser_obj, [':MEAS:SCAL:FREQ?' char(10)]);
        rsp = wavemeter_class.prologix_cmd(me.ser_obj, [':CALC3:WAV:DATA? CURR' char(10)]);
        if (~isempty(rsp))
          break;
        end
	fprintf('ERR wavemeter: retry FREQ cmd\n');
      end
      if (isempty(rsp))
	fprintf('ERR wavemeter: giving up on wavemeter\n');
        return;
      end		

      [f_hz cnt]=sscanf(rsp,'%f');
      f_hz = f_hz*1e12; % FREQ? returns THz
      if (cnt~=1)
	fprintf('ERR wavemeter: bad rsp to freq cmd: %s\n', rsp);
        f_hz=0;
      end
    end
    
  end
  
end
