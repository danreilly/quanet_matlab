function p2
  import nc.*
  tvars = nc.vars_class('tvars.txt');

  dbg_each_seg_fit=0
  plot_lorentzian_fit=0;
  calc_linewid = 0;
  beat_with_self = 1;
  dbg=0;

  known_lwid_Hz = 210e3;
  
  
  fname='';
  
  dflt_fname_var = 'fname';
  fn_full = tvars.get(dflt_fname_var,'');
  max_fnum = 0; % tvars.get('max_fnum', 0);
  if (iscell(fn_full))
    str = fn_full{1};
  else
    str = fn_full;
  end
  [n is ie] = fileutils.num_in_fname(str);
  if (ie>0)
    places = ie-is+1;
    fmt = ['%s%0' num2str(places) 'd%s'];
    fn2 = sprintf(fmt, str(1:is-1), n+1, str(ie+1:end));
    if (exist(fn2, 'file') && (max_fnum<=n))
      fprintf('prior file:\n  %s\n', str);
      fprintf('but newer file exists:\n  %s\n', fn2);
      fprintf('use it?');
      if (nc.uio.ask_yn(1))
        tvars.set('fname', fn2);
        tvars.set('max_fnum', n+1);
        fname =fn2;
      end
    end
  end
  if (isempty(fname))  
    fname = tvars.ask_fname('data file', 'fname');
  end
  pname = fileparts(fname);
  pname_pre = fileparts(str);
  if (~strcmp(pname, pname_pre))
    'new dir'
    tvars.set('max_fnum', 0);
  end
  tvars.save();


  
  fname_s = fileutils.fname_relative(fname,'log');

  mvars = nc.vars_class(fname);
  use_lfsr = mvars.get('use_lfsr',1);
  num_itr  = mvars.get('num_itr',1);
  tx_0 = mvars.get('tx_0',0);
  if (tx_0)
    do_eye=1;
  end
  hdr_pd_samps = mvars.get('probe_pd_samps', 0);
  if (~hdr_pd_samps)
    hdr_pd_samps = mvars.get('hdr_pd_samps', 2464);
  end
  hdr_qty = mvars.get('probe_qty', 0);
  if (~hdr_qty)
    hdr_qty      = mvars.get('hdr_qty', 0);
  end
    
  hdr_len_bits = mvars.get('probe_len_bits', 0);
  if (~hdr_len_bits)
    hdr_len_bits = mvars.get('hdr_len_bits', 256);
  end
  osamp = mvars.get('osamp', 4);

  other_file = mvars.get('data_in_other_file',0);
  if (other_file==2)
      s = fileutils.nopath(fname);
      s(1)='d';
      s=fileutils.replext(s,'.raw');
      fname2=[fileutils.path(fname) '\' s];
      fprintf(' %s\n', fname2);
      fid=fopen(fname2,'r','l','US-ASCII');
      if (fid<0)
        fprintf('ERR: cant open %s\n', fname2);
      end
      [m cnt] = fread(fid, inf, 'int16');
      fclose(fid);
      % class(m) is double
      m = reshape(m, 2,cnt/2).';
        % 'DBG here'
        % m = reshape(m,cnt/2,2);      
  elseif (other_file==1)
      s = fileutils.nopath(fname);
      s(1)='d';
      fname2=[fileutils.path(fname) '\' s];
      fprintf('  also reading %s\n', fname2);
      fid=fopen(fname2,'r');
      [m cnt] = fscanf(fid, '%g');
      fclose(fid);
      m = reshape(m, 2,cnt/2).';
  else
      m = mvars.get('data');
  end
  fname_s = fileutils.fname_relative(fname,'log');  
  tvars.save();  

  fsamp_Hz = 1.233333333e9;

  l=size(m,1);
  fprintf('num raw samples %d\n', l);
  t_ms = 1e3*(0:(l-1)).'/fsamp_Hz;

  a1=double(m(:,1));

  if (0)
    plot(t_ms, [a1 a2],'-');
    xlabel('time (ms)');  
  end

  
%  zoom_bw_Hz =2e6;
  zoom_bw_Hz =20e6;

  max_pd_us = round(t_ms(end)*1000/2);
  
  pds_us = 10:10:min(100,max_pd_us);
  pds_us = .2;
  pds_us = 1;
%  pds_us = 90;
  pds_l = length(pds_us);
  if (calc_linewid)
    lws_Hz = zeros(pds_l,1);
  end




  
  fprintf('integration periods from %d to %d\n', pds_us(1), pds_us(end));
  for pdi = 1:pds_l  % :100:t_ms(end)*1000
    pd_us = pds_us(pdi);
    fprintf('pd %d us\n', pd_us);
    nsamp = floor(pd_us*1e-6 * fsamp_Hz);

    freqs_Hz = 0;
    lorentz_ss= 0;
    fft_phs_rad = 0;
    offs_s = 0;

    zoom_bw_idx=round(zoom_bw_Hz * nsamp/fsamp_Hz);
    ncplot.init();

    [co,ch,cq]=ncplot.colors();


    x_all=[];
    y_all=[];

    freqs_l = floor(l/nsamp)
    offs_s      =zeros(freqs_l,1);
    freqs_Hz    =zeros(freqs_l,1);
    fft_phs_rad =zeros(freqs_l,1);
    lorentz_wids=zeros(freqs_l,1);

    for fi = 1:freqs_l
      opt.no_window=0;
      opt.no_plot=1;
      res = ncplot.fft(a1((fi-1)*nsamp+(1:nsamp)), 1/fsamp_Hz, opt);
      offs_s(fi)      = (fi-1)*pd_us*1e-6; % start of segment
      freqs_Hz(fi)    = res.main_freq_Hz;
      fft_phs_rad(fi) = res.main_ph_rad;


   %      ncplot.txt(sprintf('freq %sHz', uio.sci(res.main_freq_Hz)));
%      title(sprintf('offset %s',uio.dur((fi-1)/fsamp_Hz)));
%      uio.pause();


      if (calc_linewid)
      hbw=round(zoom_bw_idx/2);
      rng_lim = res.main_freq_idx+[-hbw hbw];
      rng_lim(2) = min(rng_lim(2), length(res.x_Hz));
      rng_lim(1) = max(rng_lim(1), 1);
      if (diff(rng_lim)<4)
	fprintf('ERR: small rng %d.  change zoom_bw_idx\n', diff(rng_lim));
	return;
      end
      rng = rng_lim(1):rng_lim(2);

      xs = res.x_Hz(rng);
      ys = res.y_dBc(rng);

      if (0)
        gopt.weighting='y';
        gopt.m = res.main_freq_Hz;
        gopt.dbg=1;
	[a m s o rmse] = fit.gaussian(xs, ys, gopt);
      else
	slopt.dbg = dbg_each_seg_fit;
	slopt.m = res.main_freq_Hz;
	slopt.init_y_thresh = .50;
	slopt.weighting='y';
	[a m g o rmse] = fit.lorentzian(xs, ys, slopt);
	 fprintf('wid %sHz\n', uio.sci(2*g,1));
	lorentz_wids(fi) = 2*g;
      end	
      x_all = [x_all; xs-m];
      y_all = [y_all; ys];
      
      if (0)
        plot(xs-m, ys, '.', 'Color',cq(1,:));
        xf = linspace(xs(1),xs(end));
	if (0)
  	  yf = a/(sqrt(2*pi)*s)*exp(-(xf-m).^2/(2*s^2)) + o;
	else
          yf = a*g./(pi*((xf-m).^2+g^2)) + o;
	end
        plot(xf-m, yf,'Color','green');
	uio.sci(m)
	uio.pause();
      end	
      end
	     %      xlim(res.rbw_Hz * (res.main_freq_idx+[-hbw hbw]));
%      xlim(res.rbw_Hz * [-hbw hbw]);
      %      uio.pause();

    end % for fi

    
    if (calc_linewid && freqs_l)

      ll = length(x_all);
      if (ll > 4000)
	step = round(ll/2000);
        x_all = x_all(1:step:ll);
        y_all = y_all(1:step:ll);
	if (dbg)
	  fprintf('to avoid mem err, decimating peaks by %d to %d samples total\n', step, length(x_all));
	end
      end
%      save('tmp.mat','x_all','y_all','-mat');
%      fprintf('saved tmp.mat');
      
      lopt.dbg=0; % (pd_us==60);
      lopt.weighting='n';
      lopt.m=0;
      lopt.fwhm = mean(lorentz_wids);

		%      lopt.hh_wid = hh_wid;

      [a m g o rmse] = fit.lorentzian(x_all, y_all, lopt);

      fwhm_Hz = 2*g;
      if (plot_lorentzian_fit)
	ncplot.init();
	plot(x_all, y_all, '.', 'Color',cq(1,:));
        % Plot lorentzian fit to all fft segments
	xf = linspace(-zoom_bw_Hz/2,  zoom_bw_Hz/2);
	yf = a*g./(pi*((xf-m).^2+g^2)) + o;
	plot(xf-m, yf,'Color','red');
		  %     line([-.5 .5]*zoom_bw_Hz,[o o],'Color','red');
	ncplot.txt(sprintf('integration %s', uio.dur(pd_us*1e-6)));
	ncplot.txt(sprintf('Lorentzian FWHM %sHz', ...
			   uio.sci(fwhm_Hz,1)));
	xlabel('freq (Hz)');
	xlim([-.5 .5]*zoom_bw_Hz);
	ylabel('power (dBrel)');
	ncplot.title(fname_s);
	uio.pause();
      end
      % given lw1 and lw2, the combined lw is
      %  sqrt(lw1^2 + lw2^2)
      pure_lwid_Hz = 210e3;
      if (beat_with_self)
        lws_Hz(pdi) = fwhm_Hz/sqrt(2);
      else
	lws_Hz(pdi) = sqrt(fwhm_Hz^2-known_lwid_Hz^2);
      end
    end

    
    if (freqs_l && (pds_l==1))
      
      offs_us = offs_s*1e6;
      offs_us(1:4)
      ncplot.init();
      ncplot.subplot(3,1);

      % plot frequency over time
      ncplot.subplot();
      plot(offs_us, freqs_Hz/1e6,'.','Color',cq(1,:));
      p = fit.polyfit(offs_us, freqs_Hz, 1); % Hz/us
      ch_mean_Hzpus = p(1);
      %      plot(1:freqs_l, freqs_Hz/1e6,'.','Color',ch(1,:));
      sl = 3;
      frates_MHzpus=zeros(length(freqs_Hz)-(sl-1),1);
      pmax=0;
      for k=0:(freqs_l-sl)
	srng = (1:sl)+k;
	p = fit.polyfit(offs_us(srng), freqs_Hz(srng)/1e6,1); % MHz/us
	frates_MHzpus(k+1)=p(1);
	if ((k==0)||(abs(p(1))>pmax))
	  pmax = abs(p(1));
	  k_best = k;
	  p_best = p;
	end
      end
      srng = (1:sl)+k_best;
      fx=offs_us([srng(1) srng(end)]);
      fy=polyval(p_best, fx);
      line(fx,fy,'Color','red');
      ch_max_Hzpus = p_best(1)*1e6;
      ncplot.txt(util.ifelse(beat_with_self, ...
			     'two identical lasers', ...
			     'two different lasers'));
      ncplot.txt(sprintf('integration pd %s', uio.dur(nsamp/fsamp_Hz)));
      ncplot.txt(sprintf('fastest drift %sHz/us', uio.sci(ch_max_Hzpus, 1)));
      ncplot.txt(sprintf('   mean drift %sHz/us', uio.sci(ch_mean_Hzpus, 1)));      
%    ncplot.txt(sprintf('range %sHz', uio.sci(max(freqs_Hz)-min(freqs_Hz))));
      xl=[offs_us(1) offs_us(end)];
      xlim(xl);
      xlabel('time (us)');
      ylabel('freq (MHz)');
      ncplot.title({fname_s; 'beat frequency drift'});


      freqs_mean_Hz = mean(freqs_Hz);

      
      if (0) % USUAL STUFF
	y = freqs_Hz(:)-freqs_mean_Hz;
        
	if (1) % Allen Variance
	  m = 2; % num intervals used to calc m-sample var
	  opt_vary_m=0;
	  dfs_l = freqs_l-m+1;
	  avar = zeros(dfs_l,1);
	  for k=1:dfs_l
	    if (opt_vary_m)
	      m=freqs_l-(k-1);
	    end
	    df = y(1:m)-y((k-1)+(1:m));
	    avar(k)= m/(m-1) * (mean(df.^2)-mean(df)^2);
	  end
          ncplot.subplot();
	  plot((0:dfs_l-1)*pd_us, sqrt(avar)/1000, '.-');
	  line(xl,[1 1]*27, 'Color','red');	  
	  xlim([0 (freqs_l-1)*pd_us]);
	  xlabel('period (us)');
	  ylabel('deviation (kHz)');
          ncplot.title({fname_s; ...
			sprintf('%s-sample Allan Deviation', ...
				util.ifelse(opt_vary_m,'M','2'))});
	end
	
	if (0) % Freq Noise PSD using autocorr
  	  end_l = ceil(1e-3 / (pd_us*1e-6)); % samps at end
	  seg_l = freqs_l - end_l;
	  acorr_l = end_l+1;

	  k=floor(acorr_l/2);
	  acorr=zeros(acorr_l,1);
	  for k=0:(acorr_l-1)
	    acorr(k+1)=mean(y(1:seg_l).*y(k+(1:seg_l)));
	  end
	  if (0) % double-check autocorr
	    ncplot.subplot();
	    plot((0:(acorr_l-1))*pd_us, acorr/1e12,'.');
	    xlabel('delay (us)');
	    ylabel('freq (MHz^2)');
	    title('autocorrelation of freq change');
          end
          ax = ncplot.subplot();
	  psdopt.plot_y=1;
	  ncplot.fft(acorr, pd_us*1e-6, psdopt);
	  title('Freq Niose Power Spectral Density (autocorr method)');
	  set(ax, 'YScale', 'log')
          xlabel('freq (Hz)');
	  ylabel('noise density (Hz^2 / Hz)');
        end
	
	ax=ncplot.subplot();
	if (0)
  	  lsdopt.plot_y2=1;
	  ncplot.fft(freqs_Hz-freqs_mean_Hz, pd_us*1e-6, lsdopt);
	  ylabel('PSD ( Hz^2 / Hz )');
	else
	  lsdopt.plot_y=1;
	  ncplot.fft(freqs_Hz/1000, pd_us*1e-6, lsdopt);
	  line([.001 1]/(pd_us*1e-6), [1 1]*27, 'Color','red');
	  ylabel('LSD ( kHz / sqrt(Hz) )');
	end
	set(ax, 'YScale', 'log','XScale','log');
        xlabel('freq ( Hz )');
	title('Frequency Noise Linear Specral Density (fft of freqs)');	
	
        return;	
      elseif (0)
        ncplot.subplot();

	fdiff_max = zeros(freqs_l-1,1);
	fdiff_rms = zeros(freqs_l-1,1);
	for k=1:freqs_l-1 % diff across k samples
	  sl=freqs_l-k;
	  tmp=(freqs_Hz(k+(1:sl))-freqs_Hz(1:sl))/2; % single laser
	  fdiff_max(k) = max(abs(tmp));
          fdiff_rms(k) = sqrt(mean(tmp.*tmp));
	end
        plot(offs_us(1:freqs_l-1)+pd_us, [fdiff_max fdiff_rms]/1000, '.');

%        plot(offs_us(1:freqs_l-sl+1), abs(frates_MHzpus) * 1e3, '.','Color',ch(1,:));
	line(xl,[1 1]*27, 'Color','red');
%	line(xl,[1 1]*27*2/1000,'Color','red');
        xlim(xl+pd_us);
        ncplot.txt(sprintf('integration pd %s', uio.dur(nsamp/fsamp_Hz,1)));
        xlabel('delay (us)');
        ylabel('single laser freq diff (kHz)');
	legend({'max'; 'rms'},'Location','SouthEast');
        ncplot.title({fname_s; 'single laser frequency drift'});



	
%        ncplot.subplot();
%	ffopt.dbm=1;
%	ncplot.fft(freqs_Hz, pd_us*1e-6, ffpot);
%	xlabel('freq (Hz)');
%        uio.pause(); 
      else
          'PHASE VS TIME FIND LOST DATA'
        % Plot fft phase vs time
	ncplot.subplot();
	deg = util.mod_unwrap(fft_phs_rad*180/pi,360);
	[mxv mxi]=max(abs(diff(deg)));
	mxi=mxi+1
	plot(offs_us, deg, '.', 'Color',ch(1,:));      
	plot(offs_us(mxi), deg(mxi), '.', 'Color','red');
	xlim([offs_us(1) offs_us(end)]);
	xlabel('time (us)');
	ylabel('phase (deg)');
	ncplot.title('phase drift');

        % Look for lost data
        ncplot.subplot();
	
				% largest phase step
	if (0)
        at_us = offs_us(mxi);
        fprintf('anomoly time %g us\n', at_us);
        fprintf('        jump %g deg\n', mxv);
        idxs = round( (offs_us(mxi) + [-2 2])/1e6 * fsamp_Hz);
        rng = idxs(1):idxs(2);
        fprintf('idx: %d:%d = %d\n', min(rng), max(rng),  max(rng)-min(rng))
        fprintf('time_us %.1f  %.1f\n', rng(1)/fsamp_Hz*1e6, rng(end)/fsamp_Hz*1e6)
        plot((rng-1).'/fsamp_Hz*1e6, a1(rng), '.');
        plot([1 1]*at_us, [-1 1]*2000,'-','Color','red');
        end
	
	% largest freq step
        [mxv mxi]=max(abs(diff(freqs_Hz)));
        mxi=mxi+1;
        at_us = offs_us(mxi);
        fprintf('anomoly time %g us\n', at_us);
        fprintf('        jump %g deg\n', mxv);
        idxs = round( (offs_us(mxi) + [-2 2]*pd_us )/1e6 * fsamp_Hz);
        rng = idxs(1):idxs(2);
        plot((rng-1).'/fsamp_Hz*1e6, a1(rng), '.');
        plot([1 1]*at_us, [-1 1]*2000,'-','Color','red');
      
	% largest change in signal (works for slow sin)
	if (0)
        [mxv mxi]=max(abs(diff(a1)));      
        rng = (-50:50)+mxi;
        plot((rng-1).'/fsamp_Hz*1e6, a1(rng), '.');
        at_s = mxi/fsamp_Hz
        fprintf('idx: %d = %s\n', mxi, uio.dur(at_s,6));
        plot([1 1]*at_s*1e6, [-1 1]*2000,'-','Color','black');
        end
	
        xlabel('time (us)');
        ylabel('signal (adc)');
        ncplot.title('potential anomolies');
      
      uio.pause();
      end
    end
  end
  
  calc_linewid
  pds_l
  if (calc_linewid && (pds_l>1))
    ncplot.init();
    plot(pds_us, lws_Hz/1000, '.-');
    if (~beat_with_self)
      ncplot.txt(sprintf('used known linewid %sHz', uio.sci(known_lwid_Hz,1)));
    end
    ncplot.txt(sprintf('zoom bw %sHz', uio.sci(zoom_bw_Hz,1)));
    xlabel('integration pd (us)');
    ylabel('linewidth (kHz)');
    ncplot.title(fname_s);  
  end  
end


