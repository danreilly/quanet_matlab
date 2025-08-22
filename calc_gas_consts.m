function res = calc_gas_consts(freq_MHz, gas, num_iter, opt)
% inputs
%    gas: samples of gas cell in ADC units
%    num_iter: number of measurements taken at each frequency setting
%    freq_MHz: the frequencies at which samples were taken. This vector
%              must be the same size as gas.  Might be in units of MHz or deg,
%              but units should be linear.
%    opt.plot_dip : 
%    opt.plot_fall : 
%    opt.plot_gauss : 
%    opt.MHz_per_xunits
% outputs
%  
%  res.err: 0=found, 1=could not find dip
%  res.dip.min_MHz: frequency of center of fitted parabola
%  res.dip.min_adc: gas value at minimum of fitted parabola, in ADC units
%
%  res.fall.mid_MHz: frequency at midslope of falling edge of dip
%  res.fall.mid_adc: gas cell value at midslope of falling edge of dip
%  res.fall.hi_adc: gas cell value at 90% of falling edge of dip
%  res.fall.lo_adc: gas cell value at 10% of falling edge of dip
%  res.fall.slope_adcpMHz: slope of falling edge of dip
%
%  res.gauss.fita: amplitude
%  res.gauss.m: middle, in x units
%  res.gauss.s: std dev
%  res.gauss.o: offset
%  res.gauss.min_adc: minimum point on gaussian fit
%  res.gauss.hh_wid_x: width at half height (3dB)
%  res.gauss.hh_slope_adcpx: slope at half height
%  res.gauss.rmse: 
% gaussian fit is:
%   y = gauss.o - gauss.fita * exp(-(x-gauss.m).^2/(2*gauss.s^2));

%  res.lorentz.m=m;
%  res.lorentz.o=gas_mx - o;
%  res.lorentz.g=g;
%  res.lorentz.a=a;
%  res.lorentz.rmse=rmse;


%  res.offset_MHz = ctr_MHz - goal_MHz;
%
%     Note: give a measurement gas_adc, you can convert to frequency using:
%         (gas_adc - fall_mid_adc)/gas_slope_adcpMHz + gas_mid_MHz
%     but only if: fall_lo_adc < gas_adc < fall_hi_adc
  import nc.*

  opt=util.set_field_if_undef(opt,'dbg',0);

  % force both to be vertical vectors
  if (size(freq_MHz,2)>1)
    freq_MHz = resize(freq_MHz,[],1);
  end
  if ((size(gas,1)==1)&&(size(gas,2)>1))
    gas = gas.';
  end


  res.err = 0;


  gas_flt=filt.gauss(gas, 1, 1/5, 7);
  err=gas-gas_flt;
  s = std(err);
  if (1)
    idxs=find(abs(err)>3*s);
    f=figure();
    ncplot.init;
    [co,ch,cq]=ncplot.colors();
    plot(freq_MHz, gas,'.','Color',ch(1,:));
    plot(freq_MHz, gas_flt,'-','Color',cq(1,:));
    plot(freq_MHz(idxs), gas(idxs),'.','Color','red');
    uio.pause;
    delete(f);
  end
  idxs=find(abs(err)<=3*s);
  gas=gas(idxs);
  freq_MHz=freq_MHz(idxs);

  


  
  i_min = find(gas==min(gas),1);
  gas_min = mean(gas(idx_s(i_min):idx_e(i_min)));
  res.dip.min_MHz = freq_MHz(i_min);

  i_max = find(gas==max(gas(1:i_min)),1);
  gas_max = mean(gas(idx_s(i_max):idx_e(i_max)));

  fall_hi = (gas_max - gas_min)*0.8 + gas_min;
  fall_lo = (gas_max - gas_min)*0.2 + gas_min;
  fall_mid = round((fall_hi+fall_lo)/2);


  rng_pct_min = 10;
  rng_pct = 100 *((fall_hi - fall_lo)/fall_hi);
  if (rng_pct<rng_pct_min)
    fprintf('ERR: calc_gas_consts(): data range is %.1f%% but typical gas dips range more than %.1f%%\n', rng_pct, rng_pct_min);
    res.err=1;
    return;
  end
  xr_MHz = (max(freq_MHz)-min(freq_MHz))*opt.MHz_per_xunits;
  if (xr_MHz < 10)
    fprintf('calc_gas_consts ERR: x range = %g MHz is too small\n', xr_MHz);
    res.err=1;
    return;
  end


  i_s = find(gas(i_max:i_min) <= fall_hi,1)+i_max-1;
  i_s = idx_s(i_s);

  i_e = find(gas(i_max:i_min) >= fall_lo,1,'last')+i_max-1;
  i_e = idx_e(i_e);

  if (opt.dbg)
    f=figure();
    ncplot.init;
    cq=ncplot.colors_qtr;
    plot(freq_MHz, gas,'.','Color',cq(1,:));
    line(freq_MHz(i_s)*[1 1],[fall_lo fall_hi],'Color','green');
    line(freq_MHz(i_e)*[1 1],[fall_lo fall_hi],'Color','green');
    ncplot.txt(sprintf('range %d .. %d', round(gas_min), round(gas_max)));
    uio.pause;
    delete(f);
  end

  if (idx_s(i_e)<=i_s)
    fprintf('ERR: cant automatically find dip so you must fix something and retake data.\n');
    fprintf('  dip starts at idx %d and rises back att idx %d\n', i_s, i_e);
    res.err=1;
    return;
  end

  i_r = find(gas(i_min:end)>=fall_hi, 1)+i_min-1;
  if (isempty(i_r))
    fprintf('ERR: cant find rising edge after dip.  Should you sweep more?\n');
    fprintf('     (dip is at %d)\n', i_min)
