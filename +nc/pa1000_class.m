% pa1000_class

% class ("static") functions
%   pa1000_class.parse_idn(idn)
%
% member variables (read only "properties")
%   pa.devinfo: structure of device specifications & supported features
%     devinfo.num_chan: int: number of channels (FPCs) in chassis
%     devinfo.num_wp:   int: number of waveplates per channel (all chans have same amt)
%     devinfo.pol_type: char: polarization type: l (linear) p (polarization beam splitter) n (no polarizer)
%
%   pa.settings: structure of current device settings
%     settings.wavelen_nm(chan) - current wavlengths in nm, per channel
%     settings.waveplates_deg(chan, 1..6) - current waveplate settings in deg


%
% some member functions
%   pa=pa1000_class(port) CONSTRUCTOR. calls open, then get_settings.
%   pa.close              you may close and then re-open
%   pa.open(port)         if port absent, uses prior port
%   b=pa.isopen           returns logical
%   pa.get_settings       call, then access pa.settings structure
%   pa.set_wavelen_nm(chan, wl_nm)   wavelens limited in device-specific manner
%                                 check pa.settings.waveplates_deg afterwards.
%   pa.set_waveplates_deg(chan, wp, degs)  degs are limited in device-specific manner
%   pa.zero_waveplates_of_pc(chan)
%   pa.set_tomo_state(chan, st)
%   [err msg] = pa.get_cal(me)    fills in pa.cal and set pa.cal_ok


% in general:
%   set_* - change a setting on device
%   meas_* - measure something using device
%   cal_* - function intended for calibration only, not for general use


% Types of errors, and how handled:
%   bugs: misuse of this api.  Bug in the caller, so fix it.
%     causes a matlab crash and stack trace printout
%   communication error:
%     a windows com error could mean serial port yanked out.
%
%   garbled response:
%     could be a com error such as loss of chars due to buffer overrflow.
% 
%   operations on closed ports:
%     These routines continue silently.
%     Allows calling code to pretend as if the pa is connected, which
%     is useful for partial-system testing  if pa1000 is absent.

classdef pa1000_class < nc.ncdev_class

  properties
%    dbg  % 0=none, 1=debug io
    port
    ser
    idn
    devinfo
%     devinfo.num_chan: number of channels (FPCs) in chassis
%     devinfo.num_wp:   number of waveplates per channel (all chans have same amt)
%     devinfo.pol_type: polarization type: l p or n    
%     devinfo.supports_flash_write
%     devinfo.can_meas_sings
%     devinfo.fsamp_MHz
%     devinfo.max_measlen_ms
    settings
%     settings.wavelen_nm(chan) - current wavlenths in nm
%     settings.waveplates_deg(chan, 1..6) - current waveplate settings in deg
%     settings.int_align_deg - 1x3 matrix of settings for wp 4..6. wl dependent.
    cal
%     cal.wp_axes    
    cal_ok
    dbg_cal
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function str = chan_idx2str(idx)
    % idx: channel index base 1, which is the matlab "way".
      % inputs: ch_i: one-based channel index
      % output: str: string name of channel.  Pa's channels are named "A" and "B".
      names='ab';
      str = names(max(min(idx,2),1));
    end
    
    function str = channame_idx2str(ch_i)
      % inputs: ch_i: one-based channel index
      % output: str: string name of channel.  Pa's channels are named "A" and "B".
      % DEPRECATED
      error('WARN: DEPRECATED use of channame_idx2str(ch_i); use chan_idx2str(idx)\n');
      % return pa1000_class.chan_idx2str(ch_i);
    end

    % static
    function devinfo = parse_idn(idn)
% always sets:
%      devinfo.num_wp  : 4 or 6
%      devinfo.num_chan: 1 or 2
%      devinfo.pol_type: l p n
      if (~isstruct(idn))
        error('idn must be a structure');
      end
      
      % import nc.*
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      model=0;
      if (num_flds>=2)
        model = parse_word(flds{2}, '%d', model);
      end
      
      % default PA
