% cal_gas_show.m
%
% You can invoke this from matlab cmd line with no arguments, and you will be prompted
% to choose a calcgas###.txt file to display.
% Or it might be called from gal_gas after it takes data,  arg will be fname of
% calgas### file to display
function cal_gas_show(arg)
  import nc.*
  opt_manually_review_all = 1;
  opt_plot_all = 0;
  mname = 'cal_gas_show.m';

  fn_full='';
  if (nargin>0)
    fn_full = arg;
    if (ischar(arg))
      [pname fname ext] = fileparts(fn_full);
      pname = [pname '\'];
      fname = [fname ext];
    else
      uio.set_always_use_default(1);
    end
  else
    uio.set_always_use_default(0);
  end

  tvars=vars_class('tvars.txt');

  c_mps = 299792485.0; % speed of light m/s


  opt_review_all=0;

  if (isempty(fn_full))
    fn_full = tvars.ask_fname('gasline data file', 'measgas_fname');
    if (isempty(fn_full))
      return;
    end
  end
  
  k=1;
  [fn_path fn_name fn_ext] = fileparts(fn_full);

  ttl = [{mname}; fileutils.wrap_at_slashes(fn_full, 30)];


  vars = vars_class(fn_full);


  data = vars.get('data',[]);
  gas_p_torr = vars.get('gas_p_torr',25);
  is_hcn     = vars.get('is_hcn',0);
  data_hdr = vars.get('data_hdr',[]);
  serialnum = vars.get('serialnum','');
  if (isempty(data))
    fprintf('ERR: no data\n');
    return;
  end
  tvars.set('measgas_fname', fn_full);
  tvars.save;  

  num_iter = vars.get('num_iter', 1);
  tst_ref_choice=vars.get('tst_ref_choice', 'i');

  cfg_fsr = vars.get('cfg_fsr', []);

  refpure = vars.get('refpure', 1);
  sweep_reflsr = vars.get('sweep_reflsr', 1);

  if (sweep_reflsr)
    lsr_designator='reflsr';
    gas_designator='gas';
    lsr_idx=1;
  else
    lsr_designator='tunlsr';
    gas_designator='gas2';
    lsr_idx=2;
  end

  ref_pwr_col    = vars.datahdr2col(data_hdr, 'pwr_adc');
  tun_pwr_col    = vars.datahdr2col(data_hdr, 'tun_pwr');
  gasline_col    = vars.datahdr2col(data_hdr, 'gasline');  % reflsr gas cell
  gas_col        = vars.datahdr2col(data_hdr, 'gas_adc');  % reflsr gas cell
  gas2_col       = vars.datahdr2col(data_hdr, 'gas2'); % tunlsr gas cell
  ph_deg_col     = vars.datahdr2col(data_hdr, 'ph_deg');  % reflsr gas cell
  itla_f_MHz_col = vars.datahdr2col(data_hdr, 'ofreq_MHz');
  if (~sweep_reflsr)
    itla_f_MHz_col = vars.datahdr2col(data_hdr, 'itla_f_MHz');
  end

  gasline_col = vars.datahdr2col(data_hdr, 'gasline');
  if (~gasline_col)
    gaslines=0;
  else
    gaslines = unique(data(:,gasline_col));
  end
  gaslines_l = length(gaslines);

  opt_manually_review_all = (gaslines_l==1);
  if (~nargin && (gaslines_l>1))
    opt_manually_review_all=tvars.ask_yn('review all lines', 'opt_manually_review_all', 1);
  end

  wavelen_nm_col = vars.datahdr2col(data_hdr, 'wavelen_nm'); % from wavemeter

  if (refpure)
    fine_MHz_col = vars.datahdr2col(data_hdr, 'fine_MHz');
    % frequency settings
    freqset_MHz_col = fine_MHz_col;
  end


%na  if (gaslines_l~=length(gas_freqs_MHz))
%    fprintf('ERR: length of gas_freqs_MHz (%d) <> number of gas lines (%d) in data\n', );
%an    uio.pause;
%  end

  sp_h = 2;  
  sp_w = 2;  
  sp_i = 1;  

  tvars.save;  
  ncplot.init;
  figure(gcf);

  glr_l=0;
  gaslineresult = zeros(gaslines_l, 7);
  
  for gaslines_i=1:gaslines_l
    gasline = gaslines(gaslines_i);
    if (gasline_col)
      idxs = find(data(:,gasline_col)==gasline);
    else
      idxs = 1:size(data,1);
    end
    freqs_MHz = data(idxs, freqset_MHz_col);

    if (~sweep_reflsr)
      gas       = data(idxs, gas2_col);
    else
      gas       = data(idxs, gas_col);
    end

    if (is_hcn)
      gas_freq_MHz = tunlsr_class.hcn_lookup(gasline, gas_p_torr*133.322)/1e6;
    else
      error('TODO');
    end
    % fprintf('f %d\n', round(gas_freq_MHz))

    ttl2 = [ttl; sprintf('P%d = %dMHz', gasline,  round(gas_freq_MHz))];

    u_freqs_MHz = unique(freqs_MHz);
    u_freqs_l = length(u_freqs_MHz);

    ncplot.subplot(3,3);

    xlbl = sprintf('%s finetune setting (MHz)', lsr_designator);

    % if file contains nominal freq setting of pure laser being swept
    if (itla_f_MHz_col) 
      f = data(idxs, itla_f_MHz_col)-freqs_MHz;
      itla_base_MHz = round(mean(f));
      if (var(f)~=0)
        fprintf('BUG: gas sweep involved channel change\n');
        fprintf('     edit code to know true itla freq setting\n');
	fprintf('     var(f)=%g\n', var(f));
	if (1)
	  ncplot.subplot;
	  base_MHz = round(data(idxs(1),itla_f_MHz_col)/1000)*1000;
	  plot(freqs_MHz, data(idxs,itla_f_MHz_col)-base_MHz, '.');
	  xlabel(xlbl);
	  ylabel(sprintf('offset from %.3fGHz (MHz)', round(base_MHz/1000)));
	  title([ttl2; sprintf('nominal freq settings of %s', lsr_designator)]);
	end
        itla_base_MHz = 0;
        uio.pause;
      end
    end


    xl = [min(freqs_MHz) max(freqs_MHz)];
    if (xl(2)==xl(1))
      xl=[xl(1)-1 xl(2)+1];
    end


    ncplot.init();
    ncplot.subplot(1,2);
    
    ok = 0;
    gas_norm_pwr_adc = 0;
    if (refpure && (tst_ref_choice=='i'))


    if (0)      
      ncplot.subplot;
      plot(freqs_MHz, gas, '.');
      ncplot.xlim(xl);
      xlabel(xlbl);
      ylabel('gas (adc)');
      ncplot.title(ttl2);
      opt.plot_dip=1;
      opt.plot_fall=0;
      opt.plot_gauss=1;
      opt.dbg=0;
      opt.MHz_per_xunits = 1;

      % THIS SEEMS REDUNDANT AND NOT USED?
      % theres another calc_gas_consts later on.
      res = calc_gas_consts(freqs_MHz, gas, num_iter, opt);
      if (sweep_reflsr)
        ncplot.txt('sweep reflsr');
      else
        ncplot.txt('sweep tunlsr');
      end
%      ncplot.txt(sprintf('P%d %.1fMHz %.4fnm', gasline, gas_freq_MHz, c_mps/(gas_freq_MHz*1e6)*1e9));
      ncplot.xlim(xl);
%      ncplot.ylim([min(gas) 4095]);
      if (res.err)
	ncplot.txt('CANT FIND DIP!','red');

	gas_goal_adc       = mean(gas);
	gas_goal_MHz       = mean(freqs_MHz);
	fall_slope_adcpMHz = -1;
	fall_hi_adc        = max(gas);
	fall_lo_adc        = min(gas);
	fall_mid_offset_MHz = 0;

      else
%	plot(xl, [1 1]*res.fall.hi_adc, '-', 'color', 'yellow');
	  ok=1;
  	gas_goal_adc = round(res.gauss.o - res.gauss.fita/2);
        off_MHz = res.gauss.hh_wid_x/2;
	fall_hi_adc = round(res.gauss.o - 0.1 * res.gauss.fita);
	fall_lo_adc = round(res.gauss.o - 0.9 * res.gauss.fita);
	fall_slope_adcpMHz = -res.gauss.hh_slope_adcpx;
        fall_mid_offset_MHz = off_MHz; % offset in finetune units
	gas_goal_MHz = res.gauss.m - off_MHz;

%	off_MHz = res.dip.min_MHz - res.fall.mid_MHz;
	% PLOT OFFSET

	x1=(fall_hi_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;
	x2=(fall_lo_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;


        line([x1 x2], [fall_hi_adc fall_lo_adc], 'Color', 'red');

	plot([-off_MHz 0]+res.gauss.m, [1 1]*gas_goal_adc, ...
	     'color', 'red');
	text(res.gauss.m, gas_goal_adc, ...
	     sprintf('%.1fMHz', off_MHz), ...
	     'Units', 'data', 'Color', 'red');

	midslope_MHz = gas_freq_MHz - off_MHz;
	ncplot.txt(sprintf('gauss_hh_wid %.1f', res.gauss.hh_wid_x));
	ncplot.txt(sprintf('fall_mid %d', gas_goal_adc)); % res.fall.mid_adc));
	ncplot.txt(sprintf('         %.1f MHz', round(midslope_MHz)));
	ncplot.txt(sprintf('fall range %d .. %d', fall_lo_adc, fall_hi_adc));
	ncplot.txt(sprintf('slope    %g adc/kHz', fall_slope_adcpMHz*1000));
	% sort of for dbg:
	ncplot.txt(sprintf('setting at dip %d MHz', itla_base_MHz + round(res.dip.min_MHz)));
	% sort of for dbg:
	ncplot.txt(sprintf('gauss min %d', round(res.gauss.o - res.gauss.fita)));

%	gas_goal_adc       = res.fall.mid_adc;
%	fall_slope_adcpMHz = res.fall.slope_adcpMHz;
%	fall_hi_adc        = res.fall.hi_adc;
%	fall_lo_adc        = res.fall.lo_adc;
%	fall_mid_offset_MHz = res.dip.min_MHz - res.fall.mid_MHz; % offset in finetune units
       
      end
end


      if (sweep_reflsr)
	lsr_pwr_col = ref_pwr_col;
      else
	lsr_pwr_col = tun_pwr_col;
      end
      pwr_adc = 0;
      if (lsr_pwr_col)
	lsr_pwr = data(idxs, lsr_pwr_col);
  	m = mean(lsr_pwr);

	ncplot.subplot();
	pwr_ply = fit.polyfit(freqs_MHz, lsr_pwr, 1);
        pwr_adc = 1;
        
	plot(freqs_MHz, lsr_pwr, '.');
	yy=polyval(pwr_ply, xl);
	line(xl,yy,'Color','green');
	r = max(lsr_pwr)-min(lsr_pwr);
	ncplot.txt(sprintf('pwr mean %.4f', m));
	ncplot.txt(sprintf('pwr range %d = %.2f%%', r, r*100/m));
	ncplot.txt(sprintf('norm to %d', pwr_adc));
	% ncplot.txt(sprintf('DBG: det effic = %.5f adc/adc', res.gauss_min_adc /  m))
	ncplot.txt(sprintf('pwr slope %.3f adc/MHz', pwr_ply(1)));
%	pwrdep_dBpMHz = 10*log10(pwr_ply(1)/pwr_adc)/(max(freqs_MHz)-min(freqs_MHz))

	pctr_adc = round(polyval(pwr_ply,0));
	phi_adc  = round(polyval(pwr_ply,30000));
	plo_adc  = round(polyval(pwr_ply,-30000));

	ncplot.txt('across 60GHz tuning range');
	ncplot.txt(sprintf('    %.3f adc', pwr_ply(1)*60e3));
	ncplot.txt(sprintf('   =%.1f .. %.1f dB', ...
			   10*log10(plo_adc/pctr_adc),10*log10(phi_adc/pctr_adc)));
	ncplot.xlim(xl);
	xlabel(xlbl);
	ylabel(sprintf('%s pwr (adc)', lsr_designator));
	ncplot.title([ttl2; 'laser power during sweep']);

        %    uio.pause('laser pwr plot');



        
	gas_norm = gas * pwr_adc./lsr_pwr;
        gas_norm_pwr_adc = pwr_adc;

       
        opt.plot_gauss=0;
        opt.plot_dip=0;
        opt.plot_fall=0;
        opt.plot_fall=0;
        opt.dbg=0;
        opt.MHz_per_xunits = 1;        
	res = calc_gas_consts(freqs_MHz, gas_norm, num_iter, opt);
        
	ncplot.subplot();
	plot(freqs_MHz, gas_norm, '.');
        ncplot.title(ttl2);        
	if (res.err)
	  ncplot.txt('CANT FIND DIP!','red');
        else
	  ok=1;
	  if (1) % new
  	    gas_goal_adc = res.gauss.o - res.gauss.fita/2;
            off_MHz = res.gauss.hh_wid_x/2;
	    fall_hi_adc = res.gauss.o - 0.1 * res.gauss.fita;
	    fall_lo_adc = res.gauss.o - 0.9 * res.gauss.fita;
	    fall_slope_adcpMHz = res.gauss.hh_slope_adcpx;
          else
  	    gas_goal_adc = res.fall.mid_adc;
    	    off_MHz = res.gauss.m - res.fall.mid_MHz; % offset in finetune units
          end
          fall_mid_offset_MHz = off_MHz; % offset in finetune units

	  gas_goal_MHz = res.gauss.m - off_MHz;
          % plot slope of falling edge
	  %x1=(fall_hi_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;
	  %x2=(fall_lo_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;
	  %line([x1 x2], [fall_hi_adc fall_lo_adc], 'Color', 'red');
          % plot gaussian fit
          xx = linspace(min(freqs_MHz), max(freqs_MHz));
          yy = res.gauss.o - res.gauss.fita * exp(-(xx-res.gauss.m).^2/(2*res.gauss.s^2));
          plot(xx,yy,'-','Color','green');
	  % plot gaussian offset
          line([min(freqs_MHz) max(freqs_MHz)],res.gauss.o*[1 1],'Color','green');
          % indicate midpoint of dip, and halfwidth
          gas_goal_adc
	  plot([-off_MHz 0]+res.gauss.m, [1 1]*gas_goal_adc, 'color', 'red');
	  text(res.gauss.m, gas_goal_adc, ...
	       sprintf('%.1fMHz', off_MHz), ...
	       'Units', 'data', 'Color', 'red');
	  midslope_MHz = gas_freq_MHz + off_MHz;
	  ncplot.txt(sprintf('gauss_hh_wid %.1f', res.gauss.hh_wid_x));
	  ncplot.txt(sprintf('fall_mid %.3f', gas_goal_adc));
	  ncplot.txt(sprintf('         %.1f MHz', round(midslope_MHz)));
          %	  ncplot.txt(sprintf('fall range %.3f .. %.3f', fall_lo_adc, fall_hi_adc));
	  ncplot.txt(sprintf('slope    %g norm_adc/kHz', fall_slope_adcpMHz*1000));
	  ncplot.txt(sprintf('xmittance %.2f', (res.gauss.o-res.gauss.fita)/res.gauss.o));
        end

        std_MHz = 2.5;
        std_adc = std_MHz * abs(fall_slope_adcpMHz);
        % I forget what this is supposed to mean:
        %        fprintf('margin at lower  freqs: %.3f MHz\n', (fall_hi_adc-gas_goal_adc)/fall_slope_adcpMHz);
        %        fprintf('margin at higher freqs: %.3f MHz\n', (gas_goal_adc-fall_lo_adc)/fall_slope_adcpMHz);

	ncplot.title([ttl2; 'gas divided by pwr'])
	ncplot.xlim(xl);
	xlabel(xlbl);
	ylabel([gas_designator ' (adj adc)']);
      end


%      gauss_min_adc = res.gauss.o - res.gauss.fita;





      % if we sweep reflsr, AMZI phase only has meaning if tunlsr is substituted for Clarity
      if (~sweep_reflsr && ph_deg_col)
        phs_uw_deg = util.unwrap(data(idxs, ph_deg_col), 360);
	phs_p = fit.polyfit(freqs_MHz, phs_uw_deg,1);
	err_deg = phs_uw_deg - polyval(phs_p, freqs_MHz);

	fall_mid_ph_deg = polyval(phs_p, gas_goal_MHz);
        fall_mid_ph_off_deg = fall_mid_offset_MHz * phs_p(1);

	if (~isempty(cfg_fsr))
          uio.print_matrix('cfg_fsr', cfg_fsr);
	  ctr_fsr_kHz = cfg_fsr(1);
	  fsr_MHz = ctr_fsr_kHz/1000;
	  % todo: use temperature
	  fall_mid_offset_MHz = fall_mid_ph_off_deg * fsr_MHz / 360;

	  midslope_MHz = gas_freq_MHz + fall_mid_offset_MHz;
        end

        finetune_correct = phs_p(1)*fsr_MHz / 360

	fall_slope_adcpMHz =  fall_slope_adcpMHz /finetune_correct;

        ncplot.subplot;
        plot(freqs_MHz, phs_uw_deg, '.');
        yy=polyval(phs_p, xl);
        line(xl, yy, 'Color','green');
	ctr_deg = polyval(phs_p, res.gauss.m);
        line([1 1]*gas_goal_MHz, [ctr_deg fall_mid_ph_deg], 'Color','red');
        line([gas_goal_MHz res.gauss.m], [1 1]*ctr_deg, 'Color','red');
        ncplot.txt(sprintf('     at ctr %.1f deg', ctr_deg));
        ncplot.txt(sprintf('at midslope %.1f deg', mod(fall_mid_ph_deg+180,360)-180));
        ncplot.txt(sprintf('     offset %.1f deg', fall_mid_ph_off_deg));
	xlabel(xlbl);
	ylabel('phase (deg)');
        ncplot.xlim(xl);
	ncplot.title([ttl2; 'AMZI phase']);

        ncplot.subplot;
        plot(freqs_MHz, err_deg, '.');
        yy=polyval(phs_p, xl);
%        line(xl, yy, 'Color','green');
        ncplot.txt(sprintf('using FSR %.3fMHz', fsr_MHz));
        ncplot.txt(sprintf(' offset = %.3fMHz', fall_mid_offset_MHz));
	ncplot.txt(sprintf('cor fact %.6f', finetune_correct));
%        plot(res.fall.mid_MHz, fall_mid_ph_deg, '.', 'Color', 'red');
	xlabel(xlbl);
	ylabel('fit err (deg)');
%	ylim([-180 180]);
        ncplot.xlim(xl);
	ncplot.title([ttl2; 'err of SL fit of AMZI phase']);
      end

      if (~sweep_reflsr && ~res.err)
	ncplot.subplot;
   	plot((freqs_MHz-res.gauss.m)*finetune_correct, gas_norm, '.');
        xx = linspace(min(freqs_MHz), max(freqs_MHz))-res.gauss.m;
        yy = res.gauss.o - res.gauss.fita * exp(-(xx).^2/(2*res.gauss.s^2));
        plot(xx*finetune_correct, yy, '-','Color','green');
	ylabel('gas2 (adj adc)')
	xlabel(sprintf('offset from P%d (MHz)', gasline))
	xlim([xx(1) xx(end)]*finetune_correct);
	ncplot.txt(sprintf('gauss_hh_wid %.1f', res.gauss.hh_wid_x * finetune_correct));
	ncplot.title([ttl2; 'err of SL fit of AMZI phase']);
      end



      if (0)
	% percent of samples above gas_max
	pct = 100 * length(find(gas(1:i_c)>fall_hi_adc))/u_fine_l
	if (pct<20)
	  fprintf('WARN: only %.1f%% gas samps above max to left of dip\n');
	  uio.pause;
	end
	pct = 100 * length(find(gas(i_c:end)>fall_hi_adc))/u_fine_l
	if (pct<20)
	  fprintf('WARN: only %.1f%% gas samps above max to right of dip\n');
	  uio.pause;
	end
      end



%      if (abs(round(fall_slope_adcpMHz*1000))<1000)
%	uio.print_wrap('NOTE: slope in adc/kHz must be greater than 1000 to have error less than 1 part per thousand.\n');
%	fprintf(' it is %g\n', round(fall_slope_adcpMHz*1000));
%	uio.pause;
%      end


      if (ok)

	fprintf('\nRESULTS:\n');
	fprintf(' nist_line     %d\n', gasline);

        fprintf(' norm offset   %.3f\n', res.gauss.o);
	fprintf(' midslope_freq %.1f   MHz  = P%d + %d\n', midslope_MHz, gasline, round(midslope_MHz - gas_freq_MHz));

%	fprintf(' midslope_freq %.1f   MHz  = %s\n', midslope_MHz, tunlsr_class.acetlyne_MHz2str(midslope_MHz));
	fprintf(' midslope_gas  %.3f   adc\n', gas_goal_adc);
        %	fprintf(' fall_hi       %.3f   adc\n', fall_hi_adc);
        %	fprintf(' fall_lo       %.3f   adc\n', fall_lo_adc);
	fprintf(' slope         %6g    adc/kHz\n', fall_slope_adcpMHz*1000);
	fprintf('\n');

	glr_l=glr_l+1;
        %	gaslineresult(glr_l,:)=[gasline round(midslope_MHz) gas_goal_adc gas_norm_pwr_adc fall_hi_adc, fall_lo_adc, fall_slope_adcpMHz];

        % In the new gaslines, it;s normalized to 10000.
        % dip_norm is height of dip, normalized to 10000.
        dip_norm = round(10000 * (res.gauss.o - res.gauss.fita)/res.gauss.o);
        % The gauss curve is fitted to gas_norm, which is gas / lsr_pwr.
        % so gauss.o is the max transmittence ratio.
        normalizer = round(10000 / res.gauss.o);
        max_err_std_MHz = 100; % guess for now
        % now:                 [num     freq_MHz            hh_off_MHz                normalizer dip_norm lorentz max_err_std_MHz]
        gaslineresult(glr_l,:)=[gasline round(gas_freq_MHz) round(fall_mid_offset_MHz) normalizer dip_norm 0 max_err_std_MHz];
        
      end
      

    end

    if (wavelen_nm_col)
      wavelen_nm = data(idxs, wavelen_nm_col);
      wmeter_freq_MHz = c_mps/1e6 ./ (wavelen_nm * 1e-9);

      p = fit.polyfit(freqs_MHz, wmeter_freq_MHz, 1);

      ncplot.subplot;
      plot(freqs_MHz, wmeter_freq_MHz,'.');
      line(xl, polyval(p, xl), 'Color', 'green');
      ncplot.txt(sprintf('slope %g', p(1)));
      ncplot.xlim(xl);
      xlabel(xlbl);
      ylabel('metered freq (MHz)');
      ncplot.title(ttl);
    end


    if ((gaslines_l>1) && opt_manually_review_all)
      uio.pause;
    end

  end % lines_i



  if (~glr_l)
    fprintf('\n\nERR: no dips found!  Bad data!\n')
    return;
  end



  gaslineresult= gaslineresult(1:glr_l,:);



  % write summary info about each gas line to a gaslines###.txt file

  datedir=fileutils.nopath(fn_path);
  [n is ie]=fileutils.num_in_fname(fn_name);  
  if (sweep_reflsr)
    gl_fn = sprintf('calgas_%s_%s_%02d.txt', serialnum, datedir, n);
  else
    gl_fn = sprintf('calgas2_%s_%s_%02d.txt', serialnum, datedir, n);
  end

  gl_fnf = [fn_path '\' gl_fn];
  ok = ~exist(gl_fnf, 'file');
  if (~ok)
    fprintf('WARN: %s file already exists\n', gl_fn);
    fprintf('  %s\n', gl_fnf);
    q = '  change gaslines file';
  else
    q = sprintf('save %s file', gl_fn);
  end
  if (uio.ask_yn(q, ok))
    tvars.set(sprintf('%s_fname',gl_fn), gl_fnf);
    tvars.save;
    gl_vars = vars_class(gl_fnf);
    gl_vars.set('filetype', 'gaslines');
    gl_vars.copy(vars,{'date', 'host', 'serialnum','hwver','fwver','desc'});
    gl_vars.set('laser_idx', lsr_idx);
    gl_vars.set('gaslines', gaslineresult);
    gl_vars.set('src_file', fn_full);

    gl_vars.save;
    fprintf('  wrote %s\n\n', gl_fnf);
    gls=[];
  end  

  if (sweep_reflsr)
    fprintf('\n');
    if (tvars.ask_yn('write gaslines file to device', 'write_gaslines', 1))
      wcal(gl_fnf);
    end
  end


  if (0)
    fprintf('\nDuring calibration, the way to set the rotation of the iqmap\n');
    fprintf('correctly is to lock both the ref and tunable lasers to the same\n');
    fprintf('gas line, and then run cal_iqmap.\n');
    if (tvars.ask_yn('write a gasline to tunlsr', 'write_gas_to_dev', 1))
      idx=1;
      if (gaslines_l>1)
	fprintf('you just calibrated gas lines');
	fprintf(' %d', gaslines);
	fprintf('\n');
	while(1)
	  gasline = uio.ask('which one?', gaslines(1));
	  idx = find(gasline==gaslines,1);
	  if (~isempty(idx))
            break;
	  end
	end
      end
      tunlsr_port = tvars.get('tunlsr_port');
      [port, idn] = testutils.dev_ask_open('tunlsr', tunlsr_port, 115200);
      if (~isempty(port))
	tvars.set('tunar_port', port);
	if (strcmp(idn.name,'tunlsr'))
          tl=tunlsr_class(port);
	  tl.set_tunlsr_gas(gaslineresult(idx,:));
	  tl.delete;
	end
      end
    end
  end
  tvars.save;


end
