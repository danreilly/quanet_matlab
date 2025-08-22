% cal_gas_cmp.m
%
function cal_gas_cmp(arg)
  import nc.*         
  opt_manually_review_all = 1;
  opt_plot_all = 0;
  mname = 'cal_gas_cmp.m';
  add_to_path('..\epa');
  fprintf('\n%s\n', mname);

  nc.uio.print_wrap('This can compare to gasline calibration runs\n');

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
    fn_full = tvars.ask_fname('calgas_fname');
    if (isempty(fn_full))
      return;
    end
  end
  
  fn_full2 = tvars.ask_fname('calgas2_fname');
  if (isempty(fn_full2))
    return;
  end


  k=1;
  [fn_path fn_name fn_ext] = fileparts(fn_full);

  fnf1=fn_full;
  idxs = strfind(fnf1, 'log\');
  if (~isempty(idxs))
    fnf1=fnf1(idxs(1):end);
  end
  fnf2=fn_full2;
  idxs = strfind(fnf2, 'log\');
  if (~isempty(idxs))
    fnf2=fnf2(idxs(1):end);
  end
  [root fnames]=futils.common_root({fnf1 fnf2});
  ttl = [{mname}; ...
 	 fname_class.wrap_at_slashes([root fnames{1}], 60); ...
         fname_class.wrap_at_slashes(['& ' fnames{2}], 60)];

  vars = vars_class(fn_full);
  vars2 = vars_class(fn_full2);


  data = vars.get('data',[]);
  data2 = vars2.get('data',[]);
  data_hdr = vars.get('data_hdr',[]);
  data_hdr2 = vars2.get('data_hdr',[]);


  if (isempty(data))
    fprintf('ERR: no data\n');
    return;
  end
  num_iter = vars.get('num_iter', 1);
  num_iter2 = vars2.get('num_iter', 1);
  tst_ref_choice=vars.get('tst_ref_choice', 'i');

  cfg_fsr = vars.get('cfg_fsr', []);

  refpure = vars.get('refpure', 1);
  refpure2 = vars2.get('refpure', 1);
  sweep_reflsr = vars.get('sweep_reflsr', 1);
  sweep_reflsr2 = vars2.get('sweep_reflsr', 1);
  lsr_desc_ca={'tunlsr'; 'reflsr'};
  sweep_desc = ['sweep ' lsr_desc_ca{sweep_reflsr+1}];
  if (sweep_reflsr ~= sweep_reflsr2)
    fprintf('WARN: one file changes reflsr, other changes tunlsr\n');
    uio.pause;
    sweep_desc = [sweep_desc ' & ' lsr_desc_ca{sweep_reflsr2+1}];
  end

  if (sweep_reflsr)
    lsr_designator='reflsr';
  else
    lsr_designator='tunlsr';
  end

  ref_pwr_col = vars.datahdr2col(data_hdr, 'ref_pwr');
  tun_pwr_col = vars.datahdr2col(data_hdr, 'tun_pwr');
  gasline_col  = vars.datahdr2col(data_hdr, 'gasline');  % reflsr gas cell
  gas_col      = vars.datahdr2col(data_hdr, 'gas');  % reflsr gas cell
  gas2_col     = vars.datahdr2col(data_hdr, 'gas2'); % tunlsr gas cell
  ph_deg_col      = vars.datahdr2col(data_hdr, 'ph_deg');  % reflsr gas cell
  ref_f_MHz_col  = vars.datahdr2col(data_hdr, 'ref_f_MHz');
  itla_f_MHz_col = vars.datahdr2col(data_hdr, 'itla_f_MHz');


  ref_pwr_col2 = vars.datahdr2col(data_hdr2, 'ref_pwr');
  tun_pwr_col2 = vars.datahdr2col(data_hdr2, 'tun_pwr');
  gas_col2     = vars.datahdr2col(data_hdr2, 'gas');  % reflsr gas cell
  gas2_col2    = vars.datahdr2col(data_hdr2, 'gas2'); % tunlsr gas cell
  ref_f_MHz_col2  = vars.datahdr2col(data_hdr2, 'ref_f_MHz');
  itla_f_MHz_col2 = vars.datahdr2col(data_hdr2, 'itla_f_MHz');




  if (sweep_reflsr)
    eff_gas_col = gas_col;
    lsr_pwr_col = ref_pwr_col;
    eff_f_MHz_col = ref_f_MHz_col;
  else
    eff_gas_col = gas2_col;
    lsr_pwr_col = tun_pwr_col;
    eff_f_MHz_col = itla_f_MHz_col;
  end
  if (sweep_reflsr2)
    eff_gas_col2 = gas_col2;
    lsr_pwr_col2 = ref_pwr_col2;
    eff_f_MHz_col2 = ref_f_MHz_col2;
  else
    eff_gas_col2 = gas2_col2;
    lsr_pwr_col2 = tun_pwr_col2;
    eff_f_MHz_col2 = itla_f_MHz_col2;
  end
  if (~eff_f_MHz_col || ~eff_f_MHz_col2)
    error('no ital freq recored in data in file');
  end

  gasline_col  = vars.datahdr2col(data_hdr, 'gasline');
  gasline_col2 = vars.datahdr2col(data_hdr2, 'gasline');
  if (~gasline_col || ~gasline_col2)
    error('no gasline col in data in file');
  else
    gaslines  = unique(data(:,gasline_col));
    gaslines2 = unique(data(:,gasline_col2));
    gaslines = union(gaslines, gaslines2);
  end
  gaslines_l = length(gaslines);
  fprintf('gaslines in common are: ');
  fprintf(' %d', gaslines);
  fprintf('\n');

  opt_manually_review_all = (gaslines_l==1);
  if (~nargin && (gaslines_l>1))
    opt_manually_review_all=tvars.ask_yn('review all lines', 'opt_manually_review_all', 1);
  end

  wavelen_nm_col = vars.datahdr2col(data_hdr, 'wavelen_nm'); % from wavemeter

  if (refpure)
    fine_MHz_col = vars.datahdr2col(data_hdr, 'fine_MHz');
    % frequency settings
    freqset_MHz_col = fine_MHz_col;
  else % todo
    % DFB laser has no freq setting
  end
  if (refpure2)
    fine_MHz_col2 = vars.datahdr2col(data_hdr2, 'fine_MHz');
    % frequency settings
    freqset_MHz_col2 = fine_MHz_col2;
  else % todo
    % DFB laser has no freq setting
  end


%na  if (gaslines_l~=length(gas_freqs_MHz))
%    fprintf('ERR: length of gas_freqs_MHz (%d) <> number of gas lines (%d) in data\n', );
%an    uio.pause;
%  end

  sp_h = 2;  
  sp_w = 2;  
  sp_i = 1;  

  myplot.init;
  co  = myplot.old_colormap;
  coq = myplot.colors_qtr;
  figure(gcf);

  glr_l=0;
  gaslineresult = zeros(gaslines_l, 7);
  
  for gaslines_i=1:gaslines_l
    gasline = gaslines(gaslines_i);
    idxs  = find(data(:,gasline_col)==gasline);
    idxs2 = find(data2(:,gasline_col2)==gasline);

    freqs_MHz = data(idxs, freqset_MHz_col);
    freqs_MHz2 = data2(idxs2, freqset_MHz_col2);

    gas  = data(idxs,  eff_gas_col);
    gas2 = data2(idxs2, eff_gas_col2);

    gas_freq_MHz = nist_lookup(gasline)/1e6;
    % fprintf('f %d\n', round(gas_freq_MHz))

    ttl2 = [ttl; sprintf('P%d = %dMHz', gasline,  round(gas_freq_MHz))];



    myplot.subplot(2,2);

    xlbl = 'finetune setting (MHz)';

    % if file contains nominal freq setting of pure laser being swept
    itla_base_MHz = 0;

    if (eff_f_MHz_col) 
      f = data(idxs, eff_f_MHz_col)-freqs_MHz;
      if (var(f)==0)
	itla_base_MHz = round(mean(f));
      else
        fprintf('BUG: gas sweep involved channel change\n');
        fprintf('     edit code to know true itla freq setting\n');
	fprintf('     var(f)=%g\n', var(f));
	if (1)
	  myplot.subplot;
	  base_MHz = round(data(idxs(1),eff_f_MHz_col)/1000)*1000;
	  plot(freqs_MHz,  data(idxs, eff_f_MHz_col )-base_MHz, '.','Color', coq(1,:));
	  plot(freqs_MHz2, data(idxs2,eff_f_MHz_col2)-base_MHz, '.','Color', coq(d21,:));
	  xlabel(xlbl);
	  ylabel(sprintf('offset from %.3fGHz (MHz)', round(base_MHz/1000)));
	  title([ttl2; sprintf('nominal freq settings of %s', lsr_designator)]);
	end
        uio.pause;
      end
    end


    xl = [min([freqs_MHz; freqs_MHz2]) max([freqs_MHz freqs_MHz2])];
    if (xl(2)==xl(1))
      xl=[xl(1)-1 xl(2)+1];
    end

    ok = 0;
    gas_norm_pwr_adc = 0;
    if (refpure && (tst_ref_choice=='i'))


      myplot.subplot;
      plot(freqs_MHz,  gas,  '.', 'Color', coq(1,:));
      plot(freqs_MHz2, gas2, '.', 'Color', coq(2,:));
      myplot.xlim(xl);
      xlabel(xlbl);
      ylabel('gas (adc)');
      myplot.title(ttl2);
      opt.plot_dip=0;
      opt.plot_fall=0;
      opt.plot_gauss=1;
      opt.MHz_per_xunits = 1;
      res = calc_gas_consts(freqs_MHz, gas, num_iter, opt);
      res2 = calc_gas_consts(freqs_MHz2, gas2, num_iter2, opt);
      myplot.txt(sweep_desc);

%      myplot.txt(sprintf('P%d %.1fMHz %.4fnm', gasline, gas_freq_MHz, c_mps/(gas_freq_MHz*1e6)*1e9));
      myplot.xlim(xl);
%      myplot.ylim([min(gas) 4095]);
      if (res.err)
	myplot.txt('CANT FIND DIP!','red');

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
	fall_hi_adc = round(res.gauss.o - 0.2 * res.gauss.fita);
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
if (0)
	myplot.txt(sprintf('gauss_hh_wid %.1f', res.gauss.hh_wid_x));
	myplot.txt(sprintf('fall_mid %d', gas_goal_adc)); % res.fall.mid_adc));
	myplot.txt(sprintf('         %.1f MHz', round(midslope_MHz)));
	myplot.txt(sprintf('fall range %d .. %d', fall_lo_adc, fall_hi_adc));
	myplot.txt(sprintf('slope    %g adc/kHz', fall_slope_adcpMHz*1000));
	% sort of for dbg:
	myplot.txt(sprintf('setting at dip %d MHz', itla_base_MHz + round(res.dip.min_MHz)));
	% sort of for dbg:
	myplot.txt(sprintf('gauss min %d', round(res.gauss.o - res.gauss.fita)));
