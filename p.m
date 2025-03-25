function p(arg)
  import nc.*

  do_eye=0;
  opt_show=0;
  if (nargin>0)
      [skip n]=sscanf(arg,'%d')
      if (n==1)
        skip
      else
        opt_show=1;
      end
  end
  
  tvars = nc.vars_class('tvars.txt');
 

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
  if (1)
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
  else
    fid=fopen(fname,'r');
    [m cnt] = fscanf(fid, '%g');
    fclose(fid);
    m = reshape(m, 2,cnt/2).';
    %  hdr_pd_samps = 3700;
    hdr_pd_samps = 2464;
    hdr_len_bits  = 64;
    use_lfsr = 1;
  end
  tvars.save();  

  fsamp_Hz = 1.233333333e9;
  

  lfsr = lfsr_class(hex2dec('a01'), hex2dec('50f'));
  lfsr_idx = 0;

  ncplot.init();
  [co,ch,coq]=ncplot.colors();
  ncplot.subplot(2,4);




  ii = m(:,1);


  qq = m(:,2);
  l = length(ii);
  fprintf('l %d\n', l);
  fprintf('num samples %d Ksamps = %s\n', round(l/1024), uio.dur(l/fsamp_Hz));
  fprintf('num hdrs    %d\n', floor(l/hdr_pd_samps));
  fprintf('hdr pd      %d samps = %s\n', hdr_pd_samps, uio.dur(hdr_pd_samps/fsamp_Hz));
  fprintf('hdr len     %d bits  = %s\n', hdr_len_bits, uio.dur(osamp*hdr_len_bits/fsamp_Hz));
  
  iq_mx = max(max(abs(ii)),max(abs(qq)));


  pat_base = [1,1,1,1,0,0,0,0,1,0,1,0,0,1,0,1, ...
                      1,0,1,0,1,1,0,0,1,0,1,0,0,1,0,1, ...
                      1,0,1,0,1,1,0,0,1,0,1,0,0,1,0,1, ...
         0,1,0,1,0,0,1,1,0,1,0,1,1,0,1,0];

  pat = repmat(pat_base,osamp,1);
  pat = reshape(pat,[],1);
  pat_l=length(pat);
  pat_base = pat_base*2-1;


  method=0;

  if (method==1)
      ym=(max(ii)+min(qq))/2;
      pat = (pat-.5)*2;
%  ncplot.subplot();
    c = corr(pat, y-ym);
    tit='midpoint based';
%    line([x(1) x(end)],[1 1]*ym,'Color','green');
  else
    pat = (pat-.5)*2;
    %    c = corr(pat, y);
    tit='RZ Correlation';
  end

  ncplot.subplot(1,2);

  
  filt_desc='none';
  fcut_Hz = fsamp_Hz*3/16;
  filt_len = 8;
  use_filt = 1;
  use_filt = tvars.ask_yn('filter ', 'use_filt', use_filt);
  
  do_eye=1;

  if (do_eye)

    if (0)
    % IQ SCATTERPLOT
    ncplot.subplot();
    m=max(max(abs(ii)),max(abs(qq)));
    set(gca(),'PlotBoxAspectRatio', [1 1 1]);
    plot(ii,qq,'.');
    xlim([-m m]);
    ylim([-m m]);
    ncplot.title({fname_s; 'IQ scatterplot'});
    n=1;
    si=1;
    ci=1;
    for k=1:n
      ei=min(round(l/n)*k, l);
      plot(ii(si:ei),qq(si:ei),'.','Color',coq(ci,:));
      ci=mod(ci,size(co,1))+1;
      if (n>1)
        uio.pause();
      end
      si=ei+1;
    end
    n_rms = sqrt(mean(ii.^2 + qq.^2));
    
    ncplot.txt(sprintf('filter %s', filt_desc));
    ncplot.txt(sprintf('num samples %d', l));
    ncplot.txt(sprintf('noise %.1f ADCrms', n_rms));
    fprintf('noise %.1f ADCrms\n', n_rms);
    end

    if (0)
      ncplot.subplot(2,1);
      ncplot.subplot();

      if (0)
          t_ms = 1e3*(0:(l-1)).'/fsamp_Hz;
          plot(t_ms,ii,'.','Color',coq(1,:));
          plot(t_ms,qq,'.','Color',coq(2,:));
          xlabel('time (us)');
          y_mx = max(abs(ii));
          ncplot.title('time series I & Q');
          ncplot.subplot();
      end

      noise=zeros(num_itr,1);
      l = hdr_qty * hdr_pd_samps;
      for k=1:(n-1)
        rng = (k-1)*l + (1:l);
        noise(k)=sqrt(mean(ii(rng).^2+qq(rng).^2));
      end
      itr_times_s = mvars.get('itr_times');
      plot(itr_times_s, noise,'.');
      xlabel('time (s)');
      ylabel('noise (ADCrms)');
      return;
      
      gi = 3700; % guess
      ncplot.subplot();
      ncplot.title('autocorrelation');
      c = corr2(ii(1:gi),ii((gi+1):l));
      c_l=length(c);
      plot(1:c_l, ii(gi+1:l), '.', 'Color',coq(1,:));
      %    xlabel('index');
      c = c * y_mx / max(c);
      plot(1:c_l, c, '-','Color','red');
      uio.pause();

      pks = (c>y_mx*.9);
      for k=length(pks):-1:2
          if (pks(k-1)&&pks(k))
	      pks(k)=0;
          end
      end
      idxs = find(pks);

      ncplot.subplot();
      d=diff(idxs);
      plot(d,'.');
      ylabel('difference (idx)');
      xlabel('match');
      
      return;
    end
  end


  
  plot_corr_mx=0;  
  %  h_l=928; % 116*8
  %  h_l=154*4;
  %  h_l=1240;
  h_l= hdr_pd_samps;

  %  l=floor(l/2);

  n=floor(l/h_l); % number of frames captured per session

  %  n = uio.ask('number of frames to process', n);

  l=n*h_l;
  %  y = reshape(y(1:(n*h_l)),h_l,[]);

  %  ii = ii(1:l);
  %  qq = qq(1:l);
  t_ns = 1e9*(0:(h_l-1))/fsamp_Hz;
  t_us = t_ns/1000;
