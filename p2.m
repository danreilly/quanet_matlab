function p2
  import nc.*

  uio.print_wrap('p2.m\nThis plots DAQ3 captures of beat tones and analyzes frequency and phase drift and computes other metrics\n');      
  tvars = nc.vars_class('tvars.txt');


  use_i_and_w=0;
  plot_time_domain=1;
  dbg_each_seg_fit=0;
  show_each_seg_fit=0;
  plot_lorentzian_fit=1;
  plot_allan_var=0;
  calc_linewid = 1;
  beat_with_self = 1;
  find_lost_samps = 0; % used to check for lost samples.
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

  %a  l = floor(l/10);
  %  fprintf('USING ONE TENTH!\n');
  
  fprintf('num raw samples %d = %d ksamp = %s\n', l, l/1024, uio.dur(l/fsamp_Hz));
  t_ms = 1e3*(0:(l-1)).'/fsamp_Hz;

  ncplot.init();
  [co,ch,cq]=ncplot.colors();  
  a1=double(m(1:l,1));
  a2=double(m(1:l,2));

  nclip = length(find((a1==2^13-1)|(a1==-2^13))) ...
          + length(find((a2==2^13-1)|(a2==-2^13)));
  if (nclip)
    fprintf('WARNING: percent clipping %.2f%%\n', nclip*100/l);
    uio.pause();
  end
  
  %  zoom_bw_Hz =10e3;
  zoom_bw_Hz =20e6;

  max_pd_us = t_ms(end)*1000;
  
  pds_us = .5:.25:min(5,max_pd_us);
  %  pds_us = .2;
  %  pds_us = 90;
  %  pds_us = 10:10:60;
  pds_us = max_pd_us;
  pds_us = 1.5;
  pds_l = length(pds_us);
  if (calc_linewid)
    lws_Hz = zeros(pds_l,1);
  end

  



  
  fprintf('integration periods from %.1f to %.1f us\n', pds_us(1), pds_us(end));
  for pdi = 1:pds_l  % :100:t_ms(end)*1000
    pd_us = pds_us(pdi);
    fprintf('pd %.1f us\n', pd_us);
    nsamp = floor(pd_us*1e-6 * fsamp_Hz); % num samps in period

    freqs_Hz = 0;
    lorentz_ss= 0;
    fft_phs_rad = 0;
    offs_s = 0;

    zoom_bw_idx=round(zoom_bw_Hz * nsamp/fsamp_Hz);
    ncplot.init();

    if (plot_time_domain)
      ncplot.init();
      rng=(1:nsamp);
      plot(t_ms(rng), a1(rng), '.-', 'Color', cq(1,:));
      plot(t_ms(rng), a2(rng), '.-', 'Color', cq(2,:));
      ncplot.txt(sprintf('range I %d .. %d', max(a1), min(a1)));
      ncplot.txt(sprintf('      Q %d .. %d', max(a2), min(a2)));
      if (nclip)
        ncplot.txt(sprintf('CLIPPING %.2f%%', nclip*100/l), 'red');
      end
      xlabel('time (ms)');
      ylim([-1 1]*2^13);
      ncplot.title({fname_s; 'time domain plot'; sprintf('period %d', pdi)});
      uio.pause();
    end



    x_all=[];
    y_all=[];

    freqs_l = floor(l/nsamp);
    offs_s      =zeros(freqs_l,1);
    freqs_Hz    =zeros(freqs_l,1);
    fft_phs_rad =zeros(freqs_l,1);
    lorentz_wids=zeros(freqs_l,1);

    for fi = 1:freqs_l
      opt.no_window=0;
      opt.no_plot=1;

      if (use_i_and_w)
        seg = a1((fi-1)*nsamp+(1:nsamp)) + i * a2((fi-1)*nsamp+(1:nsamp));
      else
        seg = a1((fi-1)*nsamp+(1:nsamp));
      end
      
      res = ncplot.fft(seg, 1/fsamp_Hz, opt);
      offs_s(fi)      = (fi-1)*pd_us*1e-6; % start of segment
      freqs_Hz(fi)    = res.main_freq_Hz;
      fft_phs_rad(fi) = res.main_ph_rad;
      if (~opt.no_plot)
        ncplot.txt(sprintf('freq %sHz', uio.sci(res.main_freq_Hz)));
        title(sprintf('offset %s',uio.dur((fi-1)/fsamp_Hz)));
        uio.pause();
      end
      if ((pdi==1)&&(fi==1))
        fprintf('first beat freq %sHz\n', uio.sci(freqs_Hz(fi)));
      end
      if (pd_us*1e-6 < 10/freqs_Hz(fi))
          fprintf('WARN: in pd %d us, there are only %d beat periods\n', ...
                  pd_us, floor(pd_us*1e-6 * freqs_Hz(fi)));
      end

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
        %        ys = res.y_dBc(rng);
        ys = (res.f_r(rng)/max(res.f_r)).^2;

        if (0)
          gopt.weighting='y';
          gopt.m = res.main_freq_Hz;
          gopt.dbg=1;
          [a m s o rmse] = fit.gaussian(xs, ys, gopt);
        else
          slopt.dbg = dbg_each_seg_fit;
          %       	  slopt.dbg = (fi==172);
	  slopt.m = res.main_freq_Hz;
	  slopt.init_y_thresh = .50;
	  slopt.weighting='n';

          ss_l = length(xs);
          if (ss_l>10000)
            dsamp = ceil(length(xs)/10000);
            xs = xs(1:dsamp:ss_l);
            ys = ys(1:dsamp:ss_l);
          end
	  [a m g o rmse] = fit.lorentzian(xs, ys, slopt);
              
          % fprintf('lorentz freq %sHz\n', uio.sci(m));
          freqs_Hz(fi) = m;
          fwhm = 2*g;
	  % fprintf('FWHM %sHz\n', uio.sci(fwhm,1));
          lorentz_wids(fi) = fwhm;
          if (show_each_seg_fit)
	    ncplot.init;
            ff = a*g./(pi*((xs-m).^2+g^2)) + o;
	    plot(xs/1e6, ys, '.', 'Color', cq(1,:));
	    plot(xs/1e6, ff, '-','Color','red');
            line(([-1 1]*g+m)/1e6, [1 1]*a/(pi*g)/2+o, 'Color','red');
            xlabel('freq (MHz)');
            ylabel('amplitude (dBr)');
	    ncplot.txt(sprintf('integration %.1fus', pd_us));
	    ncplot.txt(sprintf('RBW %sHz', uio.sci(1/(pd_us*1e-6))));
	    ncplot.txt(sprintf('FWHM %sHz', uio.sci(fwhm)));
	    ncplot.title({fname_s; ...
                          sprintf('offset %s',uio.dur((fi-1)/fsamp_Hz))});
	    uio.pause;
          end
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
      lopt.weighting='y';
      lopt.m=0;
      lopt.fwhm = mean(lorentz_wids);
      %   fprintf('DBG: pre-fit mean of lorentz widths %sHz\n', uio.sci(lopt.fwhm));
		%      lopt.hh_wid = hh_wid;
      [a m g o rmse] = fit.lorentzian(x_all, y_all, lopt);
      %      fwhm_Hz = 2*g;

      if (0) % when I fit to dBc
        y3 = a/(pi*g)-3;
        hw = sqrt(a*g/(pi*y3)-g^2);
      else % when I fit to v^2
        y3 = a/(2*pi*g);
        hw = g;
      end

      fwhm_Hz = 2*hw;
      
      if (plot_lorentzian_fit)
	ncplot.init();
	plot(x_all/1e6, y_all, '.', 'Color',cq(1,:));
        % Plot lorentzian fit to all fft segments
	xf = linspace(-zoom_bw_Hz/2,  zoom_bw_Hz/2);
	yf = a*g./(pi*((xf-m).^2+g^2)) + o;
	plot((xf-m)/1e6, yf,'Color','red');
	%     line([-.5 .5]*zoom_bw_Hz,[o o],'Color','red');
        line(([-1 1]*fwhm_Hz/2)/1e6, [1 1]*y3+o, 'Color','red');

        %line([-1 1]*g/1e6, [1 1]*a/(pi*g)/2+o, 'Color','red');
        
        
	ncplot.txt(sprintf('integration %s', uio.dur(pd_us*1e-6)));
	ncplot.txt(sprintf('RBW %sHz', uio.sci(1/(pd_us*1e-6), 0)));
	ncplot.txt(sprintf('Lorentzian -3dB width %sHz', ...
			   uio.sci(fwhm_Hz,1)));
        if (beat_with_self)
          ncplot.txt(sprintf('single laser linewid %sHz', uio.sci(fwhm_Hz/sqrt(2),0)));
        end
        
	xlabel('freq (MHz)');
	xlim([-.5 .5]*zoom_bw_Hz/1e6);
	ylabel('power (ADC^2)');
	ncplot.title(fname_s);
	uio.pause();
      else
	fprintf('DBG: post-fit Lorentzian FWHM %sHz\n', uio.sci(fwhm_Hz,1));
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

    
    if ((freqs_l>1) && (pds_l==1))
      
      offs_us = offs_s*1e6;

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


      if (find_lost_samps)
        % Plot fft phase vs time
        'PHASE VS TIME FIND LOST SAMPLES'
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
	if (1)
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

	if (0)
            % largest freq step
           [mxv mxi]=max(abs(diff(freqs_Hz)));
           mxi=mxi+1;
           at_us = offs_us(mxi);
           fprintf('largest freq step %g Hz\n', mxv);
           fprintf('             time %g us\n', at_us);
           idxs = round( (offs_us(mxi) + [-2 2]*pd_us )/1e6 * fsamp_Hz);
           idxs
           rng = idxs(1):idxs(2);
           plot((rng-1).'/fsamp_Hz*1e6, a1(rng), '.');
           plot([1 1]*at_us, [-1 1]*2000,'-','Color','red');
        end
        
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
      
      elseif (1) % USUAL STUFF

	y = freqs_Hz(:)-freqs_mean_Hz;
        
	if (plot_allan_var) % Allan Variance
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
	
	if (1) % Freq Noise PSD using autocorr
  	  end_l = ceil(1e-3 / (pd_us*1e-6)); % samps at end
	  seg_l = freqs_l - end_l;
	  acorr_l = end_l+1;
'ACORR'
	  k=floor(acorr_l/2);
	  acorr=zeros(acorr_l,1);
	  for k=0:(acorr_l-1)
	    acorr(k+1)=mean(y(1:seg_l).*y(k+(1:seg_l)));
	  end
	  if (1) % double-check autocorr
	    ncplot.subplot();
	    plot((0:(acorr_l-1))*pd_us, acorr/1e12,'.');
	    xlabel('delay (us)');
	    ylabel('freq (MHz^2)');
	    title('autocorrelation of freq change');
            uio.pause();
          end
          ax = ncplot.subplot();

          if (1)
            psdopt.plot_y=1;
            sig = exp(-acorr/2);
            ncplot.fft(sig, pd_us*1e-6, psdopt);
          else
  	      res = local_fft(acorr, pd_us*1e-6);
              idxs = find(abs(res.f_f) < 2e4);
              plot(res.f_f(idxs), res.f_r(idxs), '.');
          end
          uio.pause();

          if (0)
            lopt.dbg=1;
            lopt.weighting='y';
	  lopt.init_y_thresh = .50;
          lopt.fwhm = 2000;
          lopt.m=0;
          %          lx = [-flipdim(res.x_Hz,1); res.x_Hz];
          lx = res.f_f(idxs);
          ly = res.f_r(idxs);
          [a m g o rmse] = fit.lorentzian(lx, ly, lopt);
          end
          
	  title('Freq Noise Power Spectral Density (autocorr method)');
	  set(ax, 'YScale', 'log')
          xlabel('freq (Hz)');
	  ylabel('noise density (Hz^2 / Hz)');
        end

	if (0)
            ax=ncplot.subplot();
	    if (1)
  	        lsdopt.plot_y2=1;
	        res = ncplot.fft(freqs_Hz-freqs_mean_Hz, pd_us*1e-6, lsdopt);
                fcut_Hz = exp((log(res.x_Hz(end))+log(res.x_Hz(1)))/2)
                idx = find(res.x_Hz > fcut_Hz,1)
                p_m = mean(res.f_r(idx:end).^2);
                line([res.x_Hz(1) res.x_Hz(end)], [1 1]*p_m, 'Color','red');
                ncplot.txt(sprintf('floor %sHz', uio.sci(p_m)));
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
        end

        
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
      end
    end
  end
  


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


function res = local_fft(sig, tsamp)
      sig = sig(:);
      l = length(sig);
%      l2 = floor(l/2)+1;
      l2 = ceil(l/2);

% Hann window to reduce "leakage" (see IEEE 1057 4.1.6)
% Then dan added sqrt(8/3) so power is consistent after windowing
      sig = sig .* (.5-.5*cos(2*pi*(0:l-1).'/l)) * sqrt(8/3);

      f_f = (-l2+1:l2).'/(l*tsamp);
      
      f_n=fft(sig-mean(sig));
      f_r=abs(f_n);

      res.f_r = [flipdim(f_r(l2+1:end),1); f_r(1:l2)]
      res.f_f = f_f; % [flipdim(f_f(l2+1:end),1); f_f(1:l2)];
end    



function [a m g o rmse] = local_fit_lorentzian(x, y, opt)
      % weighted lorentzian fit
      % Dan Reilly
      % data must be a postive-going lorentzian
      %      fit(x) = a*g./(pi*((x-m).^2+g^2)) + o
      % g is the half-width at half height.
      % max height (above offset o) is a/(pi*g)
      % slope at x is:
      %      -2*a*g*(x-m)./(pi*((x-m).^2+g^2)^2)
      % options:
      %  opt.m: [] or starting mid value.
      %  opt.fwhm: 0 or starting full-width at half-max.  Supercedes
      %            init_y_thresh
      %  opt.init_y_thresh: determines pts used for initial guess at gamma
      %                range: 0..1  default: .25
      err=0;

      if (size(y,2)>1)
        error('nc.fit.lorentzian(): y must be vertical');
      end
      if (size(x,2)>1)
        error('nc.fit.lorentzian(): x must be vertical');
      end
      l = length(y);
      if (length(x) ~= l);
        error(sprintf('nc.fit.lorentzian(): length of x=%d does not equal length of y=%d', length(x), l));
      end
      if (l<3)
          error(sprintf('nc.fit.lorentzian(): length(y)=%d is less than three. Fitting impossible.', l));
      end
      if (l<10)
          fprintf('WARN: nc.fit.lorentzian(): length(y)=%d so fitting may be hard', l);
      end
      
      s2p = sqrt(2*pi);

      import nc.*
      opt.foo=1;
      opt = util.set_field_if_undef(opt, 'maxiter', 20);
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'fwhm', 0);
      opt = util.set_field_if_undef(opt, 'init_y_thresh', .25);
      opt = util.set_field_if_undef(opt, 'm', []);
      opt = util.set_field_if_undef(opt, 'weighting', 'n');
      opt = util.set_field_if_undef(opt, 'offset', []);
      opt = util.set_field_if_undef(opt, 'gscale', 1);


      if (isempty(opt.offset))
        if (1)
          % take median y of values within 5% of the ends
          th = 0.05;          
          x_mx = max(x);
          x_mn = min(x);
          idxs=[];
          while(length(idxs)<10)
            idxs = find((x< x_mn+(x_mx-x_mn)*th)|(x>x_mx-(x_mx-x_mn)*th));
            if (length(idxs)>10) break; end
            th = th * 1.5;
          end
          y_off = median(y(idxs));
        else
          l = length(y);
          y_mx = max(y);
          y_mn = min(y);
          idxs = find(y < y_mn + (y_mx-y_mn)*0.1); % lower 1%
          y_off = median(y(idxs));
        end
      else
        t_off = opt.offset;
      end

      dbg = opt.dbg;
      if (dbg)
        fprintf('WARN: nc.fit.lorentzian() called with opt.dbg=1\n');
        [co,ch,cq]=ncplot.colors();
      end

      if (0 && dbg)
        h = figure;
        ncplot.init();
        plot(x, y, '.');
        ncplot.title('fit_lorentzian.m');
        line([min(x) max(x)], [1 1]*y_off, 'Color', 'red');
	% ncplot.txt(sprintf('guess o = %g', y_off));
        uio.pause;
        size(y)
        delete(h);
      end
      y = y - y_off;
      o = 0;

      % normalize a little to help numerically
      if (sum(y)==0)
        ysum = 1;
      else
        ysum = abs(sum(y));
      end
      y = y/ysum;


      choice ='a';


      a = max(y);

      if (isempty(opt.m))
        m=mean(x(find(y>0.90*a))); % x coord of mean of upper 90%
        if (isempty(m))
          m=0;
        end
      else
        m = opt.m;
      end

      if (opt.fwhm)
        fwhm = opt.fwhm;
        g = fwhm/2;
      else % try to figure it out
        th = opt.init_y_thresh;
        min_pts = min(10, ceil(l/2)); % min points reqd for fit
        if (length(find(y>=0)) < min_pts)
          my=min(y);
          % fprintf('len y %d  minpts %d  miny %g\n', length(y), min_pts, my);
          th = 0;
          for itr=1:3
            [mxv mxi] = max((y<th).*(y-my));
            % fprintf('  max %g at %d\n', mxv+my, mxi);
            th = mxv+my; % largest y value below old th
            idxs = find(y>=th); % sub-fit to upper part of y
            if (length(idxs) >= min_pts)
              break;
            end
          end
        else
          for itr=1:50
            idxs = find(y>=th*a); % sub-fit to upper part of y
            if (length(idxs) >= min_pts)
              break;
            end
            th = th * .9; % lower the threshold
          end
        end
        % let x'=(x-m).^2, and suppose o=0.
        % Then lorentz = a*g./(pi*(x'+g^2))
        % we take the slope of the log of the lorentzian
        % d/dx'(log(lorentz))=d/dx'(log(a*g/pi)-log(x'+g^2))
        % = -1/(x'+g^2), and at x'=0, this is -1/g^2
        sf_x = (x(idxs)-m).^2;
        sf_y = log(y(idxs));
        sf_l = length(idxs);
        % Now we fit a straight line to sf_x, sf_y
        % we could do:  p = polyfit(sf_x, sf_y, 1);
        % but we try to do better:
        d = [sf_x repmat(1,sf_l,1)];
        if (1)
          wd2=diag(ones(sf_l,1));
        else % weighting helps exclude bad points
          % This weights center more higly
          wd2 = diag(1./(sf_x+1)).^2;
        end
        mm = (d.'*wd2*d);
        rc = rcond(mm);
        if (rc < 1e-15)
          p=fit.polyfit(sf_x, sf_y, 1);
        else
          p = mm\(d.'*wd2*sf_y); % this is better than polyfit
			             %   p = polyfit(xf, sf_y, 1);
        end
        s = 1/sqrt(abs(p(1)));
        % The half-height half-width of a ??? is:
        fwhm = sqrt(-log(0.5)*2*s^2);

        if (0 && opt.dbg && (choice ~='e'))
            h = figure;
	    ncplot.init;
            [co,ch,cq]=ncplot.colors();            
	    ncplot.subplot(2,1);
	    ncplot.subplot;
	    plot(x,y,'.', 'Color', cq(1,:));
            %hold('on');
	    plot(x(idxs),y(idxs),'.','Color','green');
	    ncplot.txt(sprintf('a %g', a));
	    ncplot.txt(sprintf('m %g', m));
	    ncplot.txt(sprintf('above %d%% in green',100*opt.init_y_thresh));
	    ncplot.title({'nc.fit.lorentzian.m: DEBUG';
	            'normalized points above thresh 0.20';
	                  'used to determin initial STD estimate'});
	    xlabel('x');
	    xlabel('y (norm)');

	    ncplot.subplot;
	    plot(sf_x, sf_y, '.');
	      hold('on');
	      xx=[min(sf_x) max(sf_x)];
	      yy=polyval(p, xx);
	      plot(xx, yy, '-', 'Color', 'green');
	      xlabel('(x-m)^2');
	      ylabel('log(y)');
	      ncplot.txt(sprintf('std est %g', s));
	      ncplot.txt(sprintf('fwhm  %g', fwhm));
	      ncplot.title({'nc.fit.lorentzian.m: DEBUG';
		            'initial STD estimate';
		            'comes from the slope of this'});
              choice = uio.ask_choice('again or skip to end', 'ae', 'a');
              delete(h)
          end
          g = (fwhm/2);
      end


      % If we assume we know m and g, we can calc the best a and o:
      if (opt.weighting=='y')
        wd2 = diag(1./(1+(x-m).^2/g^2));
      else
        wd2 = diag(ones(l,1));
      end
      d = [g./((x-m).^2+g^2) ones(l,1)];
      mm = (d.'*wd2*d);
      rc = rcond(mm);
      if (rc<1e-15)
        a = a*g;
      else
        p = mm\(d.' * wd2 * y);
        a = p(1);
        o = p(2);
      end
      if (dbg)
        fprintf('FITL: start  a=%g  o=%g\n', a, o);
      end
    

      if (opt.weighting=='n')
        wd2 = diag(ones(l,1)); % none.  if using this and subtracting median, seems to not converge well
      end

      rec = zeros(opt.maxiter,5);

      % param matrix is p=[dm ds].'
      choice ='a';
      itr=0;
      while(itr<opt.maxiter)
        ly = log(y-o);
        idxs = find(y>o);
        fit = log(a * g  ./ ((x-m).^2+g^2));
        %        err = fit-y;

        err = fit(idxs) - ly(idxs);
	err_mean = mean(err);
	erro = err - err_mean;
	mse = (erro.'*erro)/l; % TODO: should be weighted
	itr=itr+1;
	rec(itr,:)=[mse a m g o];
	done = (mse<1e-16);
	nochange = ((itr>4)&&(abs(mse-mse_pre)<1e-10));
        
	if (opt.dbg && (choice ~='e'))
	  ncplot.init();
	  plot(x, [ly fit], '.');
	  xlim([min(x) max(x)]);
          min(ly(idxs))
          max(ly(idxs))
	  ylim([min(ly(idxs))   max(ly(idxs))]);
          %	  ncplot.ylim([min(ly) max(ly)]);
	  ncplot.txt(sprintf(' iter %d', itr));
	  ncplot.txt(sprintf(' a m g o [%g %g %g %g]', a, m, g, o));
	  ncplot.txt(sprintf(' mse %g    ok %d', mse, done));
	  ncplot.txt(sprintf(' rmse %g', sqrt(mse)));
	  if (done)
            ncplot.txt(sprintf(' close enough! done.'));
	  end
	  if (nochange)
            ncplot.txt(sprintf(' not changing! done.'));
	  end
	  %      plot_txt(sprintf(' deltas [%g %g %g]', p(1),p(2),p(3)));
	  ncplot.title({'nc.fit.lorentzian.m: DEBUG';
			'iterative step of fitting'});
          choice = uio.ask_choice('FITL: again or skip to end', 'ae', 'a');          
	end

	if (done || nochange)
	  break;
	end

        % just vary width and mid.
        % Keep height the same, that is, a = k*g.
        k = a/g;
        % G = g^2;  d = [df/dm df/dG]
        tmp = (x(idxs)-m).^2+g^2;
        d = [2*(x(idxs)-m)./tmp       1/g^2 - 1./tmp];

        %        % try not change m the same time as g
        %        d = [(fit-o)/a  ...
        %             (fit-o)*2.*(x-m)./((x-m).^2+g^2)];% ...
        %            -(fit-o).*(1/g + 2*g./((x-m).^2+g^2))/opt.gscale ];
        
        if (opt.weighting=='y')
          wd2 = diag(1./(1+(x(idxs)-m).^2/g^2));
        else
          wd2 = diag(ones(length(idxs),1));
        end
        mm = (d.'*wd2*d);
	rc = rcond(mm);
	if (rc>1e-15)
  	  p = mm\(d.'*wd2*-err);
	  m = m+p(1);
	  g = g+p(2)/(2*g);
          a = g*k;
	end

	if (opt.dbg && (choice ~='e'))
          ncplot.init();
          fit = log(a * g  ./ ((x-m).^2+g^2));
	  plot(x, [ly fit], '.');
	  xlim([min(x) max(x)]);
	  ylim([min(ly(idxs))   max(ly(idxs))]);
	  ncplot.txt(sprintf(' iter %d', itr));
	  ncplot.txt(sprintf(' a m g o [%g %g %g %g]', a, m, g, o));
	  ncplot.txt(sprintf(' rmse %g', sqrt(mse)));
	  if (done)
            ncplot.txt(sprintf(' close enough! done.'));
	  end
	  if (nochange)
            ncplot.txt(sprintf(' not changing! done.'));
	  end
	  %      plot_txt(sprintf(' deltas [%g %g %g]', p(1),p(2),p(3)));
	  ncplot.title({'nc.fit.lorentzian.m: DEBUG';
			'iterative step of fitting'});
          'PT2'
          choice = uio.ask_choice('FITL: again or skip to end', 'ae', 'a');          
	end

        
        if (1)
          % Now solve a and o
          % d = [df/da df/do]
          % solve d*p ~= y, use all pts
          if (opt.weighting=='y')
            wd2 = diag(1./(1+(x-m).^2/g^2));
          else
            wd2 = diag(ones(l,1));
          end
          d  = [g./((x-m).^2+g^2) ones(l,1)];
          mm = (d.'*wd2*d);
  	  rc = rcond(mm);
	  if (rc>1e-15)
            p = mm\(d.' * wd2 * y);
  	    a = p(1);
	    o = p(2);
          end
          % fprintf('then solve o %g\n', o);
        end
        
	mse_pre=mse;	      
      end

      idx=find(rec(1:itr,1)==min(rec(1:itr,1)),1);
      rmse = sqrt(rec(idx,1));
      a=rec(idx,2);
      m=rec(idx,3);
      g=rec(idx,4);
      o=rec(idx,5);

      % de-normalize by ysum and y_off;
      y = y * ysum + y_off;
      o = o * ysum + y_off;
      a = a * ysum;
      
      % convert to canonical form
      a = a * pi;
      fit = a*g./(pi*((x-m).^2+g^2)) + o;
      err = y-fit;
      mse = (err.'*err)/l;
      rmse = sqrt(mse);
      fwhm = 2*g; % full width half max

      if (dbg)
	ncplot.init;
	plot(x,[y fit],'.');
	ncplot.txt(sprintf(' FWHM %g', fwhm));
	ncplot.txt(sprintf(' rec rmse %g', rmse));
	ncplot.txt(sprintf(' final rmse %g', sqrt(mse)));
	uio.pause;
      end


end
    
