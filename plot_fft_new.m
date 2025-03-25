%  plot_fft
%  8/29/2017 Dan Reilly

function results = plot_fft(tsamp_s, sig, r_Ohms, frange_Hz, opt)
% plot_fft(tsamp, sig, r_Ohms)
% plot_fft(tsamp, sig, r_Ohms, frange_Hz)
% plot_fft(tsamp, sig, r_Ohms, frange_Hz, opt)
%
% desc:
%   plots spectral power density, similar to that of a spectrum analyzer.
%   Parts of analysis conform to IEEE 1057.
% inputs:
%   tsamp_s: sample time in seconds
%   sig: signal in volts (or amps)
%   r_Ohms: load resistance in Ohms (or 1/Ohms). Like input resistance of
%           spectrum analyzer.  If r_Ohms=1, results are mean-square (unitless).
%   frange_Hz: freq range over which to plot and analyze. frange_Hz=[flo_Hz fhi_Hz]
%   opt: structure of options.  You don't have to fill in all fields,
%        because the ones you leave out will get default values.
%     opt.spurs_to_plot: number of spurs to plot  
%     opt.plot: 0=dont plot, 1=plot (default)
%     opt.anal: 0=just plot (default), 1=analyze (might takes longer)
%     opt.hann: 1=use hann window, 0=dont (default)
%     opt.tone_bw_Hz: max bandwidth of an individual tone.  Used when
%               calculating the power of an individual tone for purpose
%               of IMD analysis.  Default: RBW_HZ*10.
%     opt.nf_range: range over which to calculate noise floor. [flo_Hz fhi_Hz]
%                   by default this is frange_Hz.  TRY NOT TO USE THIS
%     opt.imd_tones: 1x2 matrix of tones being used for purpose of
%                    intermodulation distortion analysis.   
% outputs:
%   results: structure
%     results.nf_W: noise floor in Watts
%     results.tot_W: total power in frange_Hz in Watts
%     results.noised_WpHz = nf_W/(results.rbw_Hz);
%     results.spurs = nx3 matrix. each row: [freq_Hz pwr_W phase_rad]
% Note: mean sq pwr of: V*cos(wt)=V^2/2
%       across R: V^2/(2R)

  oldway=1;


  if (any(isnan(sig)))
    error('plot_fft(): sig contains NaN');
  end
  if (~r_Ohms)
    error('plot_fft(): r_Ohms cannot be zero');
  end    
  
  sig_l = length(sig);
  if (nargin<4)
    frange_Hz=[];
  end
  opt.foo = 1; % create if doesnt exist
  opt = set_if_undef(opt, 'plot', 1);
  opt = set_if_undef(opt, 'anal', 0);
  opt = set_if_undef(opt, 'nf_range', frange_Hz);
  opt = set_if_undef(opt, 'verbose', 0);
  opt = set_if_undef(opt, 'hann', 0);       % use hann window
  opt = set_if_undef(opt, 'tone_bw_Hz', 0); % bw assumed by analysis
  opt = set_if_undef(opt, 'imd_tones', []);
  opt = set_if_undef(opt, 'units', 'W');
  opt = set_if_undef(opt, 'spurs_to_plot', 0);
  opt = set_if_undef(opt, 'nowarn_imdtonediff', 0);
  opt = set_if_undef(opt, 'no_floor', 0);

  nfft2 = floor(sig_l/2)+1;
  sig_mean = mean(sig);
  sig = sig - sig_mean;
  if (opt.hann)
    % Hann window to reduce "leakage" between bins (see IEEE 1057 4.1.6)
    % Then dan added sqrt(8/3) so power is consistent after windowing
    sig = sig .* (.5-.5*cos(2*pi*(0:sig_l-1).'/sig_l)) * sqrt(8/3);
  end

  f_n = fft(sig);

  % ptot = (f_n'*f_n)/sig_l^2;  % Parseval's Theorum


% fprintf('plot_fft(): full spectrum parseval result = %g\n', ptot + (sig_mean'*sig_mean));
% fprintf('plot_fft(): DC pwr = %g\n', (sig_mean'*sig_mean));

  if (oldway)
    fprintf('plot_fft(1): WARN: OLD WAY\n');
    f_r=abs(f_n(1:nfft2));  % only look at magnitude of half of it
    fft_pwr = f_r.*f_r/nfft2/sig_l/r_Ohms;
  else
    fft_pwr = conj(f_n(1:nfft2)).*f_n(1:nfft2)/sig_l^2/r_Ohms;
    k=sig_l-nfft2-1;
    fft_pwr(2+(0:k)) = fft_pwr(2+(0:k)) ...
		       + conj(f_n(sig_l-(k:-1:0))).*f_n(sig_l-(k:-1:0))/sig_l^2/r_Ohms;
  end
  fft_pwr(1)=fft_pwr(1) + (sig_mean'*sig_mean)/r_Ohms;

  results.tot_W = sum(fft_pwr); % ptot +(sig_mean'*sig_mean);


%f_r2 = conj(f_n(1:nfft2)).*f_n(1:nfft2);
%k=sig_l-nfft2;
%f_r2(2:2+k-1)=f_r2(2:2+k-1)+(conj(f_n(nfft2+1:end)).*f_n(nfft2+1:end));
%  fft_ph=angle(f_n(1:nfft2)); % for now just angle of positive freqs
%'fft ptot'
%  ptot=((f_r'*f_r)/nfft2)/sig_l;  % Parseval's Theorum
%ptot2 = (f_r2'*f_r2)/sig_l^2;  % Parseval's Theorum
%fprintf('plot_fft(): half-spectrum parseval ptot = %g\n', ptot);
%fprintf('plot_fft(): new half-spectrum parseval result = %g\n', ptot2)
%  (f_n(1:nfft2)'*f_n(1:nfft2))/sig_l^2,(f_n((nfft2+1):end)'*f_n((nfft2+1):end))/sig_l^2);
  %     = sum(fft_pwr)
  % ideally equal to mean-sq-pwr=(sig'*sig)/sig_l,
  % but may be numerically different if there aren't many samples.

  freqs_Hz=(0:nfft2-1).'/(sig_l*tsamp_s);

%  full_freqs_Hz=(nfft2-1-(sig_l-1):nfft2-1).'/(sig_l*tsamp_s);

  yl = [1e-30 1];
  



%  'pwr density if white'
%   sum(fft_pwr)/length(fft_pwr)

  results.rbw_Hz = 1/(sig_l*tsamp_s);
  

  if (~isempty(frange_Hz))
    i_s = find(freqs_Hz>=frange_Hz(1),1);
    if (isempty(i_s))
      error(sprintf('plot_fft: frange_Hz(1)=%g is beyond nyquist', frange_Hz(1)));
    end
    i_e = find(frange_Hz(2)<=freqs_Hz,1,'last');
    if (isempty(i_e))
      error(sprintf('plot_fft: frange_Hz(2)=%sHz is beyond nyquist of ', ...
                    uio.sci(frange_Hz(2),6),uio.sci(1/tsamp_s/2,6)));
    end

  else
    i_s = 1;
    i_e = nfft2;
  end

  
  if (opt.plot)
    myplot.init();

    myplot.txt(0.05, 0.9, 0.09);
    co= myplot.colors_qtr;
    %    f_rfs = 20*log10(f_r/f_fs);
    semilogy(freqs_Hz(i_s:i_e), fft_pwr(i_s:i_e), 'Color', co(1,:));
    title('fft');
    myplot.txt(sprintf('fsamp %sHz  RBW = %sHz', ...
                       uio.sci(1/tsamp_s,3), uio.sci(results.rbw_Hz,3)));
    
    if (~isempty(frange_Hz))
%      myplot.txt(sprintf('inview max %g  mean %g', max(fft_pwr(i_s:i_e)), mean(fft_pwr(i_s:i_e))));
      xlim(frange_Hz);
    else
%      myplot.txt(sprintf('max %g  mean %g', max(fft_pwr), mean(fft_pwr)));
      xlim([min(freqs_Hz) max(freqs_Hz)]);
    end
    xlabel('freq (Hz)');
    ylabel(sprintf('pwr (%s)', opt.units));
    ylim(yl);
%      uio.pause;
  end

  results.imd_dbfs  = -120;


  if (opt.tone_bw_Hz)
    bins_per_spur = ceil(opt.tone_bw_Hz/results.rbw_Hz);
  else
    bins_per_spur = 10;
  end
  if (bins_per_spur > nfft2/10) % sanity check
    if (opt.tone_bw_Hz)
      tone_bw_desc = 'supplied';
    else
      tone_bw_desc = 'default';
    end
    fprintf('ERR: plot_fft(): %s opt.tone_bw_Hz is larger than one tenth of spectrum!\n');
  end
  
  if (opt.anal)
    full2tone_ms = pi^2/2; % mean sq
    
%    nf = gausfilt(1, fft_pwr, 1/1000); % 1/10000 takes too long
    
%    foo = zeros(nfft2,1);
%    foo(idx)=1;
%    foo = conf(foo, ones(bins_per_spur,1), 'same');

    use=ones(nfft2,1);



    % try removing all single spikes
    log_fft_pwr = log(fft_pwr(i_s:i_e));
    log_fft_pwr_std = std(log_fft_pwr);
log_fft_pwr_std
    idxs = find(diff(log_fft_pwr) > log_fft_pwr_std*3)+1;
%    if (opt.verbose)
      fprintf('found %d/%d bins of pwr spikes = %.2f%%\n', length(idxs),i_e-i_s+1, ...
length(idxs)*100/(i_e-i_s+1));

%    end
    if (1)
      plot(1:(i_e-i_s+1), log_fft_pwr, '.');
      hold('on');
      plot(idxs, log_fft_pwr(idxs),'.', 'Color', 'red');
      uio.pause;
    end
    idxs = idxs + i_s-1;

    nf_use = zeros(nfft2,1);
    nf_use(idxs)=1;
    nf_use = round(1-min(conv(nf_use, ones(bins_per_spur,1), 'same'),1));
    nf_pwr = fft_pwr .* nf_use;
%    plot(nf_pwr(i_s:i_e),'.'); uio.pause;
    if (~isempty(opt.nf_range))
      fprintf('plot_fft(): WARN: computing noise floor for different range than displayed\n');
      i1 = max(min(round(opt.nf_range(1)*sig_l*tsamp_s)+1,nfft2), 1);
      i2 = max(min(round(opt.nf_range(2)*sig_l*tsamp_s)+1,nfft2), 1);
    else
      i1=i_s;
      i2=i_e;
    end
    nf_W = sum(nf_pwr(i1:i2))/sum(nf_use(i1:i2));
    results.nf_W = nf_W;


 % if a sinusoid is sampled and then fft taken, there will be two
 % peaks at + and - the freq, each peak at half the power of the
 % sinusoid.
% USED to be that we're not bothering to plot the negative frequencies, and
% we *double* the power of the positive frequency bins so the peaks on
% the plot correspond to the original power of the
% sinusoid.
% NOW we add the power in the negative bins to
% the positive bins and just work with the positive bins.
%    

% The noise floor is assumed to be white, so the power spectral density
% of the noise is the noise floor divided by the bandwidth of each plotted bin.
    results.noise_psd_WpHz = nf_W/(results.rbw_Hz);
    
    if (nf_W<0)
      'BUG: negative noise floor pwr'
      fprintf('any nf_use<0 = %d\n', any(nf_use < 0));
      fprintf('any fft_pwr<0 = %d\n', any(fft_pwr < 0));
      sum(nf_pwr(i1:i2))
      sum(nf_use(i1:i2))      
      fprintf('nf %g from %g to %g\n', nf_W,  freqs_Hz(i1),  freqs_Hz(i2));
    end
    
    if (opt.plot && ~opt.no_floor)
       
      line([freqs_Hz(i1) freqs_Hz(i2)], [1 1]*nf_W, 'Color','red');
      myplot.txt(sprintf('noise: floor=%.3e %s   PSD=%.3e %s/Hz', ...
                         nf_W, opt.units, results.noise_psd_WpHz, opt.units));
    end
    results.nf_dBfs = 10*log10(nf_W/full2tone_ms);
    %      results.nf_dBfs


    if (~isempty(opt.imd_tones))
      imd_tones = sort(abs(opt.imd_tones));
      df = imd_tones(2)-imd_tones(1);
      f1 = imd_tones(1)-df;
      f2 = imd_tones(2)+df;
      % interpolate holes in noise floor in region didx
      fill_nf(round(mean([f1 f2])*sig_l*tsamp_s), round(4*df*sig_l*tsamp_s));

      
      i1 = max(min(round(imd_tones(1)*sig_l*tsamp_s)+1,nfft2), 2);
      sp = calc_spur_p(i1, bins_per_spur);
      sp1 = sp(1); % power at tone 1

      i2 = max(min(round(imd_tones(2)*sig_l*tsamp_s)+1,nfft2), 2);
      sp = calc_spur_p(i2, bins_per_spur);
      sp2 = sp(1); % power at tone 2
      tonep = max([sp1 sp2]); % max of the two
      tone_diff_pct = 100*abs(sp1-sp2)/tonep;
      if (opt.nowarn_imdtonediff && (tone_diff_pct > 0.03))
        fprintf('ERR: plot_fft(): two tones for IMD analysis are different by %.1f%%.  Using max.\n', tone_diff_pct);
        fprintf('                 (to disable this warning, set opt.nowarn_imdtonediff=1)\n');
      end
      results.tone_W = tonep; % tone power (mean sq)
%      results.tone_dbfs = 10*log10(tonep/full2tone_ms);
      if (opt.verbose)
        fprintf('   tones  %sHz, %sHz:  pwr %g = %.3f dBfs\n', ...
                uio.sci(imd_tones(1),3),uio.sci(imd_tones(2),3), ...
                tonep,  results.tone_dbfs);
      end      
      

      %      df = abs(spurs(1,1)-spurs(2,1));
      %      f1 = min(spurs(1:2,1))-df;
      %      f2 = max(spurs(1:2,1))+df;
      i1 = max(min(floor(f1*sig_l*tsamp_s)+1,nfft2), 2);
      i2 = max(min(floor(f2*sig_l*tsamp_s)+1,nfft2), 2);
      imd_l = calc_spur_p(i1, bins_per_spur);
      ip_l = imd_l(1);
      imd_h = calc_spur_p(i2, bins_per_spur);
      ip_h = imd_h(1);
      
      if (opt.verbose)
        fprintf('   imd %sHz:  pwr %g-%g = %g = %.3f dBfs\n', ...
                uio.sci(freqs_Hz(i1),3), imd_l(1), nfp_l(1), imd_l(1)-nfp_l(1), ...
                10*log10((imd_l(1)-nfp_l(1))/full2tone_ms));
        fprintf('   imd %sHz:  pwr %g-%g = %g = %.3f dBfs\n', ...
                uio.sci(freqs_Hz(i2),3), imd_h(1), nfp_h(1), imd_h(1)-nfp_h(1), ...
                10*log10((imd_h(1)-nfp_h(1))/full2tone_ms));
      end
      if (imd_l(1) > imd_h(1)) % pick the larger of the two
        imd_h = imd_l;
      end
      results.imd_W = max(ip_l, ip_h);


      myplot.txt(sprintf('tone %.3eW  IMD %.3eW', results.tone_W, results.imd_W));
      sfdr = 10*log10(results.imd_W/results.tone_W);
    else
      it = find(max(fft_pwr(i1:i2))==fft_pwr(i1:i2),1) + i1-1;
      tone_h = calc_spur_p(it, bins_per_spur);
      results.tone_W = tone_h(1);
    end

    spurs = zeros(opt.spurs_to_plot, 3); % row is: [freq_hz pwr_W phase];
    spurs_l = 0;
    med = median(fft_pwr(i_s:i_e));
    for k=1:opt.spurs_to_plot
      m = max(fft_pwr(i_s:i_e));
      if (m<=med)
        break;
      end
      idx = find(m==fft_pwr(i_s:i_e), 1)+i_s-1;
      if (isempty(idx))
        m
        i_s
        i_e
      end
      f = freqs_Hz(idx);
      % Since this is "incoherent sampling", each harmonic occupies
      % a band of frequencies.  We specify the width of this using
      % bins_per_spur. (See IEEE 1057 section 4.4.4.1.2, step h)
      ll = max(1, round(idx - bins_per_spur/2));
      ul = min(length(fft_pwr), round(idx - bins_per_spur/2) + bins_per_spur - 1);
      ps = calc_spur_p(idx, bins_per_spur);
      fill_nf(idx, bins_per_spur*50);

      if (opt.verbose)
        fprintf('spur  %sHz   pwr %g rms = %.3f dBfs\n', ...
                 uio.sci(f,6), ps(1), 10*log10(ps(1)/full2tone_ms));
      end
      
      spurs_l = spurs_l+1;
      spurs(spurs_l,1:3) = [f ps(1) ps(3)];
      
      if (k==1)
        sfdr_psig = m;
      end
%      if (0)
%        spur_ratio_db = 10*log10(spurs(2,2)/spurs(1,2));
%        %  fprintf('spur1/spur2 = %g dB\n', spur_ratio_db);
%        if (spur_ratio_db > -3)
%
%          if (opt.imd_tones)
%            df = opt.imd_tones(2)-opt.imd_tones(1);
%            f1 = opt.imd_tones(1);
%            f2 = opt.imd_tones(2);
%          else
%          
%            df = abs(spurs(1,1)-spurs(2,1));
%            f1 = min(spurs(1:2,1))-df;
%            f2 = max(spurs(1:2,1))+df;
%          end
%            i1 = max(min(floor(f1*sig_l*tsamp_s)+1,nfft2), 2);
%            i2 = max(min(floor(f2*sig_l*tsamp_s)+1,nfft2), 2);
%          % interpolate holes in noise floor in region didx
%          fill_nf(round(mean([f1 f2])*sig_l*tsamp_s), round(4*df*sig_l*tsamp_));
%          
%          imd_l = calc_spur_p(fft_pwr, use, i1, bins_per_spur) - ...
%                   calc_spur_p(nf_pwr, nf_use, i1, bins_per_spur);
%          imd_h = calc_spur_p(fft_pwr, use, i2, bins_per_spur) - ...
%                   calc_spur_p(nf_pwr, nf_use, i2, bins_per_spur);
%          
%          if (opt.verbose)
%            fprintf('   imd_l  f %g  p %g   ~ %g dBfs\n', freqs_Hz(i1), imd_l(1), 10*log10(imd_l(1)/full2tone_ms));
%            fprintf('   imd_h  f %g  p %g   ~ %g dBfs\n', freqs_Hz(i2), imd_h(1), 10*log10(imd_h(1)/full2tone_ms));
%          end
%
%          if (imd_l(1) > imd_h(1))
%            imd_h = imd_l;
%  	    % fprintf('pick left\n');
%          end
%          % use max here so we hit an apparent noise floor.
%          % I have to use something.
%          results.imd_dbfs  = 10*log10(max(imd_h(1),nf_W)/full2tone_ms);
%
%        end
%      end
      
      fft_pwr(ll:ul)=0;
      use(ll:ul)=0;
    end

    snfr = results.tone_W/results.nf_W;
    results.snr = snfr;

    if (opt.plot)
      hold('on');
      if (0)
        'DBG SNR'
        results.tone_W
        results.nf_W
        snfr
      end
      
      myplot.txt(sprintf('SNR %.3e = %.1fdB (N is noise floor)', snfr, 10*log10(snfr)));

 %      line(freqs_Hz, fft_pwr, 'Color', 'green');
%      line(freqs_Hz, nf_pwr, 'Color', 'red');
%      title('spurs removed');
      if (opt.spurs_to_plot)
        for k=1:spurs_l
          myplot.txt(sprintf('spur %d: %sHz %.3g W  %.3g rad', k, uio.sci(spurs(k,1),3), spurs(k,2), spurs(k,3)));
        end
      end
%      mean([spurs(2,2) spurs(1,2)])
      if (~isempty(opt.imd_tones))
        myplot.txt(sprintf('SFDR %.2f dB', sfdr));      
      end
      ylim(yl);
%      uio.pause;
    end
    results.spurs=spurs;
%    p_nf_W = sum(nf_pwr)/(nf_sum(use)*sig_l); % mean sq pwr of noise
%    results.pwr_noise_floor = p_nf_W;
%    nf = sqrt(p_nf_W * sig_l); % rms value of fft of noise
%    results.noise_floor = nf;

%    for k=1:3
%      spur_p(k,1) = max(0, spur_p(k,1) - spur_p(k,2)*nf*nf/sig_l/nfft2);
%    end
  
  end

  % nested
  function fill_nf(idx, w)
    i_l = max(idx-ceil(w/2),1);
    i_l = find(nf_use(1:i_l),1,'last'); % start on non-zero
    i_r = min(idx+ceil(w/2),nfft2);
    i_r = i_r-1+find(nf_use(i_r:end),1,'first'); % end on non-zero
    idxs = find(diff(nf_use(i_l:i_r)));
    kk=1;
    if (length(idxs)<2)
      return;
    end
    % fprintf('filling in %d holes in nf\n', length(idxs)/2);
   % myplot.init(); semilogy(nf_pwr(i_l:i_r), '.'); hold('on');
    while (kk<length(idxs))
      idx = idxs(kk);
      p1 = nf_pwr(i_l+idx-1);
      p2 = nf_pwr(i_l+idxs(kk+1));
      di = idxs(kk+1)-(idx-1);
%      size(nf_pwr)
      nf_pwr(i_l+(idx:idxs(kk+1)-1))=(p2-p1)/di*(1:di-1).'+p1;
%      size(nf_use(i_l+(idx:idxs(kk+1)-1)))
%      idxs(kk+1)-idx
      nf_use(i_l+(idx:idxs(kk+1)-1))=ones(idxs(kk+1)-idx,1);
      kk=kk+2;
    end
    % semilogy(nf_pwr(i_l:i_r),'.', 'Color', 'green'); uio.pause;
    % smooth out with lowpass. 
    nf_fcut = 10/(1+i_r-i_l); % these eqns copied from gausfilt()
    sigma = 1/(2*pi*nf_fcut/sqrt(2*log(sqrt(2))));
    nf_ord = ceil(sigma * sqrt(-2*log(.01))*1 * 2); % need to know this
%    nf_ord
    nf_flt = gausfilt(1, nf_pwr(i_l:i_r), nf_fcut, nf_ord);
    di = ceil(nf_ord/2); % half of ord on each end is garbage.
    nf_pwr(i_l+di:i_r-di) = nf_flt(di+1:end-di);
%    semilogy(nf_pwr(i_l:i_r), 'Color', 'green'); uio.pause;
  end
  
  % NESTED
  function spur = calc_spur_p(idx, bins)
    % returns total mean square power of spur (plus noise floor)
    % and number of bins over which that was calculated,
    % and phase of spur
    if (isempty(idx))
      error('calc_spur_p: idx is mt');
    end
    ll = max(1, round(idx - bins/2));
    ul = min(length(fft_pwr), round(idx - bins/2) + bins - 1);
    mi = find(fft_pwr(ll:ul)==max(fft_pwr(ll:ul)),1)+ll-1;
    % subtract noise floor. why? is that an IEE thing?
    spur_W = max(sum(fft_pwr(ll:ul)) - ((bins_per_spur-1)*nf_W), nf_W);
    spur = [spur_W sum(use(ll:ul)) angle(mean(f_n(ll:ul)))];
  end
  
%  function spur = calc_nf_p(idx, bins)
%    % returns total mean square power of spur (plus noise)
%    % and number of bins over which that was calculated,
%    ll = max(1, round(idx - bins/2));
%    ul = min(length(fft_pwr), round(idx - bins/2) + bins - 1);
%    spur = [sum(nf_pwr(ll:ul)) sum(nf_use(ll:ul)), 0];
%  end


end
  

function s = set_if_undef(s, fldname, val)
  if (~isfield(s, fldname))
    s = setfield(s, fldname, val);
  end
end