%   res.err=1;
%   return;
  end
  i_r = idx_e(i_r);



  if (i_r - i_s+1 < 3)
    fprintf('ERR: only %d points in dip, cant fit parabola\n', i_r-i_s+1);
    res.err=1;
    return;
  end

  % fprintf('DBG: fitting parabola to data to %d pts from %g to %g\n', i_r-i_s+1, freq_MHz(i_s), freq_MHz(i_r));
  prb = fit.polyfit(freq_MHz(i_s:i_r), gas(i_s:i_r), 2); % parabola

  % find MSE straight line fit of falling edge
  pl = fit.polyfit(freq_MHz(i_s:i_e), gas(i_s:i_e),1);
  
  if (opt.plot_dip)
    % highlight the dip sample points in red
    ncplot.init;
    plot(freq_MHz(i_s:i_r), gas(i_s:i_r),'.','color','blue');
    plot(freq_MHz([i_s i_r]), fall_mid*[1 1],'-','color','red');
    yy = polyval(prb, freq_MHz(i_s:i_r));
    plot(freq_MHz(i_s:i_r), yy, '-', 'color', 'green');
    yf=polyval(pl, freq_MHz(i_s:i_e));
    line(freq_MHz(i_s:i_e), yf, 'Color', 'black');
    uio.pause;
  end

%fprintf('parab = ');
%fprintf(' %g', prb);
%fprintf('\n');

  if (prb(1)<0)
    fprintf('ERR: fitted parabola is not concave-up\n');
    res.err=1;
    return;
  end
  res.dip.min_MHz = -prb(2)/(2*prb(1));

  if ((res.dip.min_MHz < min(freq_MHz))||(res.dip.min_MHz > max(freq_MHz)))
    fprintf('\nERR: suspected bad fit (ctr outside sample range)\n');
    ers.err=1;
    return;
  end

  res.dip.min_adc = polyval(prb, res.dip.min_MHz);
  res.dip.halfwid_MHz = sqrt(prb(2)^2-4*prb(1)*(prb(3)-fall_mid))/prb(1);
  if (~isreal(res.dip.halfwid_MHz))
    fprintf('ERR: no intersection of fall_mid with parabola');
  end
%  res.dip.halfwid_MHz = 2*sqrt(-log(0.5)*2*prb(3));


  if (~pl(1))
    res.err=1;
    fprintf('ERR: slope of falling edge of gas dip is zero!\n');
    return;
  end



  fall_slope_adcpMHz = pl(1);
  l1=[];
  while(i_e-i_s>2)
%   fprintf('idxs %d to %d\n', i_s, i_e);
    xx = freq_MHz(i_s):freq_MHz(i_e);
%   fprintf('freq %g to %g\n', xx(1), xx(end));
    yy = polyval(pl, xx);
    % errs = horizontal dist from linear fit to each point
    err_MHz = ((gas(i_s:i_e)-pl(2))/pl(1) - freq_MHz(i_s:i_e));
    err_MHz = err_MHz * opt.MHz_per_xunits;
 %  fprintf('lin fit err max %.3f std %.3f MHz\n', max(abs(err_MHz)), std(err_MHz));
    if (opt.plot_fall)
      if (isempty(l1))
        l1 = line(xx,yy,'Color','magenta');
      else
        set(l1,'XData', xx, 'YData', yy);
      end
    end
