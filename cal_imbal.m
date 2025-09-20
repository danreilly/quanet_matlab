function cal_imbal(arg)
  import nc.*
  mname='p.m';

  opt_show=1;
  h_JpHz = 6.62607e-34;
  wl_m = 1544.53e-9;
  c_mps= 299792458;

  opt_fnum=-1;
  if (nargin>0)
    [v n]=sscanf(arg,'%d');
    if (n==1)
      opt_fnum = v;
    end
  end
  
  tvars = nc.vars_class('tvars.txt');
 
  fname='';
  dflt_fname_var = 'fname';


  if (opt_fnum>=0) 
    fn_full = tvars.get(dflt_fname_var,'');
    max_fnum = 0; % tvars.get('max_fnum', 0);
    if (iscell(fn_full))
      str = fn_full{1};
    else
      str = fn_full;
    end
    [pname fname ext] = fileparts(str);
    [n is ie] = fileutils.num_in_fname(fname);
    if (ie>0)
      places = ie-is+1;
      %fmt = ['%s%0' num2str(places) 'd%s'];
      fmt = '%s%d%s';
      fn2 = sprintf(fmt, fname(1:is-1), opt_fnum, fname(ie+1:end));
      fname = fullfile(pname, [fn2 ext]);
      if (~exist(fname,'file'))
        fprintf('WARN: requested does not exist:\n');
        fprintf('   %s\n', fname);
        fname='';
      else
        tvars.set(dflt_fname_var, fname);
      end
    end
  end
  if (isempty(fname))  
    fname = tvars.ask_fname('measurement file', dflt_fname_var);
  end
  tvars.save();


  [mvars m aug] = load_measfile(fname);
  if (isempty(m))
    return;
  end
  fname = mvars.name;
  fname_s = fileutils.fname_relative(fname,'log');
  aug0=reshape(repmat(aug(1,:),4,1),[],1);
  aug1=reshape(repmat(aug(2,:),4,1),[],1);
  aug2=reshape(repmat(aug(3,:),4,1),[],1);
  aug3=reshape(repmat(aug(4,:),4,1),[],1);
  aug4=reshape(repmat(aug(5,:),4,1),[],1);
  aug5=reshape(repmat(aug(6,:),4,1),[],1);
  aug6=reshape(repmat(aug(7,:),4,1),[],1);
  aug7=reshape(repmat(aug(8,:),4,1),[],1);
  


  
  use_lfsr = mvars.get('use_lfsr',1);
  num_itr  = mvars.get('num_itr',1);
  
  tx_same_hdrs = mvars.get('rx_same_hdrs',[]);
  if (isempty(tx_same_hdrs))
    tx_same_hdrs = mvars.get('tx_same_hdrs',0);
  end
  % fprintf('rx same hdrs %d\n', tx_same_hdrs);
  
  tx_0 = mvars.get('tx_0',0);
  
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('frame_pd_samps', 0); % deprecated
  end
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('probe_pd_samps', 2464); % deprecated
  end

  tst_sync = mvars.get('tst_sync', 0);
  tst_sync=0;
  is_alice = mvars.get('is_alice', 0);    
  frame_qty = mvars.get('frame_qty', 0);

  if (~frame_qty)    
    frame_qty = mvars.get('probe_qty', 0); % deprecated
    if (~frame_qty)    
      frame_qty = mvars.get('frame_qty', 0); % deprecated
    end
  end
  if (tst_sync)
    frame_qty = frame_qty*2;
  end
  
  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  if (~hdr_len_bits)
    hdr_len_bits = mvars.get('probe_len_bits', 256); % deprecated
  end

  asamp_Hz = mvars.get('asamp_Hz', 0);
  if (asamp_Hz==0)
    asamp_Hz = mvars.get('fsamp_Hz', 1.233333333e9);
  end
  
  osamp = mvars.get('osamp', 4);
  cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
  cipher_m = mvars.get('cipher_m',0); % cipher uses m-psk
  
  hdr_len_asamps = hdr_len_bits * osamp;
  hdr_len_s = hdr_len_asamps/asamp_Hz;


  tx_hdr_twopi = mvars.get('tx_hdr_twopi',0);
  host = mvars.get('host','');
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  m11=mvars.get('m11',1);
  m12=mvars.get('m12',0);
  annotation=mvars.get('annotation','');
  already_balanced = ((abs(m11-1)>.001)||(abs(m12)>.001));

  if (already_balanced)
    fprintf('\nERR: HDL registers are already doing rebalancing\n');
    fprintf('     Imbalance calibration must be done when HDL does not rebalance\n');
    fprintf('     run   u cal norebal\n');
    return;
  end
    
    
  

  % IQ SCATTERPLOT
  ii = m(:,1);
  qq = m(:,2);
  ncplot.init();
  [co,ch,coq]=ncplot.colors();
  ncplot.subplot(1,2);
  ncplot.subplot();
  iqopt.markersize=1;

  ncplot.iq(ii, qq, iqopt);
  ncplot.title({fname_s; 'raw IQ scatterplot'});
  p = ii.^2 + qq.^2;
  n_rms = sqrt(mean(ii.^2 + qq.^2));
  i_std = std(ii);
  q_std = std(qq);
  if (~isempty(host))
    ncplot.txt(sprintf('%s', host));
  end
  if (1)
    if (~isempty(annotation))
      ncplot.txt(annotation);
    end
    ncplot.txt(sprintf('num samples %d', length(ii)));
    ncplot.txt(sprintf('mean I %.2f  std %.3f', mean(ii), i_std));
    ncplot.txt(sprintf('mean Q %.2f  std %.3f', mean(qq), q_std));
    % ncplot.txt(sprintf('filter %s', filt_desc));
    ncplot.txt(sprintf('pwr std %.1f ', std(p)));
    ncplot.txt(sprintf('E radius %.1f ADCrms', n_rms));
  end
  if (already_balanced)
    ncplot.txt('rebalanced by HDL');
  end


  
  %  ncplot.subplot();
  %  ncplot.invisible_axes();

  tvars.save();
  find_hdr=0;
    
  calc_sweep_ang= mvars.get('tx_mem_circ',0);
  if (calc_sweep_ang)
    fprintf('Calculating sweep angle because tx_mem_circ=1\n');
  else
    calc_sweep_ang= ~find_hdr;
  end
  if (calc_sweep_ang)
    frame_pd_asamps = floor(frame_pd_asamps/10);
  end
    
    
  tvars.save();  








  
  if (0)
  mean_pwr_dBm = mvars.get('mean_pwr_dBm', []);
  if (~isempty(mean_pwr_dBm))
    mean_pwr_dBm = mvars.ask('mean signal pwr (dB,)', 'mean_pwr_dBm', -inf);
  else
    mon_pwr_dBm = mvars.ask('monitor pwr (dBm)', 'monitor_pwr_dBm', -inf);
    d=tvars.get('sig_minus_mon_dB',0);
    sig_minus_mon_dB = mvars.ask('add what to monitor to get sig pwr', 'sig_minus_mon_dB',d);
    mvars.set('sig_minus_mon_dB',sig_minus_mon_dB);
    mean_pwr_dBm = mon_pwr_dBm + sig_minus_mon_dB;
  end
  mvars.save();
  end

  cipher_frame_qty=0;
  cipher_en = mvars.get('cipher_en',0);
  

  cipher_len_asamps = frame_pd_asamps - hdr_len_asamps;
  cipher_len_bits   = cipher_len_asamps * round(log2(cipher_m)) / ...
      cipher_symlen_asamps;
  cipher_symlen_s = cipher_symlen_asamps / asamp_Hz;

  
  

  
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  fprintf('lfsr rst st x%s\n', lfsr_rst_st);
  lfsr = lfsr_class(hex2dec('a01'), hex2dec(lfsr_rst_st));
  lfsr_idx = 0;
  cipher_lfsr = lfsr_class(hex2dec('280001'), hex2dec('abcde'));
  % cipher_lfsr = lfsr_class(hex2dec('280001'),    hex2dec('aabbc'));

  

  
  sim_hdl.do = 0;

  tvars.save();






          
  hdr_pwr_thresh = mvars.get('hdr_pwr_thresh');
  %  calc_pwr_dets(hdr_pwr_thresh, ii, qq, 16, hdr_len_asamps, fname_s);

  frame_pd_s  = frame_pd_asamps/asamp_Hz;
  frame_pd_us = frame_pd_asamps/asamp_Hz*1e6;
  l = length(ii);

  fprintf('fsamp = %.3f GHz\n', asamp_Hz/1e9);
  fprintf('num samples %d asamps = %d Ksamps = %s\n', l, round(l/1024), uio.dur(l/asamp_Hz));
  fprintf('num frames  %d\n', floor(l/frame_pd_asamps));
  if (l==0)
    fprintf('ERR: no data\n');
    return;
  end

  frame_qty = floor(l/frame_pd_asamps);

  % do this instead of multiplying frame_qty by two.
  
  fprintf('frame_pd    %d samps = %s\n', frame_pd_asamps, uio.dur(frame_pd_s));
  fprintf('hdr_len     %d bits  = %s\n', hdr_len_bits, uio.dur(osamp*hdr_len_bits/asamp_Hz));



          
  
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
    % line([x(1) x(end)],[1 1]*ym,'Color','green');
  else
    pat = (pat-.5)*2;
    %    c = corr(pat, y);
    tit='RZ Correlation';
  end

  %  ncplot.init();  
  %  ncplot.subplot(1,2);


  
  filt_desc='none';
  fcut_Hz = asamp_Hz*3/16;
  filt_len = 8;
  use_filt = 0;
  %  use_filt = tvars.ask_yn('filter ', 'use_filt', use_filt);






  
  do_eye=1;

  figure(gcf());    



  res = calc_rebalance(ii, qq);
  
  i_off = res.i_off;
  q_off = res.q_off;
  th_rad=res.th_deg*pi/180;
  c=cos(th_rad);
  s=sin(th_rad);
  im2=[res.i_factor 0;0 res.q_factor]*[c s;-s c]*[ii+i_off qq+q_off].';
  mx=max(abs(im2(:)));
  ii = im2(1,:).';
  qq = im2(2,:).';
  if (sim_hdl.do)
    ii=round(ii);
    qq=round(qq);
  end
  radius_mean=sqrt(mean(ii.^2+qq.^2));
  
  ncplot.subplot();
  ncplot.iq(ii,qq,iqopt);
  ncplot.txt(sprintf('qnic %s', host));
  ncplot.txt(sprintf('sqrt(<I^2+Q^2>) %.1f ADC', radius_mean));

    ncplot.txt('rebalance parameters');
    ncplot.txt(sprintf('  i_off    %d', res.i_off));
    ncplot.txt(sprintf('  q_off    %d', res.q_off));
    ncplot.txt(sprintf('  i_factor %g', res.i_factor));
    ncplot.txt(sprintf('  q_factor %g', res.q_factor));
    ncplot.txt(sprintf('  angle  %.1f deg', res.th_deg));
    ncplot.txt(sprintf('  (radius %.1f)', radius_mean));

    %    ncplot.txt(sprintf('hdr twopi %d', mvars.get('tx_hdr_twopi',0)));

  %   xlim([-1.1 1.1]*mx);    ylim([-1.1 1.1]*mx);
  ncplot.title({fname_s; 'Corrected IQ scatterplot (all samples)'});

  if (uio.ask_yn('write calibration file',-1))
    dev_name='qnic';
    archive_var='qnic_archive'; % variable storing path to archive
    while(1)
      archive_path = tvars.ask_dir(['calibration archive for ' dev_name], archive_var);
      [f_path f_name f_ext]=fileparts(archive_path);
      if (~strfind(f_name,'archive'));
        fprintf('WARN: %s\n', archive);
        fprintf('      is a non-standard calibration archive name\n');
      end
      if (exist(archive_path, 'dir'))
        break;
      end
      fprintf('WARN: %s\n', archive_path);
      fprintf('      doesnt exist\n');
    end
    [n is ie] = fileutils.num_in_fname(fname_s);      
    datedir = fileutils.rootname(fileutils.path(fname));
    ofname = fullfile(archive_path,host,datedir,sprintf('cal_%s_rebal_%s_%03d.txt', host, datedir, n));
    if (exist(ofname))
      fprintf('WARN: calibration file already exists\n');
      fprintf('      %s\n', ofname);
      if (~uio.ask_yn('overwrite',0))
        ofname='';
      end
    end
    if (~isempty(ofname))
      ovars = nc.vars_class(ofname);
      ovars.clear_vars();
      ovars.set('filetype', 'rebal');
      ovars.copy(mvars, {'engineer', 'host', 'serialnum', 'hwver', 'fwver'});
      ovars.set_context;
      ovars.set('host', host);
      ovars.set('srcfile', fname);
      ovars.set('i_off', res.i_off);
      ovars.set('q_off', res.q_off);
      ovars.set('i_fact',res.i_factor);
      ovars.set('q_fact',res.q_factor);
      ovars.set('ang_deg',res.th_deg);
      ovars.save();
      fprintf('wrote %s\n', ovars.name);
      ncplot.txt(sprintf('wrote %s', fileutils.fname_relative(ofname,'archive')));
    end
  end
  uio.pause();
  

  return;


    
  if (0)
    % sinusoidal fit is poor because phase is drifting
    ncplot.init();
    [a b c f err_rms]  = fit.sin(qq, asamp_Hz);
    t_s=(0:length(qq)-1)/asamp_Hz;
    ff=    a*cos(2*pi*f*t_s) + b*sin(2*pi*f*t_s) + c;
    plot(t_s,qq,'.','Color',coq(1,:));
    plot(t_s,ff,'.','Color','black');
    uio.pause();    
  end

  if (1) % BEFORE MAIN LOOP

    if (1)
      lfsr.reset();      
      hdr = lfsr.gen(hdr_len_bits);
      hdr = repmat(hdr.',osamp,1);
      hdr = hdr(:)*2-1;
      ci = corr(hdr, ii);
      cq = corr(hdr, qq);
      c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
      if (0)
      p  = sqrt(ii.^2 + qq.^2);
      cp = corr(ones(1,length(hdr)),p);
      cp = cp*max(ii)/max(cp);
      c2 = c2 ./ cp;
      c2 = c2*max(ii)/max(c2);
      end

  search_off_asamps=0;
  qsdc_start_idx=find(aug4,1);
  if (qsdc_start_idx) 
    % make sure we dont split up pilot
    search_off_asamps=mod(qsdc_start_idx-99,frame_pd_asamps)
  end
  dbg_find=1;      
      c2_max=zeros(10,1);
      s_i=0;
      f_l=floor(length(ii)/frame_pd_asamps); % for each frame
      for f_i=1:f_l
          % frame_off is zero based.
        frame_off=(f_i-1)*frame_pd_asamps + search_off_asamps;
        rng = (1:frame_pd_asamps)+frame_off;
        if (rng(end)>length(ii))
          break;
        end
        [mx mxi] = max(c2(rng));
        %        fprintf('idx %d = %s   mx %d  mxi %d\n', frame_off+1, uio.dur(frame_off/asamp_Hz), round(mx), mxi);
        c2_max(f_i)=mx;
        if (f_i==4)
          s=std(c2_max(1:4));
          mx_m=mean(c2_max(1:4));
          % fprintf('std %g\n', s);
        elseif (f_i>4)
          c2_slope = c2(rng(1)-1+mxi) - c2(rng(1)-2+mxi);
          k =  (mx > (mx_m*2)); % +s*4)) && (c2_slope > 200);
          if (dbg_find)
            fprintf('%d   mx %.1f  slope %d  k %d\n', f_i, mx, c2_slope, k)
          end
          if (k==1)
            s_i = rng(1)-1+mxi;
            opt_skip = frame_off/frame_pd_asamps;
            break;
          end
        end
      end
    end
    
    % TIME DOMAIN PLOT, EVERYTHING (not main in loop yet)
    if (1)
      ncplot.subplot(1,1);
      ncplot.subplot();
      t_us = 1e6*(0:(l-1)).'/asamp_Hz;
      if (1)
        x=1:l;
        xunits='samps';
      else
        x=t_us;
        xunits='us';
      end
      plot(x,ii,'.','Color',coq(1,:));
      plot(x,qq,'.','Color',coq(2,:));
      % plot(t_us,cp,'-','Color','yellow');
      plot(x,c2,'-','Color','red');
      if (s_i)
        line(x(s_i)*[1 1],[0 max(ii)],'Color','red');
        ncplot.txt(sprintf('pilot at idx %d = %d = %s', s_i, mod(s_i-1,frame_pd_asamps)+1, uio.dur(t_us(s_i)/1e6,3)));
        if (~is_alice)
          s_i_b=ceil((s_i-1)/4)*4+1;
          if (s_i_b ~= s_i)
            ncplot.txt(sprintf('   BUT ideally at idx %d (add %d)', s_i_b, s_i_b-s_i));
          end
        end
      end
      plot_aug_events('hdr_det', x, aug1, 'blue', mx*.5);
      %a//      if (any(aug1))
      %anplot(x, aug1*mx*.5, '-', 'Color','blue');
      %A      else
      %        ncplot.txt('no hdr det');
      %      end
      
      mx = max([ii;qq]);
      if (is_alice)
        plot_aug_events('frame_sync', x, aug7, 'yellow', mx*.8);
        plot_aug_events('pwr_event_iso', x, aug5, 'magenta', mx*.5);
        %        if (any(aug5))
        %          ncplot.txt('pwr_event_iso','magenta');
        %          plot(x, aug5*mx*.5, '-', 'Color','magenta'); % pwr_event_iso
        %        else
        %          ncplot.txt('no pwr_event_iso');
        %        end
        if (any(aug5))
          ncplot.txt('hdr_found','black');
          plot(x, aug3*mx,    '-', 'Color','black');   % hdr_found
        else
          ncplot.txt('hdr not found');
        end
      else
        plot_aug_events('frame_go_dlyd', x, aug4, 'green', mx*.5);        
        %        plot_aug_events('nonhdr_vld', x, aug6, 'black', mx*.5);        
        if (any(aug4))
          idx=find(aug4,1);
          %          plot(t_us(idx)*[1 1], [0 mx], '-','Color', 'green');
          %         plot(x, aug4*mx, '-', 'Color', 'green');
          ncplot.txt(sprintf('frame_go_dlyd at idx %d = %s', idx, uio.dur(t_us(idx))));
          ID=180; % ideal diff
          if (s_i && ~is_alice)
            if (idx == s_i_b-ID)
              ncplot.txt('   which is GOOD');
            else
              ncplot.txt(sprintf('  BUT ideally at idx %d (add %d)', s_i_b-ID, s_i_b-ID-idx));
              ncplot.txt('  (use "u round <dly>")');
            end
          end
        end
      end
      xlabel(sprintf('time (%ss)', xunits));
      y_mx = max(abs(ii));
      ncplot.title({'time series I & Q ... ALL samples'; fname_s});
      ncplot.subplot();

      opt_offset_asamps = uio.ask('analysis offset (asamps)', max(0,s_i-16));

    end
  else
    if (0)
      opt_skip=tvars.ask('skip how many frames', 'opt_skip');
      opt_offset_asamps = opt_skip * frame_pd_asamps;
    else
      opt_offset_ns = tvars.ask('analysis time offset (ns)', 'opt_offset_ns', 0);
      opt_offset_asamps = round(opt_offset_ns*1e-9*asamp_Hz)
    end
  end
  
  if (0)

    noise=zeros(num_itr,1);
    l = frame_qty * frame_pd_asamps;
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
  



  
  plot_corr_mx=0;  
  %  h_l=928; % 116*8
  %  h_l=154*4;
  %  h_l=1240;
  h_l= frame_pd_asamps;
  %  l=floor(l/2);
  n=floor(l/h_l); % number of frames captured per session
  %  n = uio.ask('number of frames to process', n);
  l=n*h_l;
  %  y = reshape(y(1:(n*h_l)),h_l,[]);
  %  ii = ii(1:l);
  %  qq = qq(1:l);
  t_ns = 1e9*(0:(h_l-1))/asamp_Hz;
  t_us = t_ns/1000;
  % x = 1:(h_l*n);


  if (0)
    ncplot.subplot(1,2);
    plot((1:l)-1, ii(1:l),'.');
    return;
  end

  
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
  
  % opt_skip_left = opt_skip;
  tvars.save();

  c_all  = zeros(h_l,1);
  n_all  = 0;

  if (~use_lfsr)
    hdr = pat_base(:);
  end


  if (sim_hdl.do)
    pwr_all=abs(ii)+abs(qq);
    ii = bitshift(ii,-sim_hdl.num_lsb_discard);
    qq = bitshift(qq,-sim_hdl.num_lsb_discard);
    m_i = max(abs(ii));
    m_q = max(abs(qq));
    fprintf('discarded %d LSBs from each sample. Now max I %d=x%x, Q %d=x%x\n', ...
            sim_hdl.num_lsb_discard, m_i, m_i, m_q, m_q);
  else
    pwr_all=sqrt(ii.^2+qq.^2);
  end

  cheat=0;
  if (cipher_en)
    cipher_en = tvars.ask_yn('analyze cipher','analyze_cipher',0);
    if (cipher_en)
      ignore_ns = tvars.ask('ignore time after pilot (ns)','ignore_ns',0);
      ignore_asamps = round(ignore_ns * 1e-9 * asamp_Hz);

      if (~cheat)
        body_ph_offset_deg = tvars.ask('body phase offset (deg)','body_ph_offset_deg',1);
      end

    end
  end
  if (cipher_en)
    cipher = zeros(cipher_len_bits, 1);
  end
  alice_txing = mvars.get('alice_txing',0);
  rx_en = alice_txing;


  
  do_calc_pwr = tvars.ask_yn('calc pwr','calc_pwr',0);



  frame_by_frame = tvars.ask_yn('frame by frame','frame_by_frame',1);
  opt_show = frame_by_frame;

  

  tvars.save();


  
  if (do_calc_pwr)
    cpopt.len_asamps=0;
    cpopt.start_idx=0; % find start
    cpopt.mean_pwr_dBm = mean_pwr_dBm;
    cpopt.chip_s = osamp/asamp_Hz
    pwr_res = calc_pwr(pwr_all.^2, frame_pd_asamps, hdr_len_asamps, asamp_Hz, fname_s, cpopt);
    uio.pause();
  end 


  
  mxi_l = 6;
  mxi_occ = 0;
  mxis=zeros(mxi_l,1);


    
  choice = 'n';

    
  n_left = n;
  itr=1;
  while ((n_left>0)&&(itr<=num_itr))
      ncplot.subplot(1,2);
      opt_show_all=opt_show;

      lfsr.reset();
      lfsr_idx = 0;
      
      nn = min(frame_qty, n_left);

      ci_sum = zeros(h_l,1);
      cq_sum = zeros(h_l,1);
      c      = zeros(h_l,1);
      c_qty  = 0;
      c_alice = zeros(h_l,1);
      ca_qty  = 0;
      pwr    = zeros(h_l,1);
      c2     = zeros(h_l,1);
      c2_mi = 0;
      pwr2   = zeros(h_l,1);
      hdr_phs_deg = zeros(frame_qty,1);
      phs_deg_l = 0;
      body_phs_deg = zeros(frame_qty,1);
      bers    = zeros(frame_qty,1);

      si = 1               + (itr-1)*frame_qty*frame_pd_asamps;
      ei = nn*frame_pd_asamps + (itr-1)*frame_qty*frame_pd_asamps;

      ncplot.subplot(2,1);
      
      plot_eye(si,ei,itr,[]);
      
      if (use_filt)
        filt_desc = sprintf('gauss fcut %.1fMHz  len %d', fcut_Hz/1e6, filt_len);
        ii(si:ei) = filt.gauss(ii(si:ei), asamp_Hz, fcut_Hz, filt_len);
        qq(si:ei) = filt.gauss(qq(si:ei), asamp_Hz, fcut_Hz, filt_len);
      end

      if (sim_hdl.do)
        lfsr.reset();                    
        hdr = lfsr.gen(hdr_len_bits);
          
        ci = corr(hdr, ii);
        cq = corr(hdr, qq);
        sum_shft = floor(log2(hdr_len_bits -1));
        c2 = abs(ci)+abs(cq);
        m_c=max(abs(c2));
        fprintf('HDL: before crop max corr %d = x%x\n', m_c, m_c);
        c2 = bitshift(abs(ci)+abs(cq), -sum_shft);
        m_c=max(abs(c2));
        th = 2^sim_hdl.mag_w;
        % fprintf('max corr %d = x%x, crop thresh x%x\n', m_c, m_c, th);
        idxs = find(c2>=th);
        cl=length(idxs);
        c2(idxs)=th-1;
        idxs = find(c2<-th);
        cl=cl+length(idxs);
        c2(idxs)=-th;
        if (cl)
            fprintf('WARN: %d samples cropped\n', cl);
        end
        
        calc_corr_dets(c2, hdr_len_asamps, frame_qty, fname_s, sim_hdl);
        lfsr.reset();
        lfsr_idx = 0;
          
      end


      mx=0;
      skip=0;
      pwr = zeros(frame_pd_asamps,1);

      cipher_err_cnt=0;
      cipher_bit_cnt=0;


