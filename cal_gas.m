
function cal_gas
  mname='cal_gas.m';
  fprintf('\n%s\n', mname);
  import nc.*;

  fprintf('Carefully steps tunlsr or reflsr freq around each gas line in a set of gas lines, measuring the gas cell.\n\n');

  u=uio;
  if (nargin>0)
    uio.set_always_use_default(1)
  end

  %  serial_cleanup();
  c_mps = 299792485.0; % speed of light m/s

  tvars = nc.vars_class('tvars.txt');
  log_path = fullfile('log', ['d' datestr(now,'yymmdd')]);
    

  %  ser_class.init();

%  tunlsr_port = tvars.get('tunlsr_port');
  [port idn] = tvars.ask_port({'tunlsr','qna'}, 'stable_laser_dev', 115200);
  if (isempty(port))
    return;
  end

  is_tunlsr=0;
  is_qna=0;
  if (strcmp(idn.name,'qna1'))
    is_qna=1;
    dut=nc.qna1_class(port);
  else
    is_tunlsr=1;
    dut=tunlsr_class(port);
  end

  fn = fileutils.uniquename(log_path, sprintf('measgas_sn%s_00.txt', dut.devinfo.sn));
  fnf = [log_path '\' fn];
  ovars = vars_class(fnf);
  ovars.set('filetype', 'measgas');

%  fprintf('\nWARN: why do we need at  FSR to start with?\n');
%  fprintf('current FSR is %.6f MHz\n', dut.settings.fsr_hz/1e6);

  ovars.set_context(dut);

  if (is_tunlsr)
    fprintf('\nThis program can sweep either the reference laser or the tunable laser\n');
    sweep_reflsr = tvars.ask_yn('sweep reflsr', 'sweep_reflsr', 1);
    ovars.set('sweep_reflsr', sweep_reflsr);
  else
    sweep_reflsr=1;
  end
  if (sweep_reflsr)
    lsr_designator = 'reflsr';
  else
    lsr_designator = 'tunlsr';
  end

  sweep_tunlsr_goal=0;
  if (~sweep_reflsr)
    fprintf('\nYou can sweep the low-level tunlsr settings\n');
    fprintf('or the frequency feedback goal setting\n');
    sweep_tunlsr_goal = tvars.ask_yn('sweep tunlsr goal', 'sweep_tunlsr_goal', 0);
  end
  ovars.set('sweep_tunlsr_goal', sweep_tunlsr_goal);


  if (is_tunlsr)
    refpure = dut.settings.refpure
  else
    refpure = dut.devinfo.laser_is_pure;
  end
  ovars.set('refpure', refpure);
  if (refpure)
    reflaser_desc = 'pure';
  else
    reflaser_desc = 'dfb';
  end

  if (is_tunlsr)
    ovars.set('cfg_fsr', dut.settings.cfg.fsr);
    [tst_ref_choice reflaser_Hz reflaser_desc ...
     tst_lsr_choice tunlaser_Hz tunlaser_desc] = tunlsrutils_class.ask_lsr_choices(dut, refpure, ovars, tvars);
  else
    tst_ref_choice = 'i';
    reflaser_Hz    = dut.settings.itla.freq_MHz*1e6;
    reflaser_desc  = 'pure';
    tst_lsr_choice = 'i';
    tunlaser_Hz    = reflaser_Hz;
    tunlaser_desc  = 'pure';
  end



  %  dut.ser.set_dbg(1);

  switch tst_ref_choice
    case 'i'
      % reflaser_Hz = dut.settings.reflaser_MHz*1e6;
      % fprintf('\ntunlsr thinks reference laser is %.6fTHz\n', reflaser_Hz/1e12);
      if (sweep_reflsr)
        fprintf('\n unlocking reference laser feedback\n');
        %        dut.set_ref_rmode('u');
        if (is_tunlsr)
          dut.set_laser_fdbk_en(1,0);
          dut.cal_set_laser_fm(1, 2047);
        else
          dut.set_gas_fdbk_en(0);
        end
%        dut.set_itla_fm(1, 2047);
      else
	stat=dut.get_stat;
	ovars.set('ref_locked', stat.ref_locked);
	if (~stat.ref_locked)
	  fprintf('WARN: ref not locked\n');
	  uio.pause;
        end
      end
    case 'c'
      fprintf('ERR: you cannot sweep the clarity\n');
      return;
    case 'o'
      reflaser_desc = 'other';
      dut.set_ref_st(me, 0);
      fprintf('TODO: this code not written\n');
      return;
     % dut.set_ref_rmode('e', round(reflaser_Hz/1e6));
  end
  lock_errs=0;


  switch tst_lsr_choice
    case 'i'
      if (~sweep_reflsr && ~sweep_tunlsr_goal)
	fprintf('\n unlocking tunable laser feedback\n');
	dut.set_tunlsr_rmode('u');
        dut.set_itla_fm(0, 2047);
      end
    case 'c'

    case 'o'
	 
  end
  ovars.set('tst_lsr_choice', tst_lsr_choice);





  % ovars could only use reflaser_Hz if sweeping tunlsr.
  f_lo = 191.50e12;
  f_hi = 196.25e12;
  ftr_Hz = 30e9;
  if ((tst_ref_choice=='i') && refpure)
%    [f_lo f_hi ftr_Hz] = dut.get_laser_capabilities_Hz;
    fprintf('   laser capabilities:\n');
    fprintf('      freq %sHz ... %sHz\n', uio.sci(f_lo,6), uio.sci(f_hi,6));
    fprintf('     finetune +/- %sHz\n', uio.sci(ftr_Hz,6));
    fprintf('        wl %.2fnm ... %.2fnm\n', c_mps/f_hi*1e9, c_mps/f_lo*1e9);
    %    if (dut.settings.itla.ref_en)
    if (is_tunlsr)
      en=dut.settings.cal.itla_en(1);
      pwr_dBm = dut.settings.cal.itla_pwr_dBm(1);
    else
      en      = dut.settings.itla.en;
      pwr_dBm = dut.settings.itla.pwr_dBm;
    end
    
    if (en)
      fprintf('\n        currently %.2f dBm\n', pwr_dBm);
    else
      fprintf('\n        currently off\n');
    end
  end


%  dut.set_gas_fdbk(0, 1000, 250, 0.15);

  %  [samphdr_w samphdr] = dut.get_run_hdrs;
  if (is_tunlsr)
    [samphdr_w samphdr] = dut.get_sample_hdr();
  else
    % for qna, hdr is returned with data from cap command.
    samphdr = dut.get_cap_hdr();
    samphdr_w = length(findstr(samphdr,' '))+1;
  end
  
  uio.print_wrap('\n\nFor absolute accuracy of the TUNLSR, we must calculate the freq at mid-slope of the falling edge of the gas line dip.  This is at an offset from the center of the gas dip which is calculated based on published NIST standards.\n');
  if (refpure)
    uio.print_wrap('If you take wavemeter readings, this offset will be known more accurately than if you rely on PUREs nominal accuracy of finetune settings\n');
  else
    uio.print_wrap('If you dont also take Burleigh wavemeter readings, how will you accurately know what that offset is?  There are ways, but currently not implemented in test code.\n');
  end
  fprintf('TODO: add code to keep track of accuracy of this offset\n');
  fprintf('See tunlsr_calguide_docver#.pdf section on cal_gas.m\n');
  wmeter=[];
  while(isempty(wmeter))
    wavemeter_port = tvars.ask('enter Burleigh wavemeter port or "skip"', ...
                                     'wavemeter_port', 'skip');
    if (strcmp(wavemeter_port,'skip'))
      break;
    end
    wmeter = wavemeter_class(wavemeter_port);
    if (~wmeter.is_open)
      fprintf('ERR: cant open wmeter on port %s\n', wavemeter_port);
      uio.pause;
      wmeter.delete;
      wmeter=[];
    else
      ovars.set('pwr_meter', 'Burleigh');
      break;
    end
  end


  if (~isempty(wmeter))
    fprintf('\nEnsure that wavemeter is connected to ');
    if (sweep_reflsr)
      fprintf('front panel reflaser output\n');
    else
      fprintf('TSRIG,\nand that should be in front panel tunlsr output\n');
    end
    uio.pause;    
  end

  if (is_tunlsr)
  if (   ( sweep_reflsr && refpure && (tst_ref_choice=='i')) ...
      || (~sweep_reflsr && (tst_lsr_choice=='i')))
    if (isempty(dut.settings.iqmap) || all(all(dut.settings.iqmap==0)))
      fprintf('WARN: iqmap is necessary to determine stability using mag2 vector.');
      fprintf('WARN: iqmap not set.  abort? ');
      if (uio.ask_yn(1))
        dut.close();
        return;
      end
    end
  end
  end

  is_hcn = tvars.ask('is hcn','is_hcn');
  p_torr = tvars.ask('gas cell pressure (torr)','gas_p_torr');
  
  lines_l = 0;
  while (lines_l<=0)
    lines = tunlsrutils_class.ask_gasline_nums(tvars);
    if (is_hcn)
      [gas_freqs_Hz norm_xmit] = tunlsr_class.hcn_lookup(lines, p_torr*133.322);
     else
      [gas_freqs_Hz norm_xmit] = tunlsr_class.acetlyne_lookup(lines);
    end
    idxs = find(gas_freqs_Hz);
    lines = lines(idxs);
    lines_l = length(lines);
  end
  
  tvars.set('gasline_nums', lines);
  fprintf('will measure %d gas lines: ', lines_l);
  fprintf(' %d', lines);
  fprintf('\n');

  
%  gas_freqs_Hz = nist_lookup(sort(lines));

  ovars.set('gas_freqs_MHz', gas_freqs_Hz/1e6);



  tvars.save;



  if (refpure || ~sweep_reflsr)

    % resulting data matrix
    data_hdr   = 'gasline fine_MHz iter';
    init_data_hdr_w = 3;
    data_hdr_w = 3;

    data_hdr = [data_hdr ' ' samphdr];
    samphdr_col = data_hdr_w+1;
    data_hdr_w = data_hdr_w + samphdr_w;

    if (~isempty(wmeter))
      data_hdr = [data_hdr ' dBm wavelen_nm'];
      data_hdr_w  = data_hdr_w + 2;
      dBm_col        = data_hdr_w-1;
      wavelen_nm_col = data_hdr_w;
      wl_nm=0;
      pwr_dBm=0;
    end


    uio.print_wrap('\nTODO: for better accuracy, we should be able to take multiple measuremens at each freq, but for now you can take only one.  Please modify cal_gas.m and etc.');
    itr_l=1;
    uio.pause;


    if (sweep_tunlsr_goal)
      pre_sweep=0;
      final_range_MHz = tvars.ask('sweep range around each gasline (MHz)', 'sweep_range_MHz', 1300);
      fine_d_MHz = tvars.ask('sweep step (MHz)', 'fine_sweep_step_MHz', 50);
    else
      uio.print_wrap('\nFor better accuracy, this can take a preliminary coarse sweep so we can take a fine-sampled sweep focused only on the dip.\n');
      pre_sweep=tvars.ask_yn('do pre-sweeps (recommended)', 'pre_sweep', 1);
      pre_sweep_step_MHz = 200;
      pre_sweep_errs=0;
      accuracy_Hz = 2.0e9; % accuracy of Pure Photinics laser
      if (pre_sweep)
        final_range_MHz = tvars.ask('sweep range around each gasline (MHz)', 'sweep_range_MHz', 1300);
        fine_d_MHz = tvars.ask('sweep step (MHz)', 'fine_sweep_step_MHz', 50);
      else
        fine_d_MHz = tvars.ask('sweep step (MHz)', 'sweep_step_MHz', 100);
        final_range_MHz = 2*accuracy_Hz/1e6;
      end
    end
    
    sweep_rise = tvars.ask_yn('do a rising sweep (not falling)', 'sweep_rise', 1);

    ph_deg_col = ovars.datahdr2col(samphdr, 'ph_deg');

    ref_pwr_col = tvars.datahdr2col(data_hdr, 'ref_pwr');
    tun_pwr_col = tvars.datahdr2col(data_hdr, 'tun_pwr');


    if (sweep_reflsr)
      if (is_tunlsr)
        v_gas_col     = ovars.datahdr2col(samphdr, 'gas');  % reflsr gas cell
        v_lsr_pwr_col = ovars.datahdr2col(samphdr, 'ref_pwr');  % reflsr gas cell
      else
        v_gas_col     = ovars.datahdr2col(samphdr, 'gas_adc');
        v_lsr_pwr_col = ovars.datahdr2col(samphdr, 'pwr_adc');
        % itla_f_MHz_col = ovars.datahdr2col(samphdr, 'ref_f_MHz');
      end

      d_gas_col     = init_data_hdr_w + v_gas_col;
      d_lsr_pwr_col = init_data_hdr_w + v_lsr_pwr_col;
      if (is_tunlsr)
        itla_grid_Hz       = dut.settings.cal.itla_grid_MHz(1)*1e6;
        itla_first_chan_Hz = dut.settings.cal.itla_f0_MHz(1)*1e6;
      else
        itla_grid_Hz       = dut.settings.itla.grid_MHz(1)*1e6;
        itla_first_chan_Hz = dut.settings.itla.f0_MHz(1)*1e6;
      end
    else
      v_gas_col     = ovars.datahdr2col(samphdr, 'gas2') % tunlsr gas cell
      v_lsr_pwr_col = ovars.datahdr2col(samphdr, 'tun_pwr');  % reflsr gas cell

      d_gas_col = ovars.datahdr2col(data_hdr, 'gas2');  % tunlsr gas cell
      d_lsr_pwr_col = tun_pwr_col;
      % itla_f_MHz_col = ovars.datahdr2col(samphdr, 'itla_f_MHz');
      itla_grid_Hz = dut.settings.itla.grid_Hz;
      itla_first_chan_Hz = dut.settings.itla.first_chan_Hz;
    end


    if (is_tunlsr)
      fsamp_Hz = 1000000/dut.settings.samp_pd_us;
    else
      fsamp_Hz = 1000000/dut.settings.beat_dur_us;
    end
    stab_record_Hz = 20; % tvars.ask('recording frequency (Hz)', 'stab_record_Hz', fsamp_Hz/5);
    stab_ds = round(fsamp_Hz/stab_record_Hz);
    if (is_tunlsr)
      dut.cal_set_downsampling(stab_ds);
      % for qna, downsampling rate is a param to cap_go cmd.
    end
    ovars.set('num_iter', itr_l);

    ovars.set('data_hdr', data_hdr);


    fprintf('\n');
    desc = ''; % input('description of this test > ','s');
    ovars.set('desc', desc);


    ovars.save();
    [f errmsg] = fopen(fnf, 'a');
    if (f<0)
      fprintf('BUG: cant append %s\n', fnf);
      fprintf('      %s\n', errmsg);
      return;
    else
      fprintf('writing %s\n', fnf);
      fprintf(f, 'gas_p_torr=%d;\r\n', p_torr);
      fprintf(f, 'is_hcn = %d;\r\n', is_hcn);
      fprintf(f, 'data=[');
    end
    % This program writes data to the output file as it is measured,
    % rather than waiting until after all data has been measured and writing
    % all of the file at once.  That's because if the program crashes in
    % the middle of the night, at least you have partial data saved in the
    % file, although you might have to hand-edit it and put in an end-bracket
    % so the syntax of it is correct.


    ttl = [{mname}; fileutils.wrap_at_slashes(fnf, 30)];

    %    acc_Hz = 3.0e9;
    fines_l = round(final_range_MHz / fine_d_MHz);
    tfines_l = fines_l;


    data = zeros(lines_l*fines_l*itr_l, data_hdr_w);
    d_r=1;

    tvars.save();

    for line_i=1:lines_l

      gas_freq_Hz = gas_freqs_Hz(line_i);

      % gas_lines(line_i);  % WHAT WAS THIS?
      
      gas_line = lines(line_i);
      
      % NOTE: used to be like below before 8/11/25,
      %       but I see we already have norm_xmit
      %   gas_line_xmit = tunlsr_class.lookup_transmittance(gas_line);
      gas_line_xmit = norm_xmit(line_i);

      fprintf('\ngasline P%d\n', gas_line);

      if (sweep_tunlsr_goal)
        fines_MHz = round(linspace(gas_freq_Hz/1e6-final_range_MHz/2, ...
				   gas_freq_Hz/1e6+final_range_MHz/2, fines_l));
	
        fine_s_MHz = fines_MHz(1);
        fine_e_MHz = fines_MHz(end);
      else

	ch  = round(1 + (gas_freq_Hz - itla_first_chan_Hz)/itla_grid_Hz);
	fine_MHz = round((gas_freq_Hz - (itla_first_chan_Hz + (ch-1)*itla_grid_Hz))/1e6);
        fine_ctr_MHz = fine_MHz;
	fine_s_MHz = max(fine_MHz*1e6 - accuracy_Hz, -ftr_Hz)/1e6;
	fine_e_MHz = min(fine_MHz*1e6 + accuracy_Hz,  ftr_Hz)/1e6;


        MHz=round(gas_freq_Hz/1e6);
	fprintf('set %s to %d MHz = %.3f nm\n', lsr_designator, MHz, c_mps/gas_freq_Hz*1e9);
        %        dut.ser.set_dbg(1);
	if (dut.set_itla_mode(sweep_reflsr, 'd')) % dither
          'err'
        end
        dut.get_status();

        while (1)
	  dut.set_itla_freq(sweep_reflsr, MHz);
          if (dut.settings.itla.freq_MHz == MHz)
            break;
          end
          fprintf('tried to set freq to %d but got %d\n', MHz, dut.settings.itla.freq_MHz);
          if (~uio.ask_yn('try again',1))
            break;
          end
  	  dut.ser.write(['i' char(13)]);
 	  pause(2);
	  dut.ser.flush();
	  fprintf('  will retry\n');
        end
        dut.ser.set_dbg(0);
        dut.get_settings(); % current settings
        if (ch~=dut.settings.itla.chan)
          fprintf('ERR: chan is %d not %d\n', dut.settings.itla.chan, ch);
          return;
        end
	% dut.set_itla_channel(sweep_reflsr, ch);
        dut.wait_for_pwr_stability(sweep_reflsr, 1);

%        pause(5)
	while(1)
 	  err = dut.set_itla_finetune_MHz(sweep_reflsr, fine_s_MHz);
          if (~err)
            break;
          end
  	  dut.ser.write(['i' char(13)]);
 	  pause(60);
	  dut.ser.flush();
        end
%	dut.ser.set_dbg(0);
        fprintf('now waiting for stability\n');
        dut.wait_for_pwr_stability(sweep_reflsr, 0);
	dut.set_itla_mode(sweep_reflsr, 'w'); % whisper

	if (pre_sweep)
          dbg=1;
          l = round(2*accuracy_Hz / (pre_sweep_step_MHz*1e6));
          fine_MHz = fine_s_MHz;
          fprintf('pre-sweeping max of %d fine tune settings (%d to %d)\n', l, fine_s_MHz, fine_e_MHz);
          d_MHz = pre_sweep_step_MHz;
          st=1;
          while(fine_MHz < fine_e_MHz)
	    dut.set_itla_finetune_MHz(sweep_reflsr, fine_MHz);
            if (is_tunlsr)
    	      v = dut.samp;
            else
              [hdr v]=dut.cap(1);
            end
            gas     = v(v_gas_col);
            lsr_pwr = v(v_lsr_pwr_col);
	    if (st>1)
	      gas = gas * lsr_pwr_first / lsr_pwr;
            end
            if (dbg)
              fprintf(' %d', round(gas));
            end
            switch(st)
              case 1
		gas_first = gas;
                dip_thresh = gas_first * (1-(1-gas_line_xmit)*0.25);
                lsr_pwr_first = lsr_pwr;
		if (dbg)
    		  % fprintf(' [exp xmt %.1f]', gas_line_xmit);
  		  fprintf(' [thresh %.1f]', dip_thresh);
                end
		gas_min   = gas;
		st=2;
              case 2
		if (gas<dip_thresh)
		  gas_min = gas;
		  dip_MHz = fine_MHz;
		  st=3;
  		  d_MHz = d_MHz/2; % smaller steps now we are close
		  fprintf('\nDIP %.1f%%\n', (gas_first-gas)/gas_first*100);
		end
              case 3
		if (gas < gas_min)
		  gas_min = gas;
		  dip_MHz = fine_MHz;
		elseif ((gas-gas_min)/(gas_first-gas_min) > 0.05)
		  break; % rising again significantly
		end
            end
            fine_MHz = fine_MHz + d_MHz;
          end
          if (st==3)
	    fprintf('\nmin of %d at %.1f MHz\n', round(gas_min), dip_MHz);
	    fprintf('\nnorm trasmittance %.2f\n', gas_min/gas_first);
%  	    % I dont know why I have to add 300, but it works best when i do!
%            dip_MHz = dip_MHz + 300;
            fine_s_MHz = max(dip_MHz - final_range_MHz/2, -ftr_Hz/1e6);
            fine_e_MHz = min(dip_MHz + final_range_MHz/2,  ftr_Hz/1e6);
          else
            fprintf('\nERR: pre-sweep failed to find gasline %d\n', gas_line);
            return;
            pre_sweep_errs = pre_sweep_errs+1;
            fine_s_MHz = max(fine_ctr_MHz - final_range_MHz/2, -ftr_Hz/1e6);
            fine_e_MHz = min(fine_ctr_MHz + final_range_MHz/2,  ftr_Hz/1e6);
          end
	end % end if pre_sweep

        % I don't really used fines_MHz anymore...
        fines_MHz = linspace(fine_s_MHz, fine_e_MHz, fines_l);

      end


      fprintf('sweeping %d fine tune settings\n', fines_l);
      fprintf('  from %d to %dMHz, a range of %.1fMHz\n', fine_s_MHz, fine_e_MHz, fine_e_MHz - fine_s_MHz);
      dut.ser.set_dbg(0);
      if (~sweep_rise)
	fines_MHz = flipdim(fines_MHz,2);
      end
      fine_MHz = fines_MHz(1);

      dut.set_itla_finetune_MHz(sweep_reflsr, fine_MHz);
      dut.wait_for_pwr_stability(sweep_reflsr, 0);



      d_r_s = d_r;
      l = tfines_l*itr_l;
      st=1;
      datat=zeros(fines_l*itr_l, data_hdr_w);
      dt_r=0; % length of datat;
      fprintf('    freq (MHz)   gas_norm\n');
      f_i=1;
      
      while(1)
        if ((fine_MHz > fine_e_MHz)&&(st<3))
          fprintf('ERR: did not find dip. is this a bug?\n');
          break;
        end
	fprintf('    %d', round(fine_MHz));

        if (sweep_tunlsr_goal)
          dut.set_freq_MHz(fines_MHz(f_i));
	  pause(5); % TODO FIX
          if (dut.wait_for_lock(0, 60))
	    fprintf('ERR: tunlsr not locked after 1 min!\n');
            lock_errs = lock_errs+1;
          end
        else
          for tri=1:4
    	    err = dut.set_itla_finetune_MHz(sweep_reflsr, round(fine_MHz));
            if (~err)
              dut.wait_for_pwr_stability(sweep_reflsr, 0);
              break;
            end
            dut.ser.set_dbg(1);
	    dut.ser.write(['i' char(13)]);
 	    pause(60);
	    dut.ser.flush();
	    fprintf('DBG: cal_gas: set_finetune will retry\n');
            if (tri==4)
              uio.pause('really having trouble');
            end
          end
        end
        dut.ser.set_dbg(0);


        gases=zeros(itr_l,1);
        pwrs=zeros(itr_l,1);
	for itr_i=1:itr_l
	  dt_r = dt_r+1;
 	  datat(dt_r,1)=gas_line;
	  datat(dt_r,2)=fine_MHz;
	  datat(dt_r,3)=itr_i;
          if (is_tunlsr)          
  	    v = dut.samp;
          else
            [hdr v]=dut.cap(1);
          end
	  datat(dt_r, samphdr_col+(0:samphdr_w-1)) = v;
          gases(itr_l) = v(v_gas_col); % * 
          pwrs(itr_l)  = v(v_lsr_pwr_col);
	  if (~isempty(wmeter))
            [wl_m pwr_dBm] = wmeter.meas_wl_and_pwr;
	    datat(dt_r,dBm_col)        = pwr_dBm;
	    datat(dt_r,wavelen_nm_col) = wl_m*1e9;
	  end
        end  % for itr
        gas = mean_clean(gases);
        pwr = mean_clean(pwrs);

        gas = gas * lsr_pwr_first / pwr;

        
	fprintf('    %d\n', round(gas));

        switch(st)
          case 1
            %	    gas_first     = gas;
            %            lsr_pwr_first = pwr;
            %            dip_thresh = gas_first * (1-(1-gas_line_xmit)*0.25);
	    % fprintf('\n TH %.1f \n', dip_thresh);
	    st=2;
          case 2
	    if (gas<dip_thresh)
	      % fprintf('\n TH %.1f%% at %dMHz\n', (gas_first-gas)/gas_first*100, fine_MHz);
	      gas_min = gas;
	      dip_MHz = fine_MHz;
              fines_left = floor(fines_l/2)-1;
	      st=3;
	    end
	  case 3
	    if (gas < gas_min)
	      gas_min = gas;
	      dip_MHz = fine_MHz;
              fines_left = floor(fines_l/2)-1;
	      % fprintf('\nDIP %.1f%% at %dMHz\n', (gas_first-gas_min)/gas_first*100, dip_MHz);
	    else
   	      fines_left=fines_left-1;
	      if ((fines_left<=0)&&(dt_r>=l))
		break;
              end
	    end
	end % switch

	fine_MHz = fine_MHz + fine_d_MHz; % non-integer math
        f_i=f_i+1;
        
      end %while

      % datat migt be longer than necessary because it's sort of a search history.
      % Copy the final l lines of datat into data
      data(d_r+(0:l-1),:)=datat(dt_r-l+(1:l),:);
      if (f>=0)
	for f_i=0:l-1
	  if (d_r+f_i>1)
	    fprintf(f, '\r\n');
          end
	  fprintf(f, ' %.12g', data(d_r+f_i,:));
        end
      end
      d_r=d_r+l;

      if (ph_deg_col)
        phs_uw_deg = util.unwrap(data(d_r_s:d_r-1, ph_deg_col), 360);
      end
      
      ncplot.init;
      gas_norm = data(d_r_s:d_r-1,d_gas_col) * lsr_pwr_first ./ data(d_r_s:d_r-1,d_lsr_pwr_col);
      plot(reshape(repmat(fines_MHz, itr_l,1),[],1), gas_norm, '.');
      xlabel('freq (MHz)');
      ylabel('gas (adj adc)');
      ncplot.txt(sprintf('P%d', gas_line));
      ncplot.title(ttl);
      drawnow;
      uio.pause('review plot');
    end
    dut.close;


  else
    % ref is DFB
    fprintf('current reftemp settings: %d %d\n', dut.settings.reftemp_coarse, dut.settings.reftemp_fine);
    coarse = dut.settings.reftemp_coarse;
    coarse = uio.ask('coarse', coarse);

    fines_l = 100;
    fines=round(linspace(0, 4095, fines_l));
    gass = zeros(1,fines_l);
    if (refpure)
      dut.set_fm(0);
    else
      if (dut.settings.reftemp_fine || (coarse ~= dut.settings.reftemp_coarse));
	fprintf('setting reftemp to %d, 0\n', coarse);
	dut.set_reftemp(coarse, 0);
	pause(8);
      end
      dut.get_set; % current settings
      fprintf('current reftemp settings: %d %d\n', dut.settings.reftemp_coarse, dut.settings.reftemp_fine);
    end

    fprintf('sweeping %d fine settings...\n', fines_l);
    for f_i=1:fines_l
      dut.set_reftemp(coarse, fines(f_i));
      pause(0.5);
      v = dut.samp;
      gass(f_i)=v(v_gas_col);
    end
    dut.set_reftemp(coarse, 0);
    dut.close;

  end


  if (f>=0)
    fprintf(f, '];\r\n');
    fprintf(f, 'pre_sweep_errs = %d;\r\n', pre_sweep_errs);
    fprintf(f, 'lock_errs = %d;\r\n', lock_errs);
    fprintf('\nwrote %s\n', fnf);
    fclose(f);
  end

  tvars.set('measgas_fname', fnf);
  tvars.save;

  if (pre_sweep_errs) 
    fprintf('ERR: there were %d failures of pre-sweep algorithm\n', pre_sweep_errs);
    uio.pause;
  end
  if (lock_errs) 
    fprintf('ERR: there were %d incidents of failure to lock\n', lock_errs);
    uio.pause;
  end
    
  fprintf('\nrunning cal_gas_show\n');
  cal_gas_show(fnf);

end



function m=mean_clean(v)
  med = median(v);
  s = std(v);
  idxs = find(abs(v-med)>2*s);
  num_outliers = length(idxs);
  if (num_outliers)
    fprintf('WARN: %d outliers\n', num_outliers);
    v(idxs)
  end
  idxs=find(abs(v-med)<=2*s);
  m = mean(v(idxs));
end