%      devinfo.sn = '?';
      devinfo = idn;
      devinfo.num_wp  = 4;
      devinfo.num_chan = 1;
      devinfo.pol_type = 'l';
      devinfo.supports_flash_write = nc.util.ver_is_gte(devinfo.fwver, [3 0 0]);
      devinfo.has_t_cmd   = nc.util.ver_is_gte(devinfo.fwver, [5 0 0]); % t = tomo for gui
      devinfo.has_ver_cmd = nc.util.ver_is_gte(devinfo.fwver, [6 0 0]);

      for_fwver = [6 1 1];
      if (nc.util.ver_is_gt(devinfo.fwver, for_fwver))
        fprintf('WARN: pa1000_class(): This software was written for PA firmwares %s and below\n', nc.util.ver_vect2str(for_fwver));
        fprintf('      but PA has firmware %s and might not work with this +nc package\n', ...
                nc.util.ver_vect2str(devinfo.fwver));
      end
      
      % C1
      k=3;
      if(k>num_flds)
	return;
      end
      devinfo.num_chan = parse_word(flds{k}, '%d', devinfo.num_chan);
      k = k + 1;
      if(k>num_flds)
        return;
      end

      % C2
      devinfo.num_wp = parse_word(flds{k}, '%d', devinfo.num_wp);
      k = k + 1;
      if(k>num_flds)
        return;
      end

      % C3
      devinfo.pol_type = lower(flds{k}(1));
      k = k + 1;
      if (strcmpi(idn.sn,'014'))
	% work-around for C code bug in first EPGMS system,
	% in which the PA falsely claims to have a beam cube (p) polarizer
	devinfo.pol_type = 'n';
      end

      % C4
      k = k + 1; % (C4 not used)

      % nested
      function v=parse_word(str, fmt, default)
	[v ct]=sscanf(str, fmt, 1);
	if (~ct)
          v = default;
	end
      end
      
    end


    % static
    function [err msg_rsp cal] = parse_printcal_rsp(devinfo, rsp, dbg)
    % inputs:
    %    devinfo: device's info from info cmd
    %    rsp: string. PA's response to a "print calibration" command
    %    dbg: 0|1. whether to print debug messages
    % returns:
    %    err: 0=ok, 1= problem parsing rsp
    %    msg_rsp : cell array of user feedback strings
    %    cal: pa calibrtaion structure
      msg_rsp={};
      err=0;
      calfile='?';
      if (dbg)
        'DBG parse_printcal_rsp'
	length(rsp)
        rsp
      end
      wp_axes = zeros(devinfo.num_chan*3,devinfo.num_wp);
      iv = zeros(devinfo.num_chan,3);
      int_align = zeros(devinfo.num_chan,3);
      dac2ph_coef=[];  
      pc_wavelens{1}=[];
      pc_wavelens{2}=[];

      
      idx = strfind(rsp,'=')+1;
      idx_l = length(idx);
      if (isempty(idx))
	err=1;
	addmsg(sprintf('WARN: PA did not responded with any calibration info\n'));
	fprintf('WARN: bad calibration.  rsp is: ');
	nc.uio.print_all(rsp);
      else
	cfg_fmt = sscanf(rsp(idx(1):end),'%d',1);
      	if (isempty(cfg_fmt))
	  err=1;
	  addmsg(sprintf('WARN: PA did not responded with any cfg format\n'));
	elseif (cfg_fmt==1)
	  k=7; % skip
	  for pc=1:devinfo.num_chan
            check_rsp(rsp, idx, k, 'axis');
            for wp=1:devinfo.num_wp
              for dim=1:3
		if (k<=idx_l)
		  wp_axes((pc-1)*3+dim,wp)=sscanf(rsp(idx(k):end),'%g',1);
		  k=k+1;
		else
		  err=1;
		end
              end
            end

            k=k+3*6; % skip tomo states

            if (0) % read tomo states
              if (devinfo.num_wp>=6)
		for dim=1:3
		  if (k<=length(idx))
                    iv(pc,dim)=sscanf(rsp(idx(k):end),'%g',1);
                    k=k+1;
		  else
                    err=1;
		  end
		end
		for wp=1:2
		  if (k<=length(idx))
                    int_align(pc,wp)=sscanf(rsp(idx(k):end),'%g',1);
                    k=k+1;
		  else
                    addmsg('ERR: insufficient calibration query rsp from PA');
                    err=1;
                    break;
		  end
		end
              end
            end % if 0

	  end % for pc

	  check_rsp(rsp, idx, k, 'num');


	  num_wl=sscanf(rsp(idx(k):end),'%g',1); k=k+1;

	  devinfo.num_wl=num_wl;
	  wavelens=zeros(1,num_wl);
	  dac2ph_coef=zeros(num_wl*devinfo.num_chan*2,devinfo.num_wp);
	  for pc=1:devinfo.num_chan
            for wl=1:num_wl
              d=sscanf(rsp(idx(k):end),'%g',1);
              k=k+1;
              if (pc==1)
		wavelens(wl)=d;
              else
		if (wavelens(wl)~=d)
		  fprintf('ERR: device calibrated with different set of wavelengths for each channel\n');
		end
              end
              check_rsp(rsp, idx, k, 'coef');
              for wp=1:devinfo.num_wp
		for ab=0:1
		  % n=sscanf(rsp(idx(k):end),'%g',1);
		  n=get_rsp_n(rsp, idx, k);
                  k=k+1;
                  if (dbg)
		    fprintf('[%d,%d]=%g\n', 2*devinfo.num_chan*(wl-1)+2*pc+ab+1, wp, n);
                  end
		  dac2ph_coef(2*devinfo.num_chan*(wl-1)+2*(pc-1)+ab+1,wp)=n;
		end
              end
              % new as of 12/15/14
              if (devinfo.num_wp>=6)
		check_rsp(rsp, idx, k, 'int');
		for wp=1:3
                  if (k<=length(idx))
                    int_align(pc,wp)=sscanf(rsp(idx(k):end),'%g',1);
                    k=k+1;
                  else
                    addmsg('ERR: insufficient calibration query rsp from PA');
                    err=1;
                    break;
                  end
		end
              end

            end % for wl
            pc_wavelens{pc}=wavelens;
	  end % for pc

	elseif ((cfg_fmt>=2)&&(cfg_fmt<=6))
	  if ((cfg_fmt==3)||(cfg_fmt>=5))
            calfile = get_rsp_str(rsp, idx, 2);
	  end
	  if (cfg_fmt==4) % DFPG only
	    cal.samp_pd_us = get_rsp_n(rsp, idx, 5);
          end
	  k=7 + (cfg_fmt==3)+(cfg_fmt>=4); % skip
          if (dbg)
            'first k'
            k
          end
	  % int_align will grow to a height of max(num_w1,num_w2)*num_chan.
	  for pc=1:devinfo.num_chan

            % New as of cfg_format 6
            if (~test_rsp(rsp, idx, k, 'temp_c'))
              pc_temps_C(pc) = get_rsp_n(rsp, idx, k);
              k=k+1;
            end
            
            check_rsp(rsp, idx, k, 'axis');
            if (dbg)
              dbg_print(rsp, idx, k, 'axis');
            end
            for wp=1:devinfo.num_wp
              for dim=1:3
                if (dbg)
                  dbg_print(rsp, idx, k, 'axis');
                end
		wp_axes((pc-1)*3+dim,wp) = get_rsp_n(rsp, idx, k);
		k=k+1;
              end
            end
            k=k+3*6; % skip tomo states
	    if (~test_rsp(rsp,idx,k, 'iv'))
              for dim=1:3
		iv(pc,dim) = get_rsp_n(rsp, idx, k);
		k=k+1;
              end
            end
	  end
	  %        dac2ph_coef=zeros(num_wl*devinfo.num_chan*2,devinfo.num_wp);
	  dac2ph_coef=[];
	  for pc=1:devinfo.num_chan

            check_rsp(rsp, idx, k, 'num');
            num_wl = get_rsp_n(rsp, idx, k);
            if (dbg)
              dbg_print(rsp, idx, k, 'num');
              fprintf('DBG: num_wl %d\n', num_wl);
            end
            k=k+1;

            
            wavelens=zeros(1,num_wl);
            for wl=1:num_wl
              if (k>length(idx))
		err=1;
		break;
              end
              wavelens(wl) = get_rsp_n(rsp, idx, k);
              if (dbg)
		fprintf('  -> wl %g\n', wavelens(wl));
              end
	      
              k=k+1;

              check_rsp(rsp, idx, k, 'coef');
              for wp=1:devinfo.num_wp
		for ab=0:1
		  n = get_rsp_n(rsp, idx, k);
		  k=k+1;
		  % fprintf('[%d,%d]=%g\n', 2*devinfo.num_chan*(wl-1)+2*pc+ab+1, wp, n);
		  dac2ph_coef(2*devinfo.num_chan*(wl-1)+2*(pc-1)+ab+1,wp)=n;
		end
              end
              if (devinfo.pol_type=='p')
		check_rsp(rsp, idx, k, 'int');
		% store matrix in same format as in .cal file
		r = devinfo.num_chan*(wl-1)+pc;
		for wp=1:3
		  int_align(r,wp) = get_rsp_n(rsp, idx, k);
		  k=k+1;
		end
              end
            end % for wl
            pc_wavelens{pc}=wavelens;
	  end % for pc
	  % dac2ph_coef

	else
	  err=1;
	  addmsg(sprintf('WARN: PA responded with unknown cfg format=%d', cfg_fmt));
	end
      end


      cal.calfile = strrep(calfile,char(13),'');
      cal.wp_axes = wp_axes;
      cal.int_align = int_align;
      cal.dac2ph_coef = dac2ph_coef;
      cal.iv = iv;
      cal.wavelens = []; % DEPRECATED
      cal.pc_wavelens = pc_wavelens;

      % nested function
      function addmsg(str)
	msg_rsp = [msg_rsp; str];
      end

      % nested function
      function rval = test_rsp(rsp, idxs, k, key)
	% looks for key in equality indexed by k
        % returns 0=ok, 1=not found
        if (k>length(idxs))
          rval=0;
          return;
        end
	i2=idxs(k);
	if (k==1)
	  i1=1;
	else
	  i1=idxs(k-1);
	end
	ss=rsp(i1:i2);
	rval = isempty(strfind(lower(ss), key));
      end

      % nested function
      function dbg_print(rsp, idxs, k, key)
	% returns 0=ok, 1=not found
	% prints kth assignment
        if (k>length(idxs))
          rval=0;
          return;
        end
	i2=idxs(k);
	if (k==1)
	  i1=1;
	else
	  i1=idxs(k-1);
	  iis=strfind(rsp(i1:i2),char(10))+i1-1;
	  if (~isempty(iis))
	    i1=iis(end)+1;
	  end
	end
	if (k==length(idxs))
	  i2=length(rsp);
	else
	  i2=idxs(k+1);
	  iis=strfind(rsp(i1:i2),char(10))+i1-1;
	  if (~isempty(iis))
	    i2=iis(1)-1;
	  end
	end
	ss=rsp(i1:i2);
        nc.uio.print_all(ss);
      end

      function rval = check_rsp(rsp, idx, k, key)
        rval=test_rsp(rsp, idx, k, key);
	if (rval)
          addmsg(sprintf('ERR: PA did not provide expected "%s" response\n', key));
	%	fprintf('     instead the rsp was:\n');
	%	nc.uio.print_all(ss);
	end
      end			       

      function str = get_rsp_str(rsp, idx, k)
	% parses a quoted string
	str='';
	if (k>length(idx))
	  n=0;
	  fprintf('ERR: PA did not provide enough rsp. k=%d, len(idx)=%d',k,length(idx));
	  return;
	end
	ii=idx(k);
	ee=ii;
	while( (ee<=length(rsp)) && (rsp(ee)~=char(10)))
	  ee=ee+1;
	end
	str = rsp(ii:ee-1);
      end

      function n = get_rsp_n(rsp, idx, k)
	if (k>length(idx))
	  n=0;
	  fprintf('ERR: PA did not provide enough numeric rsp\n');
	  return;
	end
	[n ok]=sscanf(rsp(idx(k):end),'%g',1);
	if (~ok)
	  fprintf('ERR: PA did not provide expected numeric response at line %d\n', k);
	  fprintf('     trying to parse: ');
	  nc.uio.print_all(rsp(idx(k):end));
	  n=0;
	else
	  n=n(1);
	% fprintf(' %g\n', n);
	end
      end

    end % parse_printcal_rsp
  