end
%	gas_goal_adc       = res.fall.mid_adc;
%	fall_slope_adcpMHz = res.fall.slope_adcpMHz;
%	fall_hi_adc        = res.fall.hi_adc;
%	fall_lo_adc        = res.fall.lo_adc;
%	fall_mid_offset_MHz = res.dip.min_MHz - res.fall.mid_MHz; % offset in finetune units

      end





      pwr_adc = 0;
      if (lsr_pwr_col)
	lsr_pwr  = data(idxs, lsr_pwr_col);
	lsr_pwr2 = data2(idxs2, lsr_pwr_col2);
  	m = mean(lsr_pwr);
	myplot.subplot;
	pwr_ply = polyfit_autocond(freqs_MHz, lsr_pwr, 1);
	pwr_ply2 = polyfit_autocond(freqs_MHz2, lsr_pwr2, 1);
	if (res.err)
	  pwr_adc = round(m);
        else
          pwr_adc = round(polyval(pwr_ply, res.fall.mid_MHz));
        end
	if (res2.err)
	  pwr_adc2 = round(mean(lsr_pwr2));
        else
          pwr_adc2 = round(polyval(pwr_ply2, res2.fall.mid_MHz));
        end
	plot(freqs_MHz, lsr_pwr, '.', 'Color', coq(1,:));
	plot(freqs_MHz2, lsr_pwr2, '.', 'Color', coq(2,:));
	yy=polyval(pwr_ply, xl);
	line(xl,yy,'Color',co(1,:));
	yy=polyval(pwr_ply2, xl);
	line(xl,yy,'Color',co(2,:));
	r = max(lsr_pwr)-min(lsr_pwr);