%  plot(i_s:i_e,err_MHz,'.');
%    ylabel('err (MHz)');
    if (max(abs(err_MHz))<20)
      break;
    end
    if (abs(err_MHz(end))>abs(err_MHz(1)))
      i_e=i_e-1;
    else
      i_s=i_s+1;
    end
  end



  if (opt.plot_fall)
    'OPT PLOT FALL'
    % highlight the falling edge sample points in red
    plot(freq_MHz(i_s:i_e), gas(i_s:i_e),'.','color','red');

    % plot straight fit to falling edge in magenta
    yy = polyval(pl, freq_MHz(i_s:i_e));
    plot(freq_MHz(i_s:i_e), yy, '-', 'color', 'magenta');
    pause();
  end


  % plot([1 1]*ctr_MHz, [fall_lo fall_hi], 'color', 'red');
  if (pl(1))
    mid_MHz = (fall_mid - pl(2)) / pl(1);
  else
    mid_MHz = 0;
  end

  res.err = 0;
  res.fall.mid_MHz  = mid_MHz;
  res.fall.mid_adc  = fall_mid;
  res.fall.hi_adc   = round(fall_hi);
  res.fall.lo_adc   = round(fall_lo);
  res.fall.slope_adcpMHz = pl(1);


  gas_mx = max(gas);
  idxs = find(abs(freq_MHz-res.dip.min_MHz)<=res.dip.halfwid_MHz*2);
  if (length(idxs)<4)
    res.err=1;
    fprintf('ERR: only %d points for gaus fit\n', length(idxs));
    return;
  end
  


  fg_opt.dbg=opt.dbg
  fg_opt.m = res.dip.min_MHz;
  fg_opt.offset = min(gas_mx-gas(idxs));
  [a, m, s, o, rmse]=fit.gaussian(freq_MHz(idxs), gas_mx-gas(idxs), fg_opt);
  res.gauss.m=m;
  res.gauss.s=s;
  fita = a/(sqrt(2*pi)*s);
  res.gauss.fita = fita;
  res.gauss.o=gas_mx - o;
  res.gauss.rmse = rmse;
  res.gauss.hh_wid_x = 2*sqrt(-log(0.5)*2*s^2);
  res.gauss.hh_slope_adcpx = fita*res.gauss.hh_wid_x/(4*s^2);
  if (opt.plot_gauss)
    ncplot.init();
    plot(freq_MHz(idxs), gas(idxs), '.');
    xx = linspace(min(freq_MHz(idxs)), max(freq_MHz(idxs)));
    yy = res.gauss.o - res.gauss.fita * exp(-(xx-m).^2/(2*s^2));
    plot(xx, yy, '-', 'Color', 'green');
    xlim([min(xx) max(xx)]);
  end

  fl_opt.dbg=0;
  fl_opt.weighting='n';
  [a m g o rmse]=fit.lorentzian(freq_MHz(idxs), gas_mx-gas(idxs), fl_opt);
  res.lorentz.m=m;
  res.lorentz.o=gas_mx - o;
  res.lorentz.g=g;
  res.lorentz.a=a;
  res.lorentz.rmse=rmse;
  if (opt.plot_gauss)
    xx = linspace(min(freq_MHz(idxs)), max(freq_MHz(idxs)));
    yy = res.lorentz.o - a*g./(pi*((xx-m).^2+g^2));
%ncplot.init;
%plot(freq_MHz(idxs), gas(idxs), '.');
%hold('on');
    plot(xx, yy, '-', 'Color', 'magenta');
%    uio.pause;
  end


  % About idx_s and idx_e:
  % In the case when multiple measurements were made at the same setting,
  % num_iter will be greater than one.  We assume all these are adjacent
  % together in the data vector in some little "range". Given any index,
  % idx_s returns the index associated with iter 1 (at the start of the
  % range), and idx_e returns the index associated with the highest iter
  % value. (at the end of the range)

  % nested
  function idx = idx_s(idx)
    idx = floor((idx-1)/num_iter)*num_iter+1;
  end  

  % nested
  function idx = idx_e(idx)
    idx = idx_s(idx)+num_iter-1;
  end  

  function v = gas_mean(idx)
    % mean of all gas values measured in the "range" that idx is in.
    v = mean(gas(idx_s(idx):idx_e(idx)));
  end

end