% what is this junk
%
%function rval = check_rsp(rsp, idxs, k, key)
%  if (k>length(idxs))
%    fprintf('ERR: device did not provide enough response\n');
%    rval=0;
%    return;
%  end
%  i2=idxs(k);
%  if (k==1)
%    i1=1;
%  else
%    i1=idxs(k-1);
%  end
%  ss=rsp(i1:i2);
%  rval = isempty(strfind(lower(ss), key));
%  if (rval)
%    fprintf('ERR: device did not provide expected "%s" response\n', key);
%    fprintf('     instead the rsp was:\n');
%    nc.uio.print_all(ss);
%  end
%end

    function cal = read_calfile(fname)
    % desc
    %   parses a pa calibration file, returns a structure
    % inputs
    %   fname : calibration file to read
    % returns
    %   cal : a structure containing calibration info
    
      % default calibration
      cal.int_align=[0 0; 0 0];
      cal.dac2ph_coef=[];
      cal.tomo_ph=zeros(6,3);
      cal.wavelens = []; % no longer used
      cal.pc_wavelens = {};
      cal.hw_ver_major=1;
      cal.hw_ver_minor=0;
      cal.samp_pd_us=1000; % what is this?
      cal.fname = nc.fileutils.rootname(fname);
      cal.no_wl_interp=0;
      cal.pc_type = 'b'; % default is BATI
    
      cal_f = fopen(fname, 'r');
      st=1;
      if (cal_f<=0)
        fprintf('ERR: read_cal(): cant open %s\n', fname);
      else
        while(1)
          [a ct]=fscanf(cal_f, '%[^\n\r]',256);
          if (ct<=0)
            if (st>1)
              handle_matrix(name, m);
              st=1;
            end
          else
            idx = strfind(a, '=');
            if (~isempty(idx) && (st==2))
              handle_matrix(name, m);
              st=1;
            end
            if (st==1)
              if (ct && (a(1)=='%'))
                [name ct] = sscanf(a(2:end), '%s', 1);
                if (~isempty(idx))
                  idx=idx(1)+1;
                  while((idx<=length(a)) && (a(idx)==' ')) idx=idx+1; end
                  val = a(idx:end);
                  handle_str(name, val);
                end
              elseif (ct && (a(1)~='%'))
                [name ct] = sscanf(a, '%s', 1);
                idx = strfind(a, '=');
                if (isempty(idx))
                  fprintf('ERR: missing =\n');
                else
                  idx2=strfind(a(idx+1:end),'[');
                  if (~isempty(idx2))
                    idx=idx+1+idx2-1;
                  end
                  [row cols]=sscanf(a(idx+1:end),'%f',inf);
                  m = row.';
                  st=2;
                end
              end
            else % st==2
              if (ct && (a(1)~='%'))
               [row ct]=sscanf(a,'%f',inf);
                if (~ct)
                  handle_matrix(name, m);
                  st=1;
                else
                  if (ct ~=cols)
                    fprintf('ERR: non-uniform matrix\n'); 
                  else
                    m = [m; row.'];
                  end
                end
              else
                handle_matrix(name, m);
                st=1;
              end
            end
          end
          [j ct_cr]=fscanf(cal_f, '%[\r]', 8); % skip
          [j ct_nl]=fscanf(cal_f, '%[\n]', 1);
          if (ct_nl<=0)
            break;
          end
    
        end % while(1)
        fclose(cal_f);
      end % if cal_f>0)

      cal.num_pc=size(cal.wp_axes,1)/3;
      cal.num_wp=zeros(1,cal.num_pc); % now per pc

      h=size(cal.dac2ph_coef,1);
      if (h/3==round(h/3))
        h=3;
      else
        h=2;
      end
      for pc=1:cal.num_pc
        m=any(cal.dac2ph_coef((pc-1)*h+(1:h),:)~=0);
        m=find(m==1,1,'last');
        if (isempty(m))
          m=0;
        end
        cal.num_wp(pc)=m;
      end
      
      size(cal.wp_axes,2);

      if (isempty(cal.pc_wavelens))
        for pc=1:cal.num_pc
          cal.pc_wavelens{pc}=cal.wavelens;
        end
      end
      cal.wavelens=[];
      
      if (~isfield(cal, 'pol_type'))
        fprintf('WARN: calibration file lacks pol_type.  Assuming L or P based on num_wp.\n');
        if (cal.num_wp==6)
         cal.pol_type = 'p';
        else
         cal.pol_type = 'l';
        end
      end
      % nested function
      function handle_matrix(name, m)
        if (strcmp(name,'iv'))
          cal.iv=m; % DEPRECATED
        elseif (strcmp(name,'hw_ver_major'))
          cal.hw_ver_major=m;
        elseif (strcmp(name,'hw_ver_minor'))
          cal.hw_ver_minor=m;
        elseif (strcmp(name,'int_align'))
          cal.int_align=m;
        elseif (strcmp(name,'wp_axes'))
          cal.wp_axes=m;
        elseif (strcmp(name,'dac2ph_coef'))
          cal.dac2ph_coef=m;
        elseif (strcmp(name,'wavelens'))
          cal.wavelens=m;
          cal.num_wl=length(cal.wavelens);
        elseif (strcmp(name,'wavelens1'))
          cal.pc_wavelens{1}=m;
        elseif (strcmp(name,'wavelens2'))
          cal.pc_wavelens{2}=m;
        elseif (strcmp(name,'tomo_ph'))
          cal.tomo_ph=m;
        elseif (strcmp(name,'dac_range'))
          cal.dac_range=m;
        end
      end
    
      % nested function
      function handle_str(name, val)
        if (strcmp(name,'date'))
          cal.date=val;
        elseif (strcmp(name,'src1'))
          cal.src1=val;
        elseif (strcmp(name,'sernum'))
          cal.sernum=val;
        elseif (strcmp(name,'pol_type'))
          cal.pol_type=val;
        elseif (strcmp(name,'pc_type'))
          cal.pc_type=val;
        elseif (strcmp(name,'temps_set_C'))
          cal.temps_set_C=sscanf(val,'%f',1);
          if (isempty(cal.temps_set_C))
            cal.temps_set_C=zeros(1,2);
          end
        elseif (strcmp(name,'no_wl_interp'))
          cal.no_wl_interp=val;
        end
      end
    
    end % function read_calfile
    
    
    
    

  end % static methods



  methods

    % CONSTRUCTOR
    function me = pa1000_class(arg1, opt)
    % desc: constructor
      import nc.*