%	myplot.txt(sprintf('mean %.4f', m));
%	myplot.txt(sprintf('range %d = %.2f%%', r, r*100/m));
	myplot.txt(sprintf('norm to %d %d', pwr_adc, pwr_adc2));
	% myplot.txt(sprintf('DBG: det effic = %.5f adc/adc', res.gauss_min_adc /  m))
	myplot.xlim(xl);
	xlabel(xlbl);
	ylabel(sprintf('%s pwr (adc)', lsr_designator));
	myplot.title([ttl2; 'laser power during sweep']);

	gas_norm = gas * pwr_adc./lsr_pwr;
	gas_norm2 = gas2 * pwr_adc2./lsr_pwr2;

	myplot.subplot;
	plot(freqs_MHz,  gas_norm, '.', 'Color', coq(1,:));
	plot(freqs_MHz2, gas_norm2, '.', 'Color', coq(2,:));
        opt.plot_fall=0;
	res  = calc_gas_consts(freqs_MHz,  gas_norm,  num_iter, opt);
	res2 = calc_gas_consts(freqs_MHz2, gas_norm2, num_iter2, opt);
	if (res.err)
	  myplot.txt('CANT FIND DIP!','red');
        else
	  ok=1;
	  gas_norm_pwr_adc = pwr_adc;
	  if (1) % new
  	    gas_goal_adc = round(res.gauss.o - res.gauss.fita/2);
  	    gas_goal2_adc = round(res2.gauss.o - res2.gauss.fita/2);
            off_MHz  = res.gauss.hh_wid_x/2;
            off2_MHz = res2.gauss.hh_wid_x/2;
	    fall_hi_adc = round(res.gauss.o - 0.2 * res.gauss.fita);
	    fall_lo_adc = round(res.gauss.o - 0.9 * res.gauss.fita);
	    fall_hi2_adc = round(res2.gauss.o - 0.2 * res2.gauss.fita);
	    fall_lo2_adc = round(res2.gauss.o - 0.9 * res2.gauss.fita);
	    fall_slope_adcpMHz = -res.gauss.hh_slope_adcpx;
	    fall_slope2_adcpMHz = -res2.gauss.hh_slope_adcpx;
          else
  	    gas_goal_adc = res.fall.mid_adc;
    	    off_MHz = res.gauss.m - res.fall.mid_MHz; % offset in finetune units
          end
          fall_mid_offset_MHz = off_MHz; % offset in finetune units

	  gas_goal_MHz = res.gauss.m - off_MHz;
	  x1=(fall_hi_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;
	  x2=(fall_lo_adc-gas_goal_adc)/fall_slope_adcpMHz + gas_goal_MHz;
	  line([x1 x2], [fall_hi_adc fall_lo_adc], 'Color', 'red');

	  % PLOT OFFSET
	  plot([-off_MHz 0]+res.gauss.m, [1 1]*gas_goal_adc, ...
	       'color', 'red');
	  text(res.gauss.m, gas_goal_adc, ...
	       sprintf('%.1fMHz', off_MHz), ...
	       'Units', 'data', 'Color', 'red');
	  midslope_MHz  = gas_freq_MHz - off_MHz;
	  midslope2_MHz = gas_freq_MHz - off2_MHz;
	  myplot.txt(sprintf('gauss_hh_wid %.1f %.1f', res.gauss.hh_wid_x, res2.gauss.hh_wid_x));
	  myplot.txt(sprintf('linfit hi %5d %5d adc', fall_hi_adc, fall_hi2_adc));
	  myplot.txt(sprintf('      mid %5d %5d adc', gas_goal_adc, gas_goal2_adc)); 
	  myplot.txt(sprintf('         %.1f %.1f MHz', midslope_MHz, midslope2_MHz));
	  myplot.txt(sprintf('       lo %5d %5d adc', fall_lo_adc, fall_lo2_adc));
	  myplot.txt(sprintf('    slope %5g %5g adc/kHz', fall_slope_adcpMHz*1000, ...
fall_slope2_adcpMHz*1000));
	  myplot.txt(sprintf('xmittance %.2f', (res.gauss.o-res.gauss.fita)/res.gauss.o));
        end

std_MHz = 2.5;
std_adc = std_MHz * abs(fall_slope_adcpMHz);
fprintf('margin at lower  freqs: %.3f MHz\n', (fall_hi_adc-gas_goal_adc)/fall_slope_adcpMHz);
fprintf('margin at higher freqs: %.3f MHz\n', (gas_goal_adc-fall_lo_adc)/fall_slope_adcpMHz);
   

	myplot.title([ttl2; 'gas adjusted by pwr'])
	myplot.xlim(xl);
	xlabel(xlbl);
	ylabel('gas2 (adj adc)');
      end


%      gauss_min_adc = res.gauss.o - res.gauss.fita;





      % if we sweep reflsr, AMZI phase only has meaning if tunlsr is substituted for Clarity
      if (~sweep_reflsr && ph_deg_col)
        phs_uw_deg = util.unwrap(data(idxs, ph_deg_col), 360);
	phs_p = polyfit_autocond(freqs_MHz, phs_uw_deg,1);
	err_deg = phs_uw_deg - polyval(phs_p, freqs_MHz);

	fall_mid_ph_deg = polyval(phs_p, gas_goal_MHz);
        fall_mid_ph_off_deg = fall_mid_offset_MHz * phs_p(1);

	if (~isempty(cfg_fsr))
% uio.print_matrix('cfg_fsr', cfg_fsr);
	  ctr_fsr_kHz = cfg_fsr(1);
	  fsr_MHz = ctr_fsr_kHz/1000;
	  % todo: use temperature
	  fall_mid_offset_MHz = fall_mid_ph_off_deg * fsr_MHz / 360;

	  midslope_MHz = gas_freq_MHz - fall_mid_offset_MHz;
        end
'DBG1'
        finetune_correct = phs_p(1)*fsr_MHz / 360
fall_slope_adcpMHz
	fall_slope_adcpMHz =  fall_slope_adcpMHz /finetune_correct;

        myplot.subplot;
        plot(freqs_MHz, phs_uw_deg, '.');
        yy=polyval(phs_p, xl);
        line(xl, yy, 'Color','green');
	ctr_deg = polyval(phs_p, res.gauss.m);
        line([1 1]*gas_goal_MHz, [ctr_deg fall_mid_ph_deg], 'Color','red');
        line([gas_goal_MHz res.gauss.m], [1 1]*ctr_deg, 'Color','red');
        myplot.txt(sprintf('     at ctr %.1f deg', ctr_deg));
        myplot.txt(sprintf('at midslope %.1f deg', mod(fall_mid_ph_deg+180,360)-180));
        myplot.txt(sprintf('     offset %.1f deg', fall_mid_ph_off_deg));
	xlabel(xlbl);
	ylabel('phase (deg)');
        myplot.xlim(xl);
	myplot.title([ttl2; 'AMZI phase']);

        myplot.subplot;
        plot(freqs_MHz, err_deg, '.');
        yy=polyval(phs_p, xl);
%        line(xl, yy, 'Color','green');
        myplot.txt(sprintf('using FSR %.3fMHz', fsr_MHz));
        myplot.txt(sprintf(' offset = %.3fMHz', fall_mid_offset_MHz));
	myplot.txt(sprintf('cor fact %.6f', finetune_correct));
%        plot(res.fall.mid_MHz, fall_mid_ph_deg, '.', 'Color', 'red');
	xlabel(xlbl);
	ylabel('fit err (deg)');
%	ylim([-180 180]);
        myplot.xlim(xl);
	myplot.title([ttl2; 'err of SL fit of AMZI phase']);
      end

      if (~sweep_reflsr && ~res.err)
	myplot.subplot;
   	plot((freqs_MHz-res.gauss.m)*finetune_correct, gas_norm, '.');
        xx = linspace(min(freqs_MHz), max(freqs_MHz))-res.gauss.m;
        yy = res.gauss.o - res.gauss.fita * exp(-(xx).^2/(2*res.gauss.s^2));
        plot(xx*finetune_correct, yy, '-','Color','green');
	ylabel('gas2 (adj adc)')
	xlabel(sprintf('offset from P%d (MHz)', gasline))
	xlim([xx(1) xx(end)]*finetune_correct);
	myplot.txt(sprintf('gauss_hh_wid %.1f', res.gauss.hh_wid_x * finetune_correct));
	myplot.title([ttl2; 'err of SL fit of AMZI phase']);
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
	fprintf(' midslope_freq %.1f   MHz  = %s\n', midslope_MHz, acetlyne_MHz2str(midslope_MHz));
	fprintf(' midslope_gas  %d     adc\n', gas_goal_adc);
	fprintf(' fall_hi       %d     adc\n', fall_hi_adc);
	fprintf(' fall_lo       %d     adc\n', fall_lo_adc);
	fprintf(' slope         %6g     adc/kHz\n', fall_slope_adcpMHz*1000);
	fprintf('\n');

	glr_l=glr_l+1;
	gaslineresult(glr_l,:)=[gasline round(midslope_MHz) gas_goal_adc gas_norm_pwr_adc fall_hi_adc, fall_lo_adc, fall_slope_adcpMHz];
      end
      

    end

    if (wavelen_nm_col)
      wavelen_nm = data(idxs, wavelen_nm_col);
      wmeter_freq_MHz = c_mps/1e6 ./ (wavelen_nm * 1e-9);

      p = polyfit_autocond(freqs_MHz, wmeter_freq_MHz, 1);

      myplot.subplot;
      plot(freqs_MHz, wmeter_freq_MHz,'.');
      line(xl, polyval(p, xl), 'Color', 'green');
      myplot.txt(sprintf('slope %g', p(1)));
      myplot.xlim(xl);
      xlabel(xlbl);
      ylabel('metered freq (MHz)');
      myplot.title(ttl);
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
  if (0)
  if (glr_l)
    fprintf('\n\nOK, hard-code the following into tunlsr.c:\n\n');
    fprintf('// line freq_MHz goal_adc ref_pwr_adc hi_adc lo_adc slope_adcpMHz\n');
    fprintf('gaslines_t %s_gaslines[]= {', lsr_designator);
    for k=1:glr_l
      if (k>1)
	fprintf(',\n');
      end
      fprintf(' {%d, %d, %d, %d, %d, %d, %.4f}', ...
	      gaslineresult(k,:));
    end
    fprintf('};\n');
  end
  fprintf('\n');
  end



  % write summary info about each gas line to a gaslines###.txt file
  idx = strfind(fn_name, 'calgas');
  if (sweep_reflsr)
    gl_fn_root = 'gaslines';
  else
    gl_fn_root = 'gas2lines';
  end
  if (idx)
    gl_fnf = [fn_path '\' gl_fn_root fn_name(idx+6:end) fn_ext];
    ok = ~exist(gl_fnf, 'file');
    if (~ok)
      fprintf('WARN: %s file already exists\n', gl_fn_root);
      fprintf('  %s\n', gl_fnf);
      q = '  change gaslines file';
    else
      q = sprintf('save %s file', gl_fn_root);
    end
    if (uio.ask_yn(q, ok))
      tvars.set(sprintf('%s_fname',gl_fn_root), gl_fnf);
      tvars.save;
      gl_vars = vars_class(gl_fnf);
      gl_vars.set('filetype', gl_fn_root);
      gl_vars.copy_vars(vars,{'date', 'host', 'serialnum','hwver','fwver','sweep_reflsr','desc'});
      gl_vars.set(gl_fn_root, gaslineresult);
      gl_vars.save;
      fprintf('  wrote %s\n\n', gl_fnf);
      gls=[];
    end  
  end
  if (sweep_reflsr)
    fprintf('\n');
    if (tvars.ask_yn('write gaslines file to device', 'write_gaslines', 1))
      wcal(gl_fnf);
      tvars.set(sprintf('%s_fname',gl_fn_root), gl_fnf);
      tvars.save;
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