%   x = 1:(h_l*n);



  ncplot.subplot(1,2);
  % CORRELATION WITH HEADER
  %  mean_before_norm = tvars.ask_yn('correlation vector mean taken before magnitude (const ph)', 'mean_before_norm', 1);
  mean_before_norm = 0;
  if (mean_before_norm)
      method=2;
  else
      method=3;
  end

    opt2=0;
      
    tvars.save();
      
    m=max(max(abs(ii)),max(abs(qq)));
    %   fprintf('max abs %d, %d\n', max(abs(ii)), max(abs(qq)));

    %   opt_show=1;
    opt_skip=0;

    if (opt_show)
      opt_skip=tvars.ask('skip how many hdrs', 'opt_skip');
    end

    c_all  = zeros(h_l,1);
    n_all  = 0;

    if (~use_lfsr)
      hdr = pat_base(:);
    end


  choice = 'e';
  search_mode=0;
    
    n_left = n;
    itr=1;
    while ((n_left>0)&&(itr<=num_itr))
      ncplot.subplot(1,2);
      opt_show_all=opt_show;

      lfsr.reset();
      lfsr_idx = 0;

      ci_sum = zeros(h_l,1);
      cq_sum = zeros(h_l,1);
      c      = zeros(h_l,1);
      c2     = zeros(h_l,1);
      
      nn = min(hdr_qty, n_left);

      si = 1               + (itr-1)*hdr_qty*hdr_pd_samps;
      ei = nn*hdr_pd_samps + (itr-1)*hdr_qty*hdr_pd_samps;

      ncplot.subplot(1,2);
      
      plot_eye(si,ei,itr,[]);
      
      if (use_filt)
        filt_desc = sprintf('gauss fcut %.1fMHz  len %d', fcut_Hz/1e6, filt_len);
        ii(si:ei) = filt.gauss(ii(si:ei), fsamp_Hz, fcut_Hz, filt_len);
        qq(si:ei) = filt.gauss(qq(si:ei), fsamp_Hz, fcut_Hz, filt_len);
      end

      tic;
      mx=0;
      for k=1:nn % for each probe
        search_cmax=0;
        while(1)
        if (use_lfsr) % ever-changing probe
          if (opt_skip)
            opt_skip=opt_skip-1;
            hdr = zeros(hdr_len_bits, 1);
          else
            hdr = lfsr.gen(hdr_len_bits);
            lfsr_idx = lfsr_idx + 1;
          end
          hdr = repmat(hdr.',osamp,1);
          hdr = hdr(:)*2-1;
        end

        off=(k-1)*hdr_pd_samps + (itr-1)*hdr_qty*hdr_pd_samps;
        
        rng = (1:hdr_pd_samps)+off;
        if (opt2)
           mm=sqrt(ii(rng).^2+qq(rng).^2);
           c2 = corr_circ(hdr, mm, 0);
        else
           ci = corr_circ(hdr, ii(rng));
           cq = corr_circ(hdr, qq(rng));
           if (mean_before_norm)
             ci_sum = ci_sum + ci/nn;
             cq_sum = cq_sum + cq/nn;
           else
             c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
           end
        end
        if (~opt_show_all)
            break;
        else

          if (~search_mode || (max(c2) > search_cmax))
                search_cmax = max(c2);
                % DRAW ONLY ONE FRAME
                ncplot.subplot(1,1);
                ncplot.subplot();
                plot(1:hdr_pd_samps, ii(rng), '.-', 'Color',coq(1,:));
                plot(1:hdr_pd_samps, qq(rng), '.-', 'Color',coq(2,:));
                if (mean_before_norm)                       
                    plot(1:hdr_pd_samps, ci, '-', 'Color', co(1,:));
                    plot(1:hdr_pd_samps, cq, '-', 'Color', co(2,:));
                    mx = max(mx, max(abs([ci; cq])));
                else
                    plot(1:hdr_pd_samps, c2, '-', 'Color','red');
                    mx = max(mx, max(abs(c2)));
                end
                ncplot.txt(sprintf('frame %d', k));
                
                % ylim([-1.2 1.2]*mx);
                xlabel('time (samples)');
                ylabel('amplitude (adc)');
                ncplot.title({fname_s; sprintf('frame %d', k)});

                choice = uio.ask_choice('(n)ext, goto (e)nd, (s)earch or (r)edo', 'nesr', choice);
                if (choice=='e')
                    opt_show_all=0;
                    break;
                elseif (choice=='n')
                    break;
                elseif (choice=='s')
                    search_mode=1;
                end
            end
          end % if not show all
        end % search loop
        
        c = c + c2;
        
      end % for k



      %      plot_eye(si,ei,itr);
      
      toc

      
      n_left = n_left - nn;



      if (mean_before_norm && ~opt2)
          if (opt_show)
              ncplot.subplot(1,1);
              ncplot.subplot();
              plot(1:hdr_pd_samps, ci_sum, '-', 'Color', co(1,:));
              plot(1:hdr_pd_samps, cq_sum, '-', 'Color', co(2,:));
              mx = max(abs([ci_sum; cq_sum]));
              ylim([-1.1 1.1]*mx);
              xlabel('time (samples)');
              ylabel('amplitude (adc)');
              ncplot.title(fname_s);
              ncplot.txt(sprintf('mean of %d frames', n));
              uio.pause();
          end
          c = sqrt((ci_sum).^2+(cq_sum).^2)/hdr_len_bits;
      else
        c = c/nn;
      end


      if (1)
        'here'
         ncplot.subplot();
         si
         ei
         t_all_us = 1e6*(0:(l-1))/fsamp_Hz;
         plot(t_all_us, ii, '.', 'Color', coq(1,:));
         return;
      end
      
      
      plot_corr(si,ei,c);



      c_all = c_all+c*nn;
      n_all = n_all+nn;

      [mx mi]=max(c_all/n_all);
      fprintf('peak %d  at idx %d\n', round(mx),  mi);

      drawnow();
      if (num_itr>1)
          % uio.pause();
      end
      itr=itr+1;
    end % itrs

    if (num_itr>1)
      c=c_all/n_all;
      plot_corr(1,1,c);
      %      plot(t_us, c, '-', 'Color','blue');
      ncplot.title(sprintf('%s:  %d pings', fname_s, n));
      ylim([-1 1]*max(c)*1.5);
    end
    
  return;
   
  if (0)
      % CORRELATION OF MEAN OF PINGS
      % wont work if hdr always changes
   ii=mean(reshape(ii,h_l,[]).').';
   qq=mean(reshape(qq,h_l,[]).').';
   ci = corr_circ(pat, ii, 0);
   cq = corr_circ(pat, qq, 0);
   c_l=length(ci);
   m=max(max(abs(ci)),max(abs(cq)));                
   ci = ci * iq_mx / m;
   cq = cq * iq_mx / m;
   c = sqrt(ci.^2+cq.^2);
   [mx mi]=max(abs(c));
   ncplot.subplot();
   % ncplot.txt(sprintf('num pings %d', n));
   ncplot.txt(sprintf('max at %.3f ns', t_ns(mi)));
   ncplot.txt(sprintf('       idx %d', mi));
   plot(t_ns, ii, '.', 'Color', coq(1,:));
   plot(t_ns, qq, '.', 'Color', coq(2,:));
   plot(t_ns(1:c_l), c, '-','Color','red');
   xlim([0 t_ns(end)]);
   ncplot.title(sprintf('%s: corr of mean of %d pings', fname_s, n));
   xlabel('time (ns)');
   ylabel('amplitude (adc)');
  end

   ncplot.subplot(2,1);

   % IQ SCATTERPLOT of DETECTED HEADER
   ncplot.subplot();
   ii=paren(circshift(ii,-(mi-1)),1,pat_l);
   qq=paren(circshift(qq,-(mi-1)),1,pat_l);
   m=max(max(abs(ii)),max(abs(qq)));
   set(gca(),'PlotBoxAspectRatio', [1 1 1]);
   plot(ii,qq,'.', 'Color', coq(1,:));

   % DOWNSAMPLE
   l = round(pat_l/osamp);
   ii_d = zeros(l,1);
   qq_d = zeros(l,1);
   vi = zeros(l,1);
   vq = zeros(l,1);
   for k=1:l
     ii_d(k)=mean(ii(((k-1)*osamp+2):(k*osamp-1)));
     qq_d(k)=mean(qq(((k-1)*osamp+2):(k*osamp-1)));
     vi(k)=ii_d(k)*pat_base(k);
     vq(k)=qq_d(k)*pat_base(k);
   end
   plot(ii_d, qq_d, '.', 'Color', 'red');
   %   idxs=(1:l)*osamp - 3;
   %   plot(ii(idxs), qq(idxs), '.', 'Color', 'blue');
   %   plot(ii(idxs+3), qq(idxs+3), '.', 'Color', 'magenta');
   %   plot(vi, vq, '.', 'Color', 'magenta');
   ph = [mean(vi) mean(vq)];
   ph = ph/norm(ph);
   ph_deg = atan2(ph(2), ph(1))*180/pi;
   ph=ph*m;
   xlim([-m m]);
   ylim([-m m]);
   line([0 ph(1)], [0 ph(2)], 'Color','green');
   ncplot.txt(sprintf('phase %.1f deg', ph_deg));
   ncplot.title({fname_s; 'IQ scatterplot'; 'reflected pattern only'});



   %
   ncplot.subplot();
   m=max(abs([ii_d; qq_d]));
   plot(1:l, ii_d, '.', 'Color', coq(1,:));
   plot(1:l, qq_d, '.', 'Color', coq(2,:));
   plot(1:l, pat_base*m, '.', 'Color', 'black');
   ylim([-1.1 1.1]*m);
   xlim([1 l]);
   xlabel('index');
   return;
  

  [p1 i1 p2 i2 sfdr_dB] = calc_sfdr(c);
  c = c * y_mx / max(c);
  c_l=length(c);
  plot(x(1:c_l),c,'-','Color','red');
  ncplot.txt(sprintf('SFDR %.1f dB', sfdr_dB));
  
  ylim([y_mn y_mx]);
  xlim([x(1) x(end)]);
  xlabel('time (ns)');
  ylabel('amplitude (adc)');
  title(tit);

  % NESTED
  function plot_eye(si, ei, itr, filt_desc)
    import nc.*
    ncplot.subplot();
    plot(ii(si:ei),qq(si:ei),'.','Color',coq(1,:));
    ncplot.title({fname_s; sprintf('IQ scatterplot  itr %d', itr)});
    xlim([-1 1]*2^13);
    ylim([-1 1]*2^13);
    set(gca(),'PlotBoxAspectRatio', [1 1 1]);
    
  %   round( ii(si:(si+20)).^2 + qq(si:(si+20)).^2)
    mean(round( ii(si:(si+20)).^2 + qq(si:(si+20)).^2))
    n_rms = sqrt(mean(ii(si:ei).^2 + qq(si:ei).^2));

    if (~isempty(filt_desc))
      ncplot.txt(sprintf('filter %s', filt_desc));
    else
      ncplot.txt('NO FILTER');
    end
        
    ncplot.txt(sprintf('num samples %d', ei-si+1));
    ncplot.txt(sprintf('noise %.1f ADCrms', n_rms));
    fprintf('itr %d   noise %.1f ADCrms\n', itr, n_rms);
  end

  % NESTED
  function plot_corr(si, ei, c)
    import nc.*
    ncplot.subplot();
nn=n;
    if (ei>si)
        nn = (ei-si+1)/hdr_pd_samps;
        if (1)
            if (1)
                plot(repmat(t_us,1,nn), ii(si:ei), '.', 'Color',coq(1,:));
                plot(repmat(t_us,1,nn), qq(si:ei), '.', 'Color',coq(2,:));
            else

                plot(t_us, max(reshape(ii(si:ei),hdr_pd_samps,[]).'),'-', 'Color',coq(1,:));
                plot(t_us, min(reshape(ii(si:ei),hdr_pd_samps,[]).'),'-', 'Color',coq(1,:));
                plot(t_us, max(reshape(qq(si:ei),hdr_pd_samps,[]).'),'-', 'Color',coq(2,:));
                plot(t_us, min(reshape(qq(si:ei),hdr_pd_samps,[]).'),'-', 'Color',coq(2,:));
            end
        end
    end
    plot(t_us, c, '-','Color','blue');
    xlim([min(t_us) max(t_us)]);
    xlabel('time (us)');
    ylabel('amplitude (adc)');
    ncplot.title(sprintf('%s: superposition of %d pings', fname_s, nn));
    [mx mi]=max(c);
    mx=round(mx);
    plot_corr_mx=max(plot_corr_mx,mx);
    dd=round((hdr_len_bits+2)*osamp/2);
    is = max(mi-dd, 1);
    ie = min(mi+dd, hdr_pd_samps);
    %    line([1 1]*t_us(is),[-1 1]*100,'Color','green');
    %    line([1 1]*t_us(ie),[-1 1]*100,'Color','green');
    c((is+1):(ie-1))=0;

    [mx2 mi2]=max(c);
    
    is2 = mi2-dd;
    ie2 = mi2+dd;
    
    if (mi < mi2)
      nf = mean([c(1:is);c(ie:is2);c(ie2:end)]);
      f_std=std([c(1:is);c(ie:is2);c(ie2:end)]);
    else
      nf = mean([c(1:is2);c(ie2:is);c(ie:end)]);
      f_std=std([c(1:is2);c(ie2:is);c(ie:end)]);
    end
    
    c = (mx - nf); 
    q= c/(f_std + sqrt(c));
    %    ylim([0 1.2]*plot_corr_mx);
    %    ncplot.txt(sprintf('method %d', method));
    %    ncplot.txt(sprintf('hdr_len %d bits', hdr_len_bits));
    %    ncplot.txt(sprintf('filter %s', filt_desc));

    
    ncplot.txt(sprintf('  max-nf %.1f at %.3fus (idx %d)', mx-nf, t_us(mi), mi));

    k = mx2-nf;
    if (k>0)
      ncplot.txt(sprintf('  max-nf %.1f at %.3fus (idx %d)', k, t_us(mi2), mi2));
    end
    
    %    fprintf('max %d at idx %d\n', mx, mi);
    ncplot.txt(sprintf('floor mean %.1f   std %.2f', nf, f_std));
    ncplot.txt(sprintf('  snr %.1f dB', 10*log10(mx/nf)));
    ncplot.txt(sprintf('    Q %.1f', q));
  end

  
end
  
function [p1 i1 p2 i2 sfdr_dB] = calc_sfdr(c)
  c_l=length(c);
  [p1 i1]=max(c);

  % find indicies at extents of hump
  i1_h=0;
  for k=1:c_l
    if (i1+k>c_l)
      i1_h=c_l
      break;
    end
    if (c(i1+k)>c(i1+k-1))
      i1_h=i1+k-1;
      break;
    end
  end
  for k=1:c_l
    if (i1-k<1)
      i1_l=1;
      break;
    end
    if (c(i1-k)>c(i1-k+1))
      i1_l=i1-k+1;
      break;
    end
  end
  c(i1_l:i1_h)=0;
  [p2 i2]=max(c);
  sfdr_dB = 10*log10(p1/p2);

  
end