%     me.idn = [];
      me.devinfo = [];
      me.cal_ok = 0;

      if (nargin<2)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'baud', 115200);
      opt = util.set_field_if_undef(opt, 'dbg_cal', 0);
%      me.dbg = opt.dbg;
      me.dbg_cal = opt.dbg_cal; % for Kieth
      
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
        me.idn = me.ser.idn;
        me.devinfo = me.parse_idn(me.ser.idn);
        me.set_nomenu(1);
        me.get_version_info();
        me.get_settings();
      elseif (ischar(arg1))
        me.ser = nc.ser_class(arg1, opt);
        me.open();
      else
        error('first param must be portname or ser_class');
      end
    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function close(me)
      if (me.isopen())
        %    me.set_nomenu(0);                  
        me.ser.close;
      end
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    function status = get_status(me)
      import nc.*
      status.pc_temps_C = zeros(1,me.devinfo.num_chan);
      status.pc_temps_alarm = zeros(1,me.devinfo.num_chan);
      status.fpga_temp_C = 0;
      if (nc.util.ver_is_gte(me.devinfo.fwver, [6 0 0]))
        rsp = me.ser.do_cmd('u');
        status.pc_temps_C(1) = me.ser.parse_keyword_val(rsp,'pc1_temp_C',0);
        status.pc_temps_alarm(1) = me.ser.parse_keyword_val(rsp,'pc1_temp_alarm',0);
        if (me.devinfo.num_chan>1);
          status.pc_temps_C(2) = me.ser.parse_keyword_val(rsp,'pc2_temp_C',0);
          status.pc_temps_alarm(2) = me.ser.parse_keyword_val(rsp,'pc2_temp_alarm',0);
        end
        status.fpga_temp_C = me.ser.parse_keyword_val(rsp,'fpga_temp_C',0);
      end
    end
    
    function f=isopen(me)
      f=me.ser.isopen;
    end

    function b=supports_flash_write(me)
      % DEPRECATED
      b = (me.devinfo.fwver(1)>=3);
    end


    function set_nomenu(me, nomenu)
    % desc: control over "nomenu mode", which decreases unnecessary IO between device and host
    %       by not printing the menus.
    % inputs: nomenu=0 turns off "nomenu mode".  nonmenu=1 turns on "nomenu mode".
      if (nc.util.ver_is_gte(me.devinfo.fwver, [5 0 3]))
        if (nomenu)
          me.ser.do_cmd('n'); % nomenus
        else
          me.ser.do_cmd('i'); % nomenus
        end
      end
    end


    function open(me, portname, opt);
    % desc: opens device, does 'i' command, fills in me.idn and me.devinfo.
    % baud: optional
      import nc.*
      if (nargin==1)
        portname='';
        opt.dbg = 0;
      elseif (nargin==2)
        if (isstruct(portname))
          opt = util.set_field_if_undef(portname, 'dbg', 0);
          portname=util.getfield_or_dflt(opt,'portname','');
        else
          opt.dbg=0;
        end
      end
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      end
      if (me.ser.isopen)
        idn = me.ser.get_idn_rsp; % identity structure
        me.idn = idn;
        me.devinfo = me.parse_idn(idn);
        me.set_nomenu(1);        
        me.get_version_info();
        me.ser.set_timo_ms(1000);
        me.get_settings();
      else
	if (me.ser.dbg)
	  fprintf('WARN: pa1000_class.open failed\n');
        end
      end
    end
      
    function get_version_info(me)
      if (me.devinfo.has_ver_cmd)
        me.ser.do_cmd('s');
        rsp = me.ser.do_cmd('v');
        me.devinfo.can_meas_sings = me.ser.parse_keyword_val(rsp,'can_meas_sings',0);
        me.devinfo.max_measlen_ms = me.ser.parse_keyword_val(rsp,'max_measlen_ms',0);
        me.devinfo.fsamp_MHz      = me.ser.parse_keyword_val(rsp,'fsamp_MHz',0); % typ 200
      else
        me.devinfo.can_meas_sings = 0;
        me.devinfo.max_measlen_ms = 0;
        me.devinfo.fsamp_MHz      = 0;
      end
    end                                        

    function [err msg] = get_settings(me)
    % desc: Querries device for its current settings.  Caller then accesses fields in the
    %       class instance member variable "settings".  The caller should not
    %       change any fields in "settings" directly.  But any function that changes
    %       any settings will update the "settings" structure.
    %       Note that the get_settings(me) is called every time the device is opened.
    % returns:
    %     msg: empty means no error.  Otherwise a string description of error
      import nc.*
      err=0;
      msg='';
      me.settings.waveplates_deg = zeros(me.devinfo.num_chan, me.devinfo.num_wp);

      rsp = me.ser.do_cmd('p'); % print current phase settings
      % fwver 5.0 response is:
      %   Waveplate Settings on Device 1.
      %   WP0 = 93
      %   WP1 = 0
      %    ...
      %   WP5 = 0
      %   Waveplate Settings on Device 2.
      %   WP0 = 0
      %    ...
      % then returns to main menu
      idx = strfind(rsp,'=')+1;
      k=1;
      for chan=1:me.devinfo.num_chan
	for wp=1:me.devinfo.num_wp
	  if (k>length(idx))
            err=1;
            msg = 'WARN: insufficient response from PA';
            break;
	  end
	  [n ct] = sscanf(rsp(idx(k):end), '%g', 1);
	  k=k+1;
	  if (ct==1)
            me.settings.waveplates_deg(chan, wp)=n;
	  else
            err=1;
            msg = 'WARN: malformed numeric response from PA';
	  end
	end
      end

      me.settings.wavelen_nm    = zeros(1,me.devinfo.num_chan);
      me.settings.wavelen_idxs  = ones(1,me.devinfo.num_chan);
      me.settings.wavelen2_idxs = ones(1,me.devinfo.num_chan);

      % older versions DO NOT REPORT WAVELEN!  
      if (nc.util.ver_is_gte(me.devinfo.fwver, [3 0]))
	me.ser.do_cmd('s'); % config menu
	rsp = me.ser.do_cmd('3'); % get wavelen 1
        m = me.ser.parse_matrix(rsp);
	% after any item on config menu is chosen, it returns to main menu.
	if (~isempty(m))
          me.settings.wavelen_nm(1)=m(1,1);
	end
	if (me.devinfo.num_chan>1)
          me.ser.do_cmd('s'); % config menu
          rsp = me.ser.do_cmd('4'); % get wavelen 2
          m = me.ser.parse_matrix(rsp);
          if (~isempty(m))
            me.settings.wavelen_nm(2)=m(1,1);
          end
	end
      end
        
      if (~me.cal_ok)
        [err msg] = me.get_cal();  % sets settings.wavelen_idxs and wavelen2_idxs
        if (err)
          fprintf('ERR: could not read calibration from device\n');
        end
      end
      %      me.settings.waveplates_rotm = zeros(me.devinfo.num_chan,3,3);
      if (me.cal_ok)
        for pc=1:me.devinfo.num_chan
          me.calc_int_align(pc); % sets settings.int_align_deg
        end
        
        %        for chan=1:me.devinfo.num_chan
          %          ax = me.cal.wp_axes((chan-1)*3+(1:3),1:me.devinfo.num_wp);
          %          rets_rad =  me.settings.waveplates_deg(chan,:)*pi/180;
          %          m = pol.muel_wp(ax, rets_rad);
          %          me.settings.waveplates_rotm(chan,:,:) = m(2:4,2:4);
          %        end
      end

      % fprintf('DBG: this is me.settings.int_align_deg:\n');
      % me.settings.int_align_deg
    end
    
    function set_tomo_state(me, chan, st)
      % desc: sets PA into one of 6 pre-calibrated waveplate settings using for tomography
      % inputs: chan: 1 or 2
      %         st: one of h,v,d,r,l,etc (a char)
      err=0;
      if ((chan<1)||(chan>me.devinfo.num_chan))
        error(sprintf('BUG: pa1000_class.set_wps(chan %d): bad channel\n', chan));
      end
      st=lower(st);
      if ((length(st)~=1)||~any(st=='hvdarl'))
        error(sprintf('BUG: pa1000_class.set_tomo_state(%s): bad state\n', st));
      end
      if (chan==1)
	cmd='c';
      else
	cmd='d';
      end
      % TODO: change this so it uses pdev_cmds
      % could also start using use tomography_1dev_GUI() somehow
      me.ser.do_cmd(cmd);
      me.ser.do_cmd(st);
    end

    function [err msg] = get_cal(me)
     % desc: fills in me.cal
     % Note: epa software repeated this up to 10 times in case of failure.
     % but why did it fail?  Is that fixed now?
     % returns:
     %    errmsg: ''= no error, otherwise a cell array of strings
    %     fprintf('PA.get_cal()');


    %      printf('timo %d', me.ser.cmd_timo_ms);
    %      printf('nchar %d', me.ser.cmd_nchar);
      
      me.ser.do_cmd('s', 'onfiguration');
      me.ser.set_cmd_params(20000, 2000);
      [rsp, err] = me.ser.do_cmd('p'); % optain the PA's current "calibration"
      if (err)
        fprintf('ERR: pa1000_class().get_cal err = %d!!!\n', err);
      end
      [err msg me.cal] = me.parse_printcal_rsp(me.devinfo, rsp, me.dbg_cal);
      me.cal_ok = ~err;
      me.cal.no_wl_interp = 0;  % FOR NOW
      if (me.cal_ok)
        for pc=1:me.devinfo.num_chan
          wlens = me.cal.pc_wavelens{pc};
          [mn idx]=min(abs(wlens-me.settings.wavelen_nm(pc)));
	  if (~isempty(idx))
            me.settings.wavelen_idxs(pc)=idx;
            wlens(idx)=0;
            [mn idx]=min(abs(wlens-me.settings.wavelen_nm(pc)));
            me.settings.wavelen2_idxs(pc)=idx;
          end
        end
      end
    end


    function [dur_ms counts] = measure(me, dur_ms)
    % desc: measures counts on signal fed to PA
    %       returns count rate in Hz, or -1 on overflow or error.
    %       NOTE: This is a capability not present on all PAs.
    % returns: dur_ms: duration actually used
    %          counts: -1 means overflow. otherwise counts.                                      
      if (me.devinfo.can_meas_sings)
          me.ser.do_cmd('m');
          [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r',round(dur_ms)));
          if (err)
            counts = 0;
          elseif (length(m)==2)
            dur_ms = m(1);
            counts = m(2);
          end
      else
        error('This PA cannot meaure singles counts');
      end
    end
    
    function errmsg = set_wavelen_nm(me, chan, wl_nm)
    % chan: 1 or 2
    % errmsg: ''=no error, otherwise a string
      errmsg='';
      if ((chan<1)||(chan>me.devinfo.num_chan))
      	errmsg = 'bad channel';
        error(sprintf('BUG: pa1000_class.set_wavelen_nm(chan %d): bad channel\n', chan));
      end
      if (~nc.util.ver_is_gte(me.devinfo.fwver, [3 0]))
	errmsg = 'NOTE: cant set wavelen of PA with fwver < 3.0';	
	return;
      end
        
      me.ser.do_cmd('s'); % config menu
      me.ser.do_cmd(num2str(chan)); % '1'=set wavelen1, '2'=set wavelen2
      if (nc.util.ver_is_gte(me.devinfo.fwver, [4 0])) % fwver 4.0 on up takes floats
	wl_str = sprintf('%f', wl_nm);
      else % fwver 3.0 requires integers
	wl_str = sprintf('%d', round(wl_nm));
      end
      rsp = me.ser.do_cmd([wl_str 13]); % specify wavelen

      % PA response is like: Index=##\n wavelen=##\n Index2=##\n
      % where the first index is the closest wavlen, and index2 is the second-closest.
      % wavlen is the wavelen actually used, which may be different from requested.
      idxs = strfind(rsp,'=')+1;

      if (length(idxs)>0)
	[v n] = sscanf(rsp(idxs(1):end),'%d',1);
	if (n==1)
          wl_idx=v+1;  % PAs rsp is zero-based
	  me.settings.wavelen_idxs(chan)  = wl_idx;
	  me.settings.wavelen2_idxs(chan) = wl_idx;
	end
      end
      if (length(idxs)>1)
	[v n] = sscanf(rsp(idxs(2):end),'%g',1);
	if (n==1)
	  me.settings.wavelen_nm(chan)=v;
	  % me.settings.wavelens_vld(chan)=1;
	end
      end
      % PA fwver 5.0.2 and up print the second index also
      me.settings.wavelen2_idxs(chan) = me.settings.wavelen_nm(chan);
      if (length(idxs)>2)
	[v n] = sscanf(rsp(idxs(3):end),'%g',1);
	if (n==1)  % PAs rsp is zero-based
          me.settings.wavelen2_idxs(chan) = v+1;
	end
      end
      me.calc_int_align(chan);
    end

    function zero_waveplates_of_pc(me, chan)
    % desc:
    %   zeros the waveplates of specified channel
    % inputs:
    %   chan: 1..2 : specifies channel   (base one)
      if (chan==1)
        rsp = me.ser.do_cmd('2');
      else     
        rsp = me.ser.do_cmd('3');
      end
      me.settings.waveplates_deg(chan, :)=0;
    end

    function calc_int_align(me, pc)
    % desc: calculates me.settings.int_align_deg(pc,1:3), which is always kept valid
    % inputs:
    %   pc: 1..2 : specifies channel   (base one)
      import nc.*
      if (me.devinfo.num_wp<6)
        me.settings.int_align_deg=zeros(me.devinfo.num_chan, 3);
        return;
      end
      if (~me.cal_ok) % probably not necessary, but just in case.
        me.settings.int_align_deg=zeros(me.devinfo.num_chan, 3);
        [err msg] = me.get_cal();  % sets settings.wavelen_idxs and wavelen2_idxs
        if (err)
          fprintf('ERR: could not read calibration from PA %s\n', me.devinfo.sn);
          fprintf('     %s\n', msg);
          return;
        end
      end
      idx  = me.settings.wavelen_idxs(pc);
      idx2 = me.settings.wavelen2_idxs(pc);
      wlens = me.cal.pc_wavelens{pc};

      k=me.devinfo.num_chan*(idx-1)+pc;
      rets_deg= me.cal.int_align(k,1:3);


      if ((idx2 ~= idx) && ~me.cal.no_wl_interp)
           
       k2=me.devinfo.num_chan*(idx2-1)+pc;
       rets2_deg= me.cal.int_align(k2,1:3);

       mm1 = pol.muel_wp(me.cal.wp_axes((pc-1)*3+(1:3),4:6), rets_deg*pi/180);
       mm2 = pol.muel_wp(me.cal.wp_axes((pc-1)*3+(1:3),4:6), rets2_deg*pi/180);
          
       wl1 = wlens(idx);
       wl2 = wlens(idx2);
       if (wl2==wl1)
         error('BUG: wavelen idxs different, but wavelens the same!');
       end
       f = (1/me.settings.wavelen_nm  - 1/wl1) / (1/wl2-1/wl1);

       if (0)
         % This way might be more correct but is more complex. NOT FINISHED
         md = mm2*mm1.';
         [rax r_rad]= pol.axis_of_rot(md(2:4,2:4));
         mm2 = pol.rot_around(rax, r_rad * f) * mm1;
         mm2
       else % we are only talking about < 0.1 deg usually!!!
         drets_deg = (mod(rets2_deg - rets_deg + 180,360)-180) * f;
         rets_deg = mod(rets_deg + drets_deg, 360);
       end
     end
     me.settings.int_align_deg(pc,1:3)=rets_deg;                             
   end

   function set_int_align(me, pc)
   % pa.SET_INT_ALIGN(pc)
   % desc: sets waveplate 4..6 to wavelength-dependent
   %       factory-calibrated "internal" alignment, which
   %       compensates the "internal" fiber between EFPC and BS                         .
      import nc.*
      if (me.devinfo.num_wp<6)
        return;
      end
      me.calc_int_align(pc); % probably unnecessary.
      me.set_waveplates_deg(pc, 4, me.settings.int_align_deg(pc,1:3));
    end
    
    function [errmsgs] = set_polarization(me, pc, v)
    % [errmsgs] = pa.SET_POLARIZATION(pc, v)
    % desc:
    %   Sets only the retardances of the first three waveplates.
    %   If light is going backwards
    %   through the PA, (and if it's a six-waveplate PA, the internal fiber must first be
    %   must be "aligned" by appropriate settings on waveplates 4 through 6), light will
    %   exit the PA with the polarization specified by v.
    %   If light is going forwared through the PA, this sets the retardances
    %   so as to measure in the basis specified by v.  
    %   Note: for v=[1; 0; 0], the first three retardances are set to zero.
    % inputs:
    %   pc: channel 1 or 2.
    %   v: 3x1 stokes vector [S1; S2; S3] - desired output polarization.
      import nc.*
      if ((~isvector(v))||any(size(v)~=[3,1]))
        error('pa1000.set_polarization(v): v must be 3x1');
      end
      errmsgs='';
      if (~me.cal_ok)
        [err errmsgs] = me.get_cal();
        if (err)
          return;
        end
      end
      if (isempty(me.cal))
        errmsgs='did not read waveplate calibration info from flash';
        return;
      end
      % fprintf('DBG: set polarization %s\n',sprintf(' %g', v));
        
      % In the tstsrc1000, light passes through FPC0 backwards, like:
      %    polarizer -> wp4(D) -> wp3(H) -> wp2(D) -> wp1(H) ->
      % If we don't vary wp4, wp3 is useless.  So we vary wp4, 3 & 2.
        

      v=pol.unitize(v);
      mgoal = pol.muel_rot_to_h(v);

      wp0 = 1;

      wp_axes = me.cal.wp_axes((pc-1)*3+(1:3),wp0+(0:2));

      [ret_rad muel err_ms] =pol.muel_ph_for_ideal_wp(round(wp_axes), mgoal);
      [ret_rad, err_ms]= pol.muel_solve_for_xform(wp_axes, ret_rad);
      
% vo = pol.muel_wp(wp_axes, ret_rad)*[1 1 0 0].';
%      fprintf('diff is: %g deg\n', pol.angdiff_deg(v, vo(2:4)));

      ret_deg = mod(ret_rad*180/pi,360);
      me.set_waveplates_deg(pc, wp0, ret_deg);

%      fprintf('DBG: wps %s deg\n', sprintf(' %6.2f', me.settings.fpc_deg));

    end

    function cal_set_waveplate_dac(me, pc, wp, dacval)
      % CAL_SET_WAVEPLATE_DAC(me, pc, wp, dacval)
      % desc
      %   This sets the dac value of the DAC that drives a waveplates 
      %   of a polarization controller.
      % inputs
      %   pc : 1 or 2. specifies polarization ctlr.
      %   wp : 1..6    specifies the waveplate to change
      %   dacval : a scalar (in DAC units)
      if ((wp<1)||(wp>6))
	error(sprintf('BUG: set_waveplates called with wp=%d\n', wp))
      end
          %   fprintf('DBG: pc %d  wp %d  dacv %d\n', pc, wp, dacval);
      if (nc.util.ver_is_gte(me.devinfo.fwver, [6 0]))
        % Now PA always prompts for waveplate, since this is a calibration
        % command and is used *before* the number of waveplates
        % have been set.
        me.ser.do_cmd('s'); % config
        me.ser.do_cmd('5'); % set waveplate in dac units
        me.ser.do_cmd([num2str(pc) char(13)]); % set ret in dac units
        me.ser.do_cmd([num2str(wp-1) char(13)]);
        me.ser.do_cmd([num2str(dacval) char(13)]);
        % returns to main menu
      elseif (nc.util.ver_is_gte(me.devinfo.fwver, [5 2]))
        me.ser.do_cmd('s'); % config
        me.ser.do_cmd('5'); % set waveplate in dac units
        if (me.devinfo.num_chan>1)
          me.ser.do_cmd([num2str(pc) char(13)]); % set ret in dac units
        end
        me.ser.do_cmd([num2str(wp-1) char(13)]);
        me.ser.do_cmd([num2str(dacval) char(13)]);
        % returns to main menu
      else
        off=0;
        if (pc==2)
  	  off=8;
        end
        me.ser.do_cmd('8'); % debug
        me.ser.do_cmd('1'); % write dac
        c = wp-1+off;
        if (c>9)
	  c=c-10+'a'-'0';
        end
        me.ser.do_cmd( char('0'+c));
        me.ser.do_cmd(  [ num2str(dacval) char(13)] );
      end
    end


    function cal_set_int_align(me, new_ia_deg)
    % new_ias: num_wl * 3
      if (~me.cal_ok)
        [err msg]=me.get_cal();
        if (err)
           fprintf('ERR: %s\n', msg);
           return;
        end
      end
      me.ser.set_dbg(1);
      me.ser.do_cmd('s'); % config                          
      rsp = me.ser.do_cmd('b'); % config                          
      idx = strfind(rsp, '=');
      if (isempty(idx))
        fprintf('ERR: PA did not supply config format');
        return;
      end
      cfg_fmt=sscanf(rsp(idx(1)+1:end),'%d',1);
      if (cfg_fmt~=5)
        error('pa1000_class.set_int_align(): this api cant handle this firmware');
      end
      for k=1:7
        me.ser.do_cmd(char(13));
      end
      'axis'
      for wp=1:me.devinfo.num_wp
        for c=1:3
          me.ser.do_cmd(char(13));                           
        end
      end
      'tomo settings'
      for ts=1:6
        for wp=1:3
           rsp = me.ser.do_cmd(char(13));
        end
      end
      if (~strfind(rsp,'num_wl'))
        'BUG: out of sync'
        return
      end
      me.ser.do_cmd(char(13));                           
      wavelens_nm = me.cal.pc_wavelens{1};
      for wl_i=1:length(wavelens_nm)
        me.ser.do_cmd(char(13));                           
        for wp=1:me.devinfo.num_wp
          for c=1:2
            me.ser.do_cmd(char(13));                           
          end
        end
          fprintf('\nINT ALIGN for wl %.1f\n',  wavelens_nm(wl_i));
        for k=1:3
          me.ser.do_cmd(sprintf('%g\r', new_ia_deg(wl_i, k)));
        end
      end                       
    end

    function set_waveplates_rotm(me, chan, wp, rotm)
    % pa.SET_WAVEPLATES_ROTM(chan, wp, rets_deg)
    % desc:
    %   Sets retardances of three adjacent waveplates to effect a rotation rotm.
    % inputs:
    %   chan: 1..devinfo.num_chan : specifies channel   (base one)
    %         Note: most PAs have only one channel.
    %     wp: 1..num_wp-2 : specifies starting waveplate (base one)
    %         If this is a four-waveplate PA, wp may be 1 or 2.
    %         if a six-waveplate PA, wp may be 1..4
    %   rotm: 3x3 rotation matrix.
    % changes:
    %    pa.settings.waveplates_deg(chan,wp)
      if (nargin<4)
        error('incorrect number of arguments');
      end
      if ((wp<1)||(wp+2>me.devinfo.num_wp))
        error(sprintf('wp must be 1 .. %d\n', 1, me.devinfo.num_wp-2));
      end
      if ((size(rotm,1)~=3)&&(size(rotm,2)~=3))
        error('rotm must be a 3x3 matrix');
      end
      if (~me.cal_ok)
        [err msg]=me.get_cal();
        if (err)
           fprintf('ERR: %s\n', msg);
           return;
        end
      end
      ax = me.cal.wp_axes((chan-1)*3+(1:3),wp+(0:2));
      muelm = [1 0 0 0; [0 0 0].' rotm]; % make it a mueler matrix
      rets_rad = nc.pol.muel_solve_for_arb_xform(ax, muelm);
      rets_deg = mod(rets_rad*180/pi,360);
      me.set_waveplates_deg(chan, wp, rets_deg);
    end

    function m = calc_waveplates_rotm(me, chan, wp_start, wp_end)
    % pa.CALC_WAVEPLATES_ROTM(chan, wp_start, wp_end)
    % desc:
    %   Calculates rotation matrix (on Poincare' sphere) effected by
    %   the set of specified waveplates as light flows from wp_start
    %   through wp_end.
    % inputs:
    %   chan: 1..devinfo.num_chan : specifies channel   (base one)
    %         Note: most PAs have only one channel.
    %   wp_start: 1..num_wp: specifies starting waveplate (base one)
    %   wp_end:   1..num_wp: specifies ending waveplate (base one)
    % returns:
    %   rotm: 3x3 rotation matrix.
      import nc.*;
      if (   (wp_start<1)||(wp_end<1) ...
             || (wp_start>me.devinfo.num_wp) || (wp_end>me.devinfo.num_wp))
        error(sprintf('wp_start and wp_end must range 1 to %d', me.devinfo.num_wp));
      end
      if (~me.cal_ok)
        [err msg]=me.get_cal();
        if (err)
           fprintf('ERR: %s\n', msg);
           return;
        end
      end
      if (wp_start<=wp_end)
        wp_rng=wp_start:wp_end;
        inv = 0;
      else
        wp_rng=wp_end:wp_start;
        inv = 1;
      end
      ax = me.cal.wp_axes((chan-1)*3+(1:3),wp_rng);
      rets_rad =  me.settings.waveplates_deg(chan,wp_rng)*pi/180;
      m = pol.muel_wp(ax, rets_rad);
      if (inv)
        m = m.';
      end
      m=m(2:4,2:4);
    end

      
    function set_waveplates_deg(me, chan, wp, rets_deg)
    % pa.SET_WAVEPLATES_DEG(chan, wp, rets_deg)
    % desc:
    %   Sets retardances of one or more waveplates.
    %   Generally the retardance range is about 0 to about 450 deg, but this limit
    %   is device-calibration specific. So for example, if you try setting
    %   the retardance to 460 deg, it might be clipped to 449 deg, not wrapped to
    %   90 degrees.  This allows you to exploit any subtle systematic
    %   difference between lets say 362 degrees vs just 2 degrees.
    %   After the function returns, your code can check
    %      pa.settings.waveplates_deg(chan,wp)
    %   to see what the retardance was actually set to.
    %   Or more conveniently, the calling code can just take the modulus if
    %   there's any possibility of the value being out of range, as in:
    %      pa.SET_WAVEPLATES_DEG(chan, wp, mod(rets_deg,360))
    % inputs:  
    %   chan: 1..devinfo.num_chan : specifies channel   (base one)
    %         Note: most PAs have only one channel.                               
    %     wp: 1..6 : specifies starting waveplate   (base one)
    %         Typical PAs have either four or six waveplates per channel
    %    rets_deg: 0..? : vector of retandances (in deg) to set the waveplate to
    %          range is limited in a device-calibration-specific manner.
    % changes:
    %    pa.settings.waveplates_deg(chan,wp)
      import nc.*
      num_chan = me.devinfo.num_chan;
      if ((chan<1)||(chan>num_chan))
        error(sprintf('pa1000_class.set_waveplates_deg(chan %d): bad channel\n', chan));
      end
      
      for k=1:length(rets_deg)
        if ((wp<1)||(wp>me.devinfo.num_wp))
          error(sprintf('pa1000_class.set_waveplates_deg: waveplate %d nonexistant', wp));
	end
        % ret_deg = mod(rets_deg(k),360);
        ret_deg = rets_deg(k);
        if (0) % TODO: eventually do this but now not sure about bridged multi-cmds.
          if (num_chan>1)
            cmd = ['h' num2str(chan) 13 num2str(wp-1) 13 sprintf('%.3f', ret_deg) 13];
          else
            cmd = ['h' num2str(wp-1) 13 sprintf('%.3f', ret_deg) 13];
          end
          rsp = me.ser.do_cmds(cmd, 3+(num_chan>1), 1000);
        else
          me.ser.do_cmd('h');
          if (num_chan>1)
            me.ser.do_cmd([num2str(chan) 13]);
          end
          me.ser.do_cmd([num2str(wp-1) 13]);
          me.ser.do_cmd(sprintf('%.3f\r', ret_deg));
        end
	me.settings.waveplates_deg(chan, wp)=ret_deg;
        wp=wp+1;
      end

      %      if (me.cal_ok)
      %        ax = me.cal.wp_axes((chan-1)*3+(1:3),1:me.devinfo.num_wp);
      %        rets_rad =  me.settings.waveplates_deg(chan,:)*pi/180;
      %        m = pol.muel_wp(ax, rets_rad);
      %        me.settings.waveplates_rotm(chan,:,:) = m(2:4,2:4);
      %      end
    end
    
  end
end