opt_offset_asamps      
      sweep_angs = [];
      for f_i=1:nn % for each frame
        % frame_off is zero based.
        fprintf('frame %d\n', f_i);
        frame_off=(f_i-1)*frame_pd_asamps + (itr-1)*frame_qty*frame_pd_asamps + opt_offset_asamps;
        if (frame_off+frame_pd_asamps > length(ii))
          break;
        end
        rng = (1:frame_pd_asamps)+frame_off;


        if (find_hdr)

          if (use_lfsr) % ever-changing probe
            if (tx_same_hdrs)
              lfsr.reset();                    
              lfsr_idx = 0;
            end
            hdr = lfsr.gen(hdr_len_bits);
            lfsr_idx = lfsr_idx + 1;
          end
          hdr = repmat(hdr.',osamp,1);
          hdr = hdr(:)*2-1;


          % CORRELATE FOR PILOT or PROBE
          size(rng)
          size(hdr)
          ci = corr(hdr, ii(rng));
          cq = corr(hdr, qq(rng));
          c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
          [mxv mxi]=max(c2);

          
          % mxi should always be the same. check that.
          if (~skip && (mxi_occ < mxi_l))
            mxi_occ=mxi_occ+1;
            mxis(mxi_occ)=mxi;
            if (mxi_occ==mxi_l)
              mxi_med = round(median(mxis));
            end
          elseif (mxi_occ >= mxi_l)
            if (mxi ~= mxi_med)
              fprintf('WARN: corr max in bin %d not %d.  Adj sync dly by %d\n', ...
                      mxi, mxi_med, mxi_med-mxi);
            end
            mxv=c2(mxi);
          end

          % DETERMINE PHASE OF HEADER
          % Because our corr pattern uses +1 for 1 and -1 for 0,
          % A positive correlation lies along pos x axis.
          hdr_ph_deg = atan2(cq(mxi),ci(mxi))*180/pi;
          hdr_phs_deg(f_i)=hdr_ph_deg;
          hdr_phs_deg_l = f_i;

          % fprintf('DBG: found pilot at index %d, phase %.1f deg\n', mxi, hdr_ph_deg);
          
          if (sim_hdl.do)
            
            sum_shft = floor(log2(hdr_len_bits -1));
            c2 = abs(ci)+abs(cq);
            m_c=max(abs(c2));
            fprintf('HDL: before crop max corr %d = x%x\n', m_c, m_c);
            c2 = bitshift(abs(ci)+abs(cq), -sum_shft);
            m_c=max(abs(c2));
            th = 2^sim_hdl.mag_w;
            % fprintf('max corr %d = x%x, crop thresh x%x\n', m_c, m_c, th);
            idxs = find(c2>=th);
            cl=length(idxs);
            c2(idxs)=th-1;
            idxs = find(c2<-th);
            cl=cl+length(idxs);
            c2(idxs)=-th;
            if (cl)
              fprintf('WARN: %d samples cropped\n', cl);
            end
            
            m_c=max(abs(c2));
            fprintf('after crop: max corr %d = x%x\n', m_c, m_c);
            %           elseif (mean_before_norm)
            %             ci_sum = ci_sum + ci/nn;
            %             cq_sum = cq_sum + cq/nn;
            %           else
          end

        end % if find_hdr

        
        % TIME DOMAIN PLOT OF CURRENT FRAME
        if (opt_show_all)

          ncplot.subplot(1,2);
          ncplot.subplot();
          if (1)
            t_ms = 1e6*(rng-1).'/asamp_Hz;
            xunits = 'us';
          else
            t_ms = rng;
            xunits = 'samples';
          end
          plot(t_ms, ii(rng), '.-', 'Color',coq(1,:));
          plot(t_ms, qq(rng), '.-', 'Color',coq(2,:));
          
          if (find_hdr)
            plot(t_ms, c2, '-', 'Color','red');
            [c2_mx c2_mi]=max(c2);
            line([1 1]*t_ms(c2_mi),[0 c2_mx],'Color','red');
            mx = max(mx, max(abs(c2))); % just for plot ylim
            if (c2_mi+hdr_len_asamps <= frame_pd_asamps)
              line([1 1]*t_ms(c2_mi+hdr_len_asamps),[0 c2_mx],'Color','magenta');
              % dont plot hdr if not all of it is there.
              h_rng = c2_mi-1+(0:hdr_len_bits-1)*osamp + 2;
              h_rng = [h_rng; h_rng+1];
              h_rng = reshape(h_rng,[],1);
              plot(t_ms(h_rng), ii(h_rng+frame_off), '.', 'Color', co(1,:));
              plot(t_ms(h_rng), qq(h_rng+frame_off), '.', 'Color', co(2,:));
            end
          end

          %        plot(t_ms, pwr_all(rng), '-', 'Color','yellow');
          if (is_alice)
            plot(t_ms, aug0(rng)*mx,    '-', 'Color','green');   % pwr_det
            plot(t_ms, aug5(rng)*mx*.5, '-', 'Color','magenta'); % pwr_event_iso
          end
          size(aug1)
          idx=find(aug1(rng),1);
          if (idx)
            plot(t_ms, aug1(rng)*mx, '-', 'Color','blue');   % dbg_hdr_det
            ncplot.txt(sprintf('HDL detection at idx %d = %s', ...
                               idx, uio.dur(t_ms(idx))));
          end
          %                  plot(t_ms, aug2(rng)*mx, '-', 'Color','magenta');% hdr_sync (not dlyd)
          plot(t_ms, aug3(rng)*mx, '-', 'Color','black');  % hdr_found
          plot(t_ms, aug4(rng)*mx*.9, '-', 'Color','red'); % hdr_sync_dlyd
                                                           % plot(t_ms, aug4(rng)*1000, '-', 'Color','blue');
          xlim([t_ms(1) t_ms(end)]);
          [mx mi]=max(pwr_all(rng));
          if (1)
            if (host)
              ncplot.txt(sprintf('host %s', host));
            end
            ncplot.txt(sprintf('frame %d', f_i));
            ncplot.txt(sprintf('offset %d = time %s', frame_off, uio.dur(frame_off/asamp_Hz)));
            ncplot.txt(sprintf('max sqrt(I^2+Q^2)  %.1f', mx));
            if (find_hdr)
              ncplot.txt(sprintf('det:  pwr_thresh %d  corr_thresh %d', ...
                                 mvars.get('hdr_pwr_thresh'), mvars.get('hdr_corr_thresh')));
              ncplot.txt(sprintf('corr max %d at %.3fms = idx %d', ...
                                 round(c2_mx), t_ms(c2_mi), c2_mi));
            end
          end
          aug2_sub =   aug2(rng);
          ai=find(aug2_sub, 1);
          if (~isempty(ai))
            ncplot.txt(sprintf('      aug2 %d',ai));
          end
          % ylim([-1.2 1.2]*mx);
          xlabel(sprintf('time (%s)',xunits));
          ylabel('amplitude (adc)');
          ncplot.title({mname; fname_s});


          
          if (find_hdr)
            ncplot.subplot();
            h_rng = frame_off+c2_mi-1+(1:hdr_len_asamps);
            ncplot.iq(ii(h_rng),qq(h_rng));
            h_srng = frame_off+c2_mi-1 + floor(osamp/2)+1 + (0:hdr_len_bits-1)*osamp;
            plot(ii(h_srng),qq(h_srng),'.', 'Color','blue');
            mx=max([abs(ii);abs(qq)]);
            c=cos(hdr_ph_deg*pi/180)*mx;
            s=sin(hdr_ph_deg*pi/180)*mx;
            line([0 c],[0 s],'Color','blue');
            ncplot.title({'IQ plot of pilot'; fname_s});
            ncplot.txt(sprintf('frame %d', f_i));
            ncplot.txt(sprintf('phase %d deg', round(hdr_ph_deg)));
            ncplot.txt(sprintf('pilot twopi %d', tx_hdr_twopi));
          end

          uio.pause('review frame');

          if (find_hdr)
          % DEROTATE HDR AND FIND MEAN SEPARATION OF BPSK CONSTELLATION.
          iiqq = geom.rotate(-hdr_ph_deg*pi/180, [ii(h_srng).';qq(h_srng).']);
          ii_s = iiqq(1,:).';
          qq_s = iiqq(2,:).';
          idxs=find(ii_s>=0);
          i1_m = mean(ii_s(idxs));
          q1_m = mean(qq_s(idxs));
          idxs=find(ii_s<0);
          i0_m = mean(ii_s(idxs));
          q0_m = mean(qq_s(idxs));
          ncplot.subplot();
          ncplot.iq(ii_s, qq_s);
          plot(i1_m, q1_m, '.', 'Color', 'blue');
          plot(i0_m, q0_m, '.', 'Color', 'blue');
          dist = sqrt((i1_m-i0_m).^2+(q1_m-q0_m)^2);
          ncplot.txt(sprintf('mean dist %.1f', dist));
          ncplot.title({'DEROTATED pilot'; fname_s});
          uio.pause('review derotated hdr');
          end
        end % if show all

        % CIRCLE FIT FOR WHEN DOING SINE MODULATION FOR IMBALANCE CALIBRATION
        if (~find_hdr)
          fcopt.noplot=~opt_show_all;
          if (opt_show_all)
            ncplot.subplot();
            ncplot.iq(ii(rng),qq(rng));
            xlabel('I');
            ylabel('Q');
            ncplot.title({fname_s; 'IQ plot of frame'});
            ncplot.txt(sprintf('sqrt(<I^2+Q^2>) %.1f', sqrt(mean(ii(rng).^2+qq(rng).^2))));
          end
          fcopt.no_txt=0;
          [ctr radius sweep_deg cphs_deg] = fit_circle(ii(rng),qq(rng),fcopt);
          sweep_angs(f_i)  = sweep_deg;
          hdr_phs_deg(f_i) = cphs_deg;
          hdr_phs_deg_l = f_i;
        end
        


        if (do_calc_pwr && frame_by_frame)
          'CALC PWR'
          prng = (f_i-1)*frame_pd_asamps + c2_mi-1 + (1:frame_pd_asamps);
          pwr_an=pwr_all(prng);
          cpopt.len_asamps=frame_pd_asamps;
          cpopt.start_idx=1;
          res = calc_pwr(pwr_an.^2, ...
                         frame_pd_asamps, hdr_len_asamps, asamp_Hz, fname_s, cpopt);
          uio.pause();
          pwr = pwr + pwr_all(rng);
        end


        % frame_off is zero-based.
        is = frame_off + c2_mi-1 + hdr_len_asamps+1; % idx of start of body
        if (cipher_en && (is+cipher_len_asamps-1 <= l))
          cipher = cipher_lfsr.gen(cipher_len_bits);
          if (cipher_m==8)
            cipher = reshape(cipher.',4,[]);
            cipher = 8*cipher(1,:)+4*cipher(2,:)+1*cipher(3,:)+cipher(4,:);
          elseif (cipher_m==4)
            cipher = reshape(cipher.',2,[]);
            cipher = 2*cipher(1,:)+cipher(2,:);
          else
            cipher = reshape(cipher.',1,[]);
          end
          % cipher(1:16)

          cipher = repmat(cipher,cipher_symlen_asamps,1);
          cipher = cipher(:);
          
          cipher_frame_qty = f_i;
          ii_s = ii(is-1 + (1:cipher_len_asamps));
          qq_s = qq(is-1 + (1:cipher_len_asamps));

          cipher_c = exp(-i*cipher*2*pi/cipher_m); % BPSK: 0->1, 1->-1
          desc = 'body';

          %          xs = cipher_len_asamps/2+1;
          xs = ceil(ignore_asamps / cipher_symlen_asamps)*cipher_symlen_asamps + 1; % 1 based
          xe = cipher_len_asamps - cipher_symlen_asamps; % 1 based
          ss_l = floor((xe-xs+1)/cipher_symlen_asamps);
          xl = [xs xe]; % range of "good" data in ii_s.
          idxs= xs + (0:ss_l-1)*cipher_symlen_asamps + 1;
          eidxs = idxs.'+1;
          idxs=reshape([idxs; idxs+1],[],1);

          % ph_deg = 0;


          if (cheat)
            ph_deg = calc_derot2(ii_s(idxs),qq_s(idxs), hdr_ph_deg+tx_hdr_twopi*90);
            ph_method='cheat';
          else
            % ph_deg = hdr_ph_deg + tx_hdr_twopi*30; ph_method='hdr+30';
            ph_deg =  hdr_ph_deg - body_ph_offset_deg + tx_hdr_twopi*45;
            ph_method='pilot based';
          end
          %ph_deg = calc_derot(ii_s(idxs),qq_s(idxs), ph_deg);
          body_phs_deg(f_i) = ph_deg;


          % IQ PLOT OF RAW BODY (AFTER PILOT)
          if (opt_show_all && frame_by_frame)
            ncplot.subplot(1,2);
            ncplot.subplot();
            iqopt.color=coq(1,:);
            iqopt.markersize=6;
            ncplot.iq(ii_s, qq_s, iqopt);
            iqopt.color=co(1,:);
            ncplot.iq(ii_s(idxs), qq_s(idxs), iqopt);
            %       plot(ii_s(idxs),qq_s(idxs), );
            ncplot.title(sprintf('%s BEFORE ROTATION', desc));
            %            ncplot.txt(sprintf('ph %.1f deg', ph_deg));
          end

          % IQ PLOT OF ROTATED BODY (AFTER PILOT)
          iiqq = geom.rotate(-ph_deg*pi/180, [ii_s.';qq_s.']);
          ii_s = iiqq(1,:).';
          qq_s = iiqq(2,:).';
          if (opt_show_all && frame_by_frame)
            ncplot.subplot();
            iqopt.color=coq(1,:);
            ncplot.iq(ii_s, qq_s, iqopt);
            iqopt.color=co(1,:);
            ncplot.iq(ii_s(idxs),qq_s(idxs), iqopt);
            ncplot.title(sprintf('%s AFTER ROTATION', desc));
            if (~cheat)
              ncplot.txt(sprintf('rotated by %d-pilot', body_ph_offset_deg));
            end
            ncplot.txt(sprintf('rotated by %.1f deg', -ph_deg));
            ncplot.txt(sprintf('method: %s', ph_method));
            uio.pause('review derotation of body');
          end

          if (0)
            ncplot.subplot();
            % Plot histogram of slices through "chip" to  double check
            % that we sample the chip in the middle of its eye
            mx=max(ii_s);
            mn=min(ii_s);
            s=(mx-mn)/63;
            edges=mn:s:mx;
            edges(end)=inf;
            ii_r=reshape(ii_s,4,[]);
            for k=1:4
              n=histc(ii_r(k,:), edges);
              plot(1:length(n),n,'.-','Color',coq(k,:));
            end
            title('histograms of eye slices');
            %          plot(mod(0:length(ii_s)-1,4), ii_s, '.', 'Markersize',1,'Color', coq(1,:));
            %          xlim([-0.1 3.1]);
            %          xlabel('idx');ylabel('i');
            uio.pause();
          end
          

          err=0;


          
          errmsk=logical(zeros(ss_l,1));
          for k=1:ss_l
            ki = cipher_len_asamps-4*ss_l+1+(k-1)*4+1;
            c=cipher(ki);
            % fprintf(' %d',c);
            ii_m=mean(ii_s(ki+(0:1)));
            errmsk(k) = logical(c ~= (ii_m>0));
            err = err + (c ~= (ii_m>0));
            %            qq_m=mean(qq_s(ki+(0:1)));
            %            plot(ii_m, qq_m, '.', 'Color', coq(1,:));
            % fprintf('%d %g %g\n', c, ii_m, qq_m);            
            %            sums(c+1,1:3)=sums(c+1,1:3)+[1 ii_m qq_m];
          end
          ber = err/ss_l;
          if (cheat && (ber>.5))
            ber = 1-ber;
            body_phs_deg(f_i) = ph_deg+180;
            err = ss_l-err;
          end
          bers(f_i) = ber;

          if (f_i>2)
            cipher_err_cnt = cipher_err_cnt + err;
            cipher_bit_cnt = cipher_bit_cnt + ss_l;
          end
          % fprintf('\n');
          
          if (opt_show_all && frame_by_frame)
            fprintf('cipher %d-psk, len %d asamps, duration %s\n', cipher_m, length(cipher), ...
                  uio.dur(length(cipher)/asamp_Hz));

            
            ncplot.init();
            ncplot.subplot(1,2);
            % Time Domain plot of IQ with expected data superimposed
            ncplot.subplot();
            plot(1:cipher_len_asamps, ii_s, '-', 'Color',coq(1,:));
            plot(idxs, ii_s(idxs), '.', 'Color',ch(1,:));
            plot(1:cipher_len_asamps, qq_s, '-', 'Color',coq(2,:));
            plot(idxs, qq_s(idxs), '.', 'Color',ch(2,:));
            mx=max(max(abs(ii_s)),max(abs(qq_s)))*.9;
            if (1)
              plot(1:cipher_len_asamps, real(cipher_c)*mx*.5, '-', 'Color', 'yellow');
              ncplot.txt('yellow: expected cipher');
            end
            plot(eidxs(errmsk),ii_s(eidxs(errmsk)),'.','Color','red');
            
            if (cipher_m>2)
              plot(1:cipher_len_asamps, imag(cipher_c)*mx, '-', 'Color',coq(2,:));
            end
            ncplot.txt(sprintf('frame %d', f_i));
            xlim(xl);
            ylabel('i&q (adc)');
            xlabel('index');
            title(sprintf('rotated body time domain', desc));
              
            ncplot.subplot();
            % ncplot.eye(ii_s(xs:cipher_len_asamps), qq_s(xs:cipher_len_asamps));
            ncplot.iq(ii_s(idxs),qq_s(idxs));
            %            v=calc_derot(ii_s(idxs),qq_s(idxs))*5000;
            %            line([0 v(1)],[0 v(2)],'Color','red');
            ncplot.title({sprintf('rotatad body IQ plot', desc); fname_s});
            ncplot.txt(sprintf('frame %d', f_i));
            ncplot.txt(sprintf('bits %d', ss_l*round(log2(cipher_m))), 'blue');

            fprintf('cipher BER %.4f\n', ber);
            uio.pause('review rotated body');
          end

          if (0)
            ncplot.subplot();
            % take mean of all "similar" symbols
            sums=zeros(cipher_m,3);
            for k=1:ss_l
              ki = cipher_len_asamps-4*ss_l+1+(k-1)*4+1;
              c=cipher(ki);
              
              ii_m=mean(ii_s(ki+(0:1)));
              printf('%d %d\n', c, ii_m>0)
              
              %            qq_m=mean(qq_s(ki+(0:1)));
              %            plot(ii_m, qq_m, '.', 'Color', coq(1,:));
              % fprintf('%d %g %g\n', c, ii_m, qq_m);            
              %            sums(c+1,1:3)=sums(c+1,1:3)+[1 ii_m qq_m];
            end
            %          set(gca(),'PlotBoxAspectRatio', [1 1 1]);
            for k=1:cipher_m
              sums(k,2:3) = sums(k,2:3)/sums(k,1);
              fprintf('%d %.1f %.1f\n', k-1, sums(k,2:3));
              plot(sums(k,2),sums(k,3),'.','Color',co(1,:));
              text(sums(k,2),sums(k,3),sprintf('%d', k-1),'Color',co(1,:));
            end
            ncplot.title({fname_s; 'IQ scatterplot of body'});
          end

          
          if (0)
            ncplot.subplot(3,1);
            ph_s = atan2(qq_s, ii_s)*180/pi;
            ncplot.subplot();
            plot(1:cipher_len_asamps, ph_s, '.-', 'Color',coq(1,:));
            plot(1:cipher_len_asamps, (mod(cipher,4)+1)*50, '.-', 'Color',coq(2,:));
            xlim(xl);
            title('phase of IQ');
          end

          if (0) %DEROTE BY CIPHER
            sig = (ii_s + j * qq_s) .* cipher_c;
            ii_s = real(sig);
            qq_s = imag(sig);
            ncplot.subplot();
            plot(1:cipher_len_asamps, ii_s, 'Color',coq(1,:));
            plot(1:cipher_len_asamps, qq_s, 'Color',coq(2,:));
            xlim([xs cipher_len_asamps]);
            title('after derot');
            uio.pause();
          end
        end


        if (~tst_sync || (f_i<=frame_qty/2))
          c = c + c2;
          c_qty = c_qty + 1;
        else
          c_alice = c_alice + c2;
          ca_qty = ca_qty + 1;
        end


        if (opt_show_all)                  
          choice = uio.ask_choice('(n)ext, goto (e)nd, or (q)uit', 'neq', choice);
          if (choice=='q')
            return;
          elseif (choice=='e')
            opt_show_all=0;
          end
        end

      end % for f_i (each frame)


      %      fprintf('DBG: out of loop f_i\n');
      
      if (calc_sweep_ang)
        fprintf('\n\nmean sweep angle %.1f deg\n', mean(sweep_angs));
        fprintf('         uncertainty %.1f deg (std)\n', std(sweep_angs));
        uio.pause();
      end
      if (cipher_en)

        body_pwr_mW = 10^(mean_pwr_dBm/10);
        fprintf('body pwr %sW\n', uio.sci(body_pwr_mW/1000));
        %        wl_nm=1544.53e-9;
        fprintf('body_symlen %s\n', uio.dur(cipher_symlen_s));
        n = body_pwr_mW/1000 * cipher_symlen_s / (h_JpHz * c_mps / wl_m);
        fprintf('body pwr %.2fdB = %sW = %.1f photons\n', mean_pwr_dBm, uio.sci(body_pwr_mW/1000), n);
        cipher_ber = cipher_err_cnt / cipher_bit_cnt;
        fprintf('\ncipher BER %d/%d = %.1e\n', cipher_err_cnt, cipher_bit_cnt, cipher_ber);
        %uio.pause();
      end


      
      %      plot_eye(si,ei,itr);


      
      n_left = n_left - nn;



      if (mean_before_norm && ~opt2)
          % obsolete case
          if (opt_show)
              ncplot.subplot(1,1);
              ncplot.subplot();
              plot(1:frame_pd_asamps, ci_sum, '-', 'Color', co(1,:));
              plot(1:frame_pd_asamps, cq_sum, '-', 'Color', co(2,:));
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
        if (c_qty)
          c = c / c_qty;
        end
        if (ca_qty)
          c_alice = c_alice / ca_qty;
        end
        pwr = pwr/nn;
      end


      if (0)
        'DBG1'
        ncplot.subplot();
        t_all_us = 1e6*(0:(ei-si)).'/asamp_Hz;
        plot(t_all_us, ii(si:ei), '.', 'Color', coq(1,:));
        return;
      end

      % PLOT EYE OF ALL DATA
      ncplot.subplot(3,1);
      plot_corr(si,ei,c);
      %      plot(t_us, pwr, '-','Color','black');
      if (tst_sync)
        [a_mx a_mi]=max(c_alice);
        plot(t_us, c_alice, '-','Color','red');
        a_mx=round(a_mx);
        ncplot.txt(sprintf(' bob marker at idx %d\n', mi));
        ncplot.txt(sprintf('alice pilot at idx %d\n', a_mi));
        ncplot.txt(sprintf('  ideal sync_dly %d\n', mi-a_mi));
      end
      rng=si:ei;
      ncplot.txt(sprintf('  I  mean %.1f  std %.1f', mean(ii(rng)), std(ii(rng))));
      ncplot.txt(sprintf('  Q  mean %.1f  std %.1f', mean(qq(rng)), std(qq(rng))));




      
      
      ncplot.subplot();
      hdr_phs_deg(1) = mod(hdr_phs_deg(1)+180,360)-180;
      phs_unwrap_deg = util.mod_unwrap(hdr_phs_deg(1:hdr_phs_deg_l), 360);
      %      fx=[opt_skip frame_qty-1];
      fr_t_us = (0:hdr_phs_deg_l-1)*frame_pd_s*1e6;
      if (0)
        fx = (opt_skip+1:cipher_frame_qty).';
        p=polyfit(fx, phs_unwrap_deg(fx), 1);
        fy=polyval(p, fx);
        plot((fx-1)*frame_pd_s*1e6, mod(fy+180,360)-180,'-','Color','green');
      end

      plot(fr_t_us(1:hdr_phs_deg_l), phs_unwrap_deg, '.-','Color',coq(1,:));
      ncplot.txt(sprintf('frame period %s  pilot dur %s', uio.dur(frame_pd_s), uio.dur(hdr_len_s)));
      if (find_hdr)
        s='   blue: pilot phase';
      else
        s='   blue: phase';
      end
      xlabel('time (us)');
      ylabel('phase (deg)');
      s=[s sprintf('  mean %d deg', round(mean(phs_unwrap_deg)))];
      s=[s sprintf('  std %.1f deg', std(phs_unwrap_deg))];
      ncplot.txt(s);
      [mx mxi]=max(diff(phs_unwrap_deg));
      ncplot.txt(sprintf('    max jump %.1f deg in %s', mx, uio.dur(frame_pd_s)));
      ncplot.title({fname_s;'phase drift'});
      fprintf('time_us = [ %s ]\n', sprintf(' %.1f', fr_t_us(1:hdr_phs_deg_l)));
      fprintf('hdr_phs_deg = [ %s ]\n', sprintf(' %.1f', phs_unwrap_deg));
      
      if (cipher_en)
        body_phs_deg(1)=mod(hdr_phs_deg(1)+180,360)-180;
        body_phs_unwrap_deg = util.mod_unwrap(body_phs_deg, 360);
        plot(fr_t_us(1:cipher_frame_qty), ...
             body_phs_unwrap_deg(1:cipher_frame_qty), '.-','Color','magenta');
        s=sprintf('magenta: body phase   mean %d deg', round(mean(body_phs_unwrap_deg(1:cipher_frame_qty))));
        ncplot.txt(s);
        

        diff_deg = mod(body_phs_unwrap_deg - phs_unwrap_deg+180,360)-180;

        if (0)
        plot(fr_t_us(1:cipher_frame_qty), ...
             diff_deg(1:cipher_frame_qty), '.-','Color','red');
        ncplot.txt(sprintf('    red: body minus hdr   mean %d', round(mean(diff_deg(1:cipher_frame_qty)))));
        end

        ncplot.txt(sprintf('twopi %d', tx_hdr_twopi));
        
        %      ncplot.txt(sprintf('avg drift %.1f deg/us (green)', p(1)/(frame_pd_s*1e6)))
        %    ylim([-180 180]);
        ncplot.txt(sprintf('body pwr %.2fdBm = %sW = %.1f photons', mean_pwr_dBm, uio.sci(body_pwr_mW/1000,1), n));
        ncplot.txt(sprintf('cipher BER %d/%d = %.3e', cipher_err_cnt, cipher_bit_cnt, cipher_ber));


        ncplot.subplot();
        plot(fr_t_us(1:cipher_frame_qty), ...
             bers(1:cipher_frame_qty), '.');
        xlabel('time (us)');
        ylabel('BER');
        ncplot.title({fname_s;'per-frame BER'});
      end
      
      uio.pause();
      opt_show_aints=0;

      ncplot.init();
      if (frame_pd_s < 1e-6)
        max_aint_us = floor((frame_qty-opt_skip)*frame_pd_s*1e6);
        errs_rms=zeros(max_aint_us,1);
        aints_us=zeros(max_aint_us,1);
        a_i_last=max_aint_us;
        for a_i=1:max_aint_us % analysis interval
          cla();
          aint_samps = a_i+1; % round(a_i*1e-6/frame_pd_s);
          aint_us = aint_samps * frame_pd_s*1e6;
          aints_us(a_i)=aint_us;
          k=opt_skip+1;
          errs=[];
          while(1)
            if (k+aint_samps>frame_qty)
              break;
            end
            p1=phs_unwrap_deg(k);
            p2=phs_unwrap_deg(k+aint_samps);

            fm = (p2-p1)/aint_samps;
            fx = (k:k+aint_samps).';
            fy = (0:aint_samps).'*fm+p1;
            err = fy-phs_unwrap_deg(fx);
            errs = [errs; err(2:aint_samps-1).^2];
            if (opt_show_aints)
                line(([k k+aint_samps]-1)*frame_pd_us,[p1 p2],'Color','red');
                plot((fx-1)*frame_pd_us,phs_unwrap_deg(fx),'.','Color','blue');
                plot(([k k+aint_samps]-1)*frame_pd_us,[p1 p2],'.','Color','red');
                xlabel('time (us)');
                ylabel('phase (deg)');
            end
            k=k+aint_samps;
          end
          err_rms = sqrt(mean(errs));
          errs_rms(a_i)=err_rms;
          if (opt_show_aints)
            ncplot.txt(sprintf('analysis interval %.2f us', aint_us));
            ncplot.txt(sprintf('err %.2f deg rms', err_rms));
            uio.pause();
          end
          if (err_rms>90)
            a_i_last = a_i;
            break;
          end
        end
      end
      
      ncplot.init();
      plot(aints_us(1:a_i_last), errs_rms(1:a_i_last),'.-');
      ncplot.txt(sprintf('test duration %s', uio.dur(frame_qty*frame_pd_s)));
      xlabel('pilot period (us)');
      ylabel('err (deg RMS)');
      ncplot.title({fname_s;'phase error'});
      uio.pause();

      
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
      ncplot.title(sprintf('%s:  %d frames', fname_s, n));
      ylim([-1 1]*max(c)*1.5);
    end
    
  return;
   
  if (0)
      % CORRELATION OF MEAN OF FRAMES
      % wont work if hdr always changes
   ii=mean(reshape(ii,h_l,[]).').';
   qq=mean(reshape(qq,h_l,[]).').';
   ci = corr(pat, ii, 0);
   cq = corr(pat, qq, 0);
   c_l=length(ci);
   m=max(max(abs(ci)),max(abs(cq)));                
   ci = ci * iq_mx / m;
   cq = cq * iq_mx / m;
   c = sqrt(ci.^2+cq.^2);
   [mx mi]=max(abs(c));
   ncplot.subplot();
   % ncplot.txt(sprintf('num frames %d', n));
   ncplot.txt(sprintf('max at %.3f ns', t_ns(mi)));
   ncplot.txt(sprintf('       idx %d', mi));
   plot(t_ns, ii, '.', 'Color', coq(1,:));
   plot(t_ns, qq, '.', 'Color', coq(2,:));
   plot(t_ns(1:c_l), c, '-','Color','red');
   xlim([0 t_ns(end)]);
   ncplot.title(sprintf('%s: corr of mean of %d frames', fname_s, n));
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
        nn = (ei-si+1)/frame_pd_asamps;
        if (1)
            if (1)
                plot(repmat(t_us,1,nn), ii(si:ei), '.', 'Color',coq(1,:));
                %                plot(repmat(t_us,1,nn), qq(si:ei), '.', 'Color',coq(2,:));
            else

                plot(t_us, max(reshape(ii(si:ei),frame_pd_asamps,[]).'),'-', 'Color',coq(1,:));
                plot(t_us, min(reshape(ii(si:ei),frame_pd_asamps,[]).'),'-', 'Color',coq(1,:));
                plot(t_us, max(reshape(qq(si:ei),frame_pd_asamps,[]).'),'-', 'Color',coq(2,:));
                plot(t_us, min(reshape(qq(si:ei),frame_pd_asamps,[]).'),'-', 'Color',coq(2,:));
            end
        end
    end
    plot(t_us, c, '-','Color','blue');
    xlim([min(t_us) max(t_us)]);
    xlabel('time (us)');
    ylabel('amplitude (adc)');
    ncplot.title({mname; sprintf('%s: superposition of %d frames', fname_s, nn)});
    [mx mi]=max(c);
    mx=round(mx);

    plot_corr_mx=max(plot_corr_mx,mx);
    dd=round((hdr_len_bits+2)*osamp/2);
    is = max(mi-dd, 1);
    ie = min(mi+dd, frame_pd_asamps);
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

    if (sim_hdl.do)
      ncplot.txt('HDL SIMULATION');
      ncplot.txt(sprintf('discarded %d LSBs', sim_hdl.num_lsb_discard));
      ncplot.txt(sprintf('corr magnitude width %d bits', sim_hdl.mag_w));
    end
    
    if (0)
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


function calc_corr_dets(c2, hdr_len_asamps, frame_qty, fname_s, sim_hdl)
  import nc.*
  l = length(c2);
  threshs = (0:5:100).';
  threshs_l = length(threshs);
  cnts = zeros(threshs_l,1);
  cover_asamps = sim_hdl.num_slices*4;
  for t_i=1:threshs_l;
    corr_thresh = threshs(t_i);
    det_st=0;
    det_events=0;
    k=1;
    while(k<=l)
      ei=min(l, k+cover_asamps-1);
      if (c2(k:ei) > corr_thresh)
        det_events=det_events+1;
        k=k+hdr_len_asamps;
      else
        k=k+cover_asamps;
      end
    end
    cnts(t_i)=det_events;
  end
  ncplot.subplot();
  plot(threshs, cnts,  '.-');
  line([threshs(1) threshs(end)], [1 1]*frame_qty,'Color','green');
  ncplot.txt(sprintf('num frames %d', frame_qty));
  ncplot.txt(sprintf('discarded %d LSBs', sim_hdl.num_lsb_discard));
  ncplot.txt(sprintf('corr magnitude width %d bits', sim_hdl.mag_w));
  
  xlabel('corr thresh (ADC units)');
  ylabel('num hdr detection events');
  ncplot.title({'p.m'; fname_s});
  uio.pause();
end                             

function calc_pwr_dets(pwr_thresh, ii, qq, pwr_pd_cycs, hdr_len_asamps, fname_s)
  import nc.*
  l = length(ii);
  pwr_pd_asamps = pwr_pd_cycs*4;
  p = abs(ii)+abs(qq);
  l = floor(l/pwr_pd_asamps)*pwr_pd_asamps
  p_ds = reshape(p(1:l), pwr_pd_asamps, []);
  p_ds = round(mean(p_ds,1));
  %  size(p_ds)
  p_avg = reshape(repmat([p_ds(1) p_ds(1:end-1)], pwr_pd_asamps, 1),[],1);
  p_avg_mx = max(p_avg);

  threshs = (0:10:600).';
  threshs_l = length(threshs);
  cnts = zeros(threshs_l,1);
  for t_i=1:threshs_l;
    pwr_thresh = threshs(t_i);
    det=zeros(l,1);
    det_st=0;
    det_events=0;
    k=1;
    while(k<=l)
      if (p(k)>p_avg(k)+pwr_thresh)
        det(k:k+hdr_len_asamps-1)=p_avg_mx;
        k=k+hdr_len_asamps;
        det_events=det_events+1;
      else
        k=k+1;
      end
    end
    cnts(t_i)=det_events;
  end
  if (threshs_l==1)
    ncplot.subplot();
    plot(1:l, p,     '-', 'Color', 'green');
    plot(1:l, p_avg, '-', 'Color', 'blue');
    plot(1:l, det,   '-', 'Color', 'red');
    xlabel('sample index');
    ylabel('amplitude (ADC units)');
    ncplot.txt(sprintf('pwr thresh %d\n', pwr_thresh));
    ncplot.title({'p.m'; fname_s});
  else
    ncplot.subplot();
    plot(threshs, cnts,  '.-');
    xlabel('pwr thresh (ADC units)');
    ylabel('num pwr events');
    ncplot.title({'p.m'; fname_s});
  end
  uio.pause();
end

function plot_aug_events(desc, x, msk, color, mx)
  import nc.*
  idxs=find(msk);
  ncplot.txt(sprintf('%s %d', desc, length(idxs)));
  for k=1:length(idxs)
    line(x(idxs(k))*[1 1],[0 mx],'Color',color);
  end
end
