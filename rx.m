function rx(arg)
  import nc.*
  mname='rx.m';

  %  lfsr0 = lfsr_class(hex2dec('25'), hex2dec('0a')); % cp 100101  rst_st  001010
  %  lfsr0.gen(16)

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
    fname = tvars.ask_fname('data file', dflt_fname_var);
  end
%^  pname = fileparts(fname);
%  pname_pre = fileparts(pname);
  %  if (~strcmp(pname, pname_pre))
  %   'new dir'
    % tvars.set('max_fnum', 0);
    %  end
  tvars.save();


  
  fname_s = fileutils.fname_relative(fname,'log');
  if (1)
    mvars = nc.vars_class(fname);
    use_lfsr = mvars.get('use_lfsr',1);
    num_itr  = mvars.get('num_itr',1);
    
    alice_txing = mvars.get('alice_txing',0);
    if (~alice_txing)
      uio.pause('ERR: alice was not txing in this file\n');
    end

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
      % class(m) is double
      fclose(fid);
      
      aug = m<0;
      for k=1:cnt
        aug(k)=(m(k)<0); % bitget fails on negative numbers
        if (aug(k))
          m(k)= 2^15+m(k);
        end
        m(k)=bitset(m(k),15,0);
        if (bitget(m(k),14))
          m(k)=m(k)-2^14;
        end
      end
      aug = reshape(aug,8,[]);


      aug0=repmat(aug(1,:),4,1);
      aug0=aug0(:);
      aug1=repmat(aug(2,:),4,1);
      aug1=aug1(:);
      aug2=repmat(aug(3,:),4,1);
      aug2=aug2(:);
      aug3=repmat(aug(4,:),4,1);
      aug3=aug3(:);
      aug4=repmat(aug(5,:),4,1);
      aug4=aug4(:);
      aug5=repmat(aug(6,:),4,1);
      aug5=aug5(:);



      

      

      if (0) % uio.ask_yn('gen hex for sim',0))
        s=fileutils.replext(s,'.hex');
        fname3=[fileutils.path(fname) '\' s];
        fprintf(' %s\n', fname3);
        fid=fopen(fname3,'w','l','US-ASCII');
        if (fid<0)
          fprintf('ERR: cant open %s\n', fname3);
        end
        for k=1:length(m)
          fprintf(fid, '%04x', util.ifelse(m(k)>=0, m(k), 2^16+m(k)));
        end
        fclose(fid);
        % class(m) is double
      end
       
      
      m = reshape(m, 2, cnt/2).';
        % 'DBG here'
        % m = reshape(m,cnt/2,2);      
    elseif (other_file==1)
      s = fileutils.nopath(fname);
      s(1)='d';
      fname2=[fileutils.path(fname) '\' s];
      fprintf('  also reading %s\n', fname2);
      fid=fopen(fname2,'r');
        'DBG: reading ascii'
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
    %  frame_pd_samps = 3700;
    frame_pd_asamps = 2464;
    hdr_len_bits  = 64;
  end
  tvars.save();  

  use_lfsr = 1;

  


  
  tx_same_hdrs = 1;
  
  fprintf('rx same pilots %d\n', tx_same_hdrs);
  
  tx_0 = mvars.get('tx_0',0);
  if (tx_0)
    do_eye=1;
  end
  
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('frame_pd_samps', 0); % deprecated
  end
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('probe_pd_samps', 2464); % deprecated
  end

  tst_sync = mvars.get('tst_sync', 0);    
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
  
  osamp = mvars.get('osamp', 4);
  cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
  cipher_m = mvars.get('cipher_m',0); % cipher uses m-psk
  
  hdr_len_asamps = hdr_len_bits * osamp;


    
    asamp_Hz = mvars.get('asamp_Hz', 0);
    if (asamp_Hz==0)
      asamp_Hz = mvars.get('fsamp_Hz', 1.233333333e9);
    end

  tx_hdr_twopi = mvars.get('tx_hdr_twopi',0);
  host = mvars.get('host','');
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  m11=mvars.get('m11',1);
  m12=mvars.get('m12',0);
  already_balanced = ((abs(m11-1)>.001)||(abs(m12)>.001));

  qsdc_data_pos_asamps = mvars.get('qsdc_data_pos_asamps',0);
  qsdc_data_len_asamps = mvars.get('qsdc_data_len_asamps',0);
  qsdc_code_len_cbits = mvars.get('qsdc_code_len_cbits',10);
  qsdc_data_is_qpsk = mvars.get('qsdc_data_is_qpsk',0);
  qsdc_symbol_len_asamps = mvars.get('qsdc_symbol_len_asamps',4);
  qsdc_bit_dur_syms = mvars.get('qsdc_bit_dur_syms',10);

  qsdc_bit_dur_s = qsdc_bit_dur_syms * qsdc_symbol_len_asamps / asamp_Hz;
  
  fprintf('QSDC: data_pos_asamps   %d\n', qsdc_data_pos_asamps); 
  fprintf('      data_len_asamps   %d (per frame)\n', qsdc_data_len_asamps); 
  fprintf('      code_len          %d (code bits, not data bits)\n', qsdc_code_len_cbits);
  fprintf('      symbol_len_asamps %d\n', qsdc_symbol_len_asamps);
  fprintf('      bit duration      %d syms = %s\n', qsdc_bit_dur_syms,uio.dur(qsdc_bit_dur_s));
  fprintf('      is_qpsdk          %d\n', qsdc_data_is_qpsk);
    
    cipher_len_asamps = frame_pd_asamps - hdr_len_asamps;
    cipher_len_bits   = cipher_len_asamps * round(log2(cipher_m)) / ...
        cipher_symlen_asamps;
    cipher_symlen_s = cipher_symlen_asamps / asamp_Hz;


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
  n_rms = sqrt(mean(ii.^2 + qq.^2));
  if (~isempty(host))
    ncplot.txt(sprintf('%s', host));
  end
  if (1)
    ncplot.txt(sprintf('num samples %d', length(ii)));
    ncplot.txt(sprintf('mean I %.2f', mean(ii)));
    ncplot.txt(sprintf('mean Q %.2f', mean(qq)));
    % ncplot.txt(sprintf('filter %s', filt_desc));
    ncplot.txt(sprintf('E radius %.1f ADCrms', n_rms));
  end
  if (already_balanced)
    ncplot.txt('rebalanced by HDL');
  end
  figure(gcf());  
  %  ncplot.subplot();
  %  ncplot.invisible_axes();


  % DETERMINE THE MESSAGE THAT WAS SENT
  fprintf('\n(By the way, you can use gen_data.m to generate data files.)\n');
  while(1)
    msg_fname = tvars.ask('message file that alice txed to bob','msg_fname');
     fid=fopen(msg_fname, 'r', 'l', 'US-ASCII');
    if (fid<0)
      fprintf('ERR: cant open file\n');
      continue;
    end
    [data cnt] = fread(fid, 'uint8');
    fprintf('read %s (%d bytes)\n', msg_fname, cnt);
    fclose(fid);
    break;
  end
  % TURN IT INTO BITS
  txed_bits=zeros(cnt,8);
  for k = 1:cnt
    b=flipdim(dec2bin(data(k))=='1',2);
    txed_bits(k,1:length(b))=b;
  end
  txed_bits=reshape(txed_bits.',[],1); % into vert vect
  % 'BITS'
  % txed_bits(1:8)
  fprintf(' num txed bits %d\n', length(txed_bits));

  % ENCODE EACH BIT
  % each bit is replaced by a code generated by one of the two generators.
  % The number of codebits (cbits) per data bit is qsdc_code_len_cbits
  % The codes are derived from the two irreducable polynomials of order 5
  code = flipdim([1 0 1 0 0 1 1 0 1 0],2);
  bcode = repmat(code, 1,qsdc_bit_dur_syms/length(code));

  %  lfsr0 = lfsr_class(hex2dec('25'), hex2dec('0a')); % cp 100101  rst_st  001010
  %  lfsr1 = lfsr_class(hex2dec('3b'), hex2dec('35')); % cp 111011  rst_st  110101
  % code0 = lfsr0.gen(qsdc_code_len_cbits).';
  txed_coded = zeros(length(txed_bits), length(bcode));
  for k=1:length(txed_bits)
    if (txed_bits(k)==0)
      txed_coded(k,:)=~bcode;
    else
      txed_coded(k,:)=bcode;
    end
  end
  % 'CODED'
  txed_coded=reshape(txed_coded.',[],1); % into ver vect
  fprintf(' num codebits %d\n', length(txed_coded));
  
  % SYMBOLIZE THE CODE BITS
  if (qsdc_data_is_qpsk)
    txed_syms = ([1 2] * reshape(txed_coded,2,[])).';
    code_syms = ([1 2] * reshape(code,2,[])).';
  else
    txed_syms = txed_coded;
    code_syms = code.';
  end
  % 'SYMBOLS'
  % txed_syms(1:8)
  sym_i = 1;
  fprintf(' num txed symbols %d\n', length(txed_syms));

  % SAMPLE THE SYMBOLS
  txed_asamps = reshape(repmat(txed_syms.',qsdc_symbol_len_asamps,1),[],1);
  code_asamps = reshape(repmat(code_syms.',qsdc_symbol_len_asamps,1),[],1);
  fprintf(' num txed asamps %d\n', length(txed_asamps));
  
  txed_frames = ceil(length(txed_asamps) / qsdc_data_len_asamps);
  fprintf(' num txed frames %d\n\n', txed_frames);
  

  find_hdr = 1;
  calc_sweep_ang= 0;

  if (calc_sweep_ang)
    frame_pd_asamps = floor(frame_pd_asamps/10);
  end

    

  mean_pwr_dBm = mvars.get('mean_pwr_dBm', []);
  if (~isempty(mean_pwr_dBm)) 
    mean_pwr_dBm = mvars.ask('mean signal pwr (dB,)', 'mean_pwr_dBm', -inf); %OBSOLETE
  else
    mon_pwr_dBm = mvars.ask('monitor pwr (dBm)', 'monitor_pwr_dBm', -inf);
    body_rat_dB = mvars.get('body_rat_dB',0);
    if (body_rat_dB)
      ext_rat_dB = mvars.get('ext_rat_dB',0);
      fprintf('  body/mean ratio %.1f dB\n', body_rat_dB);
      fprintf('  extinction (hdr/body) ratio %.1f dB\n', ext_rat_dB);
      mean_pwr_dBm = mon_pwr_dBm + body_rat_dB;
    else
      d=tvars.get('sig_minus_mon_dB',0);
      sig_minus_mon_dB = mvars.ask('add what to monitor to get sig pwr', 'sig_minus_mon_dB',d);
      mvars.set('sig_minus_mon_dB',sig_minus_mon_dB);
      mean_pwr_dBm = mon_pwr_dBm + sig_minus_mon_dB;
      ext_rat_dB = mvars.ask('pilot/body ext ratio (dB)', 'ext_rat_dB',0);
    end
  end

  body_pwr_mW = 10^(mean_pwr_dBm/10);
  fprintf('  body pwr %sW\n', uio.sci(body_pwr_mW/1000));
  n = body_pwr_mW/1000 * qsdc_bit_dur_s / (h_JpHz * c_mps / wl_m);
  fprintf('  body pwr %.2fdB = %sW = %.1f photons per bit\n', mean_pwr_dBm, uio.sci(body_pwr_mW/1000), n);


  mvars.save();

  cipher_frame_qty=0;
  cipher_en = mvars.get('cipher_en',0);



  
  

  
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  fprintf('  lfsr rst st x%s\n', lfsr_rst_st);
  host = mvars.get('host','');

  lfsr = lfsr_class(hex2dec('a01'), hex2dec(lfsr_rst_st));
  lfsr_idx = 0;
  cipher_lfsr = lfsr_class(hex2dec('280001'), hex2dec('abcde'));
  % cipher_lfsr = lfsr_class(hex2dec('280001'),    hex2dec('aabbc'));
  cipher = zeros(cipher_len_bits, 1);
  
  sim_hdl.do = 0;
  % sim_hdl.do = tvars.ask_yn('simulate HDL processing', 'sim_hdl');
  if (sim_hdl.do)
    sim_hdl.num_lsb_discard = tvars.ask('number of LSBs to discard', 'num_lsb_discard');
    sim_hdl.mag_w = tvars.ask('bitwidth of magnitudes', 'mag_w');
    sim_hdl.num_slices = 4;
  end
  tvars.save();


  ii = m(:,1);
  qq = m(:,2);



          
  hdr_pwr_thresh = mvars.get('hdr_pwr_thresh');
  %  calc_pwr_dets(hdr_pwr_thresh, ii, qq, 16, hdr_len_asamps, fname_s);

  frame_pd_s  = frame_pd_asamps/asamp_Hz;
  frame_pd_us = frame_pd_asamps/asamp_Hz*1e6;
  l = length(ii);

  fprintf('  fsamp = %.3f GHz\n', asamp_Hz/1e9);
  fprintf('  num samples %d asamps = %d Ksamps = %s\n', l, round(l/1024), uio.dur(l/asamp_Hz));
  fprintf('  num frames  %d\n', floor(l/frame_pd_asamps));

  frame_qty = floor(l/frame_pd_asamps);

  % do this instead of multiplying frame_qty by two.
  
  fprintf('  frame_pd    %d samps = %s\n', frame_pd_asamps, uio.dur(frame_pd_s));
  fprintf('  hdr_len     %d bits  = %s\n', hdr_len_bits, uio.dur(osamp*hdr_len_bits/asamp_Hz));



          
  
  iq_mx = max(max(abs(ii)),max(abs(qq)));










  
  filt_desc='none';
  fcut_Hz = asamp_Hz*3/16;
  filt_len = 8;
  use_filt = 0;
  %  use_filt = tvars.ask_yn('filter ', 'use_filt', use_filt);
  
  do_eye=1;
  tx_hdr_twopi = mvars.get('tx_hdr_twopi',0);



  ncplot.subplot(1,2);
  if (~already_balanced)
    % IQ SCATTERPLOT

    calc_rebal=0;
    res.i_off = -2;
    res.q_off = -10;
    res.th_deg = 179;
    res.i_factor = 1;
    res.q_factor = 1.08;
    fprintf('\nusing default REBAL for ZCU2\n');

    i_off = res.i_off;
    q_off = res.q_off;
    th_rad=res.th_deg*pi/180;
    c=cos(th_rad);
    s=sin(th_rad);
    im2=[res.i_factor 0;0 res.q_factor]*[c s;-s c]*[ii+i_off qq+q_off].';
    mx=max(abs(im2(:)));
    ii = im2(1,:).';
    qq = im2(2,:).';
    radius_mean=sqrt(mean(ii.^2+qq.^2));
    
    ncplot.subplot();
    ncplot.iq(ii,qq,iqopt);
    ncplot.txt(sprintf('qnic %s', host));
    ncplot.txt(sprintf('sqrt(<I^2+Q^2>) %.1f ADC', radius_mean));
    
    if (0)
      ncplot.txt(sprintf('hdr twopi %d', mvars.get('tx_hdr_twopi',0)));
      ncplot.txt('rebalance parameters');
      ncplot.txt(sprintf('  i_off    %d', i_off));
      ncplot.txt(sprintf('  q_off    %d', q_off));
      ncplot.txt(sprintf('  i_factor %g', res.i_factor));
      ncplot.txt(sprintf('  q_factor %g', res.q_factor));
      ncplot.txt(sprintf('  c %.1f deg', th_rad*180/pi));
      ncplot.txt(sprintf('  (radius %.1f)', radius_mean));
    end
    %   xlim([-1.1 1.1]*mx);    ylim([-1.1 1.1]*mx);
    ncplot.title({fname_s; 'Corrected IQ scatterplot'});
    uio.pause('see rebalanced IQ plot');
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
%   x = 1:(h_l*n);


  if (0)
    ncplot.subplot(1,2);
    plot((1:l)-1, ii(1:l),'.');
    return;
  end

  mean_before_norm = 0;




  
  tvars.save();
  
  m=max(max(abs(ii)),max(abs(qq)));
  %   fprintf('max abs %d, %d\n', max(abs(ii)), max(abs(qq)));


  tvars.save();

  c_all  = zeros(h_l,1);
  n_all  = 0;



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

  if (cipher_en)
    cipher_en = tvars.ask_yn('analyze cipher','analyze_cipher',0);
    if (cipher_en)
      ignore_ns = tvars.ask('ignore time after hdr (ns)','ignore_ns',0);
      ignore_asamps = round(ignore_ns * 1e-9 * asamp_Hz);
    end
  end

  
  do_calc_pwr = 0; % tvars.ask_yn('calc pwr','calc_pwr',0);



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
  search_mode=0;
  body_adj_asamps = 0;

  if (0)
    opt_skip=mvars.ask('skip how many frames', 'opt_skip_frames', 1);
    s_i = opt_skip * frame_pd_asamps+1;
  else
    opt_skip=mvars.ask('skip how many pilots', 'opt_skip_frames', 1);
    lfsr.reset();
    
    hdr = lfsr.gen(hdr_len_bits);
    hdr = repmat(hdr.',osamp,1);
    hdr = hdr(:)*2-1;
    ci = corr_circ(hdr, ii);
    cq = corr_circ(hdr, qq);
    c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
    c2_max=zeros(10,1);
    max(c2)
    s_i=0;
    f_l=floor(length(ii)/frame_pd_asamps); % for each frame    
    for f_i=1:f_l % for each frame
      % frame_off is zero based.
      frame_off=(f_i-1)*frame_pd_asamps;
      rng = (1:frame_pd_asamps)+frame_off;
      [mx mxi] = max(c2(rng));
      c2_max(f_i)=mx;
      if (f_i==4)
        s=std(c2_max(1:4));
        mx_m=mean(c2_max(1:4));
      elseif (f_i>4)
        k =  mx>(mx_m+s*4);
        % fprintf('%d   mx %d  k %d\n', f_i, mx, k)
        if (k==1)
          s_i = rng(1)-1+mxi + opt_skip * frame_pd_asamps;
          % opt_skip = frame_off/frame_pd_asamps;
          break;
        end
      end
    end

    rng=1:(s_i+frame_pd_asamps);
    t_us = 1e6*(rng-1).'/asamp_Hz;
    plot(t_us, ii(rng), '.-', 'Color',coq(1,:));
    plot(t_us, qq(rng), '.-', 'Color',coq(2,:));
    line([1 1]*t_us(s_i),[0 max(ii)],'Color','red');

    % uio.pause();
  end

  % TIME DOMAIN PLOT of NON-SKIPPED FRAME
  if (frame_by_frame)

    off_us = 0;

    rng = (1:round(frame_pd_asamps*1.2)) + s_i;
    frame_off = rng(1);

    % CORRELATE FOR HDR
    hdr = lfsr.gen(hdr_len_bits);
    lfsr_idx = 1;
    hdr = repmat(hdr.',osamp,1);
    hdr = hdr(:)*2-1;
    ci = corr(hdr, ii(rng));
    cq = corr(hdr, qq(rng));
    c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
    search_cmax = max(c2);

    % CORRELATE FOR BCODE
    cbi = corr(code_asamps*2-1, ii(rng));
    cbq = corr(code_asamps*2-1, qq(rng));
    ccode = sqrt(cbi.^2 + cbq.^2)/hdr_len_bits;
    
    % TIME PLOT
    ncplot.subplot(1,2);
    ncplot.subplot();
    if (1)
      t_us = 1e6*(rng-1).'/asamp_Hz;
      xunits = 'us';
    else
      t_us = rng;
      xunits = 'samples';
    end
    plot(t_us, ii(rng), '.-', 'Color',coq(1,:));
    plot(t_us, qq(rng), '.-', 'Color',coq(2,:));
    % plot(t_us, c2, '-', 'Color','red');
    
    plot(t_us, ccode, '-', 'Color','yellow');    
    [c2_mx c2_mi]=max(c2);
    line([1 1]*t_us(c2_mi),[0 c2_mx],'Color','red');
    mx = max(max(ii(rng)), max(qq(rng))); % just for plot ylim
    ylim([-mx mx]);
    if (0)
      if (c2_mi+hdr_len_asamps <= frame_pd_asamps)
        line([1 1]*t_us(c2_mi+hdr_len_asamps),[0 c2_mx],'Color','magenta');
        % dont plot hdr if not all of it is there.
        h_rng = c2_mi-1+(0:hdr_len_bits-1)*osamp + 2;
        h_rng = [h_rng; h_rng+1];
        h_rng = reshape(h_rng,[],1);
        plot(t_us(h_rng), ii(h_rng+frame_off), '.', 'Color', co(1,:));
        plot(t_us(h_rng), qq(h_rng+frame_off), '.', 'Color', co(2,:));
      end
    end
    if (is_alice)
      plot(t_us, aug0(rng)*mx,    '-', 'Color','green'); % pwr_det
      plot(t_us, aug5(rng)*mx*.5, '-', 'Color','magenta'); % pwr_event_iso
    end
    plot(t_us, aug1(rng)*mx, '-', 'Color','blue');   % dbg_hdr_det
    idx=find(aug1(rng),1);
    if (idx)
      ncplot.txt(sprintf('detection at idx %d = %s', ...
                         idx, uio.dur(t_us(idx))));
    end
    %                  plot(t_us, aug2(rng)*mx, '-', 'Color','magenta');% hdr_sync (not dlyd)
    % plot(t_us, aug3(rng)*mx, '-', 'Color','black');  % hdr_found

    % plot(t_us, aug4(rng)*1000, '-', 'Color','blue');
    xlim([t_us(1) t_us(end)]);
    
    [mx mi]=max(pwr_all(rng));

    if (host)
      ncplot.txt(sprintf('host %s', host));
    end
    %                ncplot.txt(sprintf('frame %d', f_i));
    %                ncplot.txt(sprintf('offset %d = time %.1f us', frame_off, frame_off*frame_pd_us));
    ncplot.txt(sprintf('max sqrt(I^2+Q^2)  %.1f', mx));
    ncplot.txt(sprintf('det:  pwr_thresh %d  corr_thresh %d', ...
                       mvars.get('hdr_pwr_thresh'), mvars.get('hdr_corr_thresh')));
    ncplot.txt(sprintf('corr max %d at %.3fms = idx %d', ...
                       round(c2_mx), t_us(c2_mi), c2_mi));


    aug2_sub =   aug2(rng);
    ai=find(aug2_sub, 1);
    if (~isempty(ai))
      ncplot.txt(sprintf('      aug2 %d',ai));
    end
    % ylim([-1.2 1.2]*mx);
    xlabel(sprintf('time (%s)',xunits));
    ylabel('amplitude (adc)');
    ncplot.title({mname; fname_s});

    if (1)
      [mxv mxi]=max(c2);
      % Because our corr pattern uses +1 for 1 and -1 for 0,
      % A positive correlation lies along pos x axis.
      hdr_ph_deg = atan2(cq(mxi),ci(mxi))*180/pi;
      ncplot.subplot();
      h_rng = frame_off+c2_mi-1+(1:hdr_len_asamps);
      ncplot.iq(ii(h_rng),qq(h_rng));
      h_srng = frame_off+c2_mi-1 + floor(osamp/2) + (0:hdr_len_bits-1)*osamp;
      plot(ii(h_srng),qq(h_srng),'.', 'Color','blue');
      h_srng = frame_off+c2_mi-1 + floor(osamp/2)+1 + (0:hdr_len_bits-1)*osamp;
      plot(ii(h_srng),qq(h_srng),'.', 'Color','blue');
      mx=max([abs(ii);abs(qq)]);
      c=cos(hdr_ph_deg*pi/180)*mx;
      s=sin(hdr_ph_deg*pi/180)*mx;
      line([0 c],[0 s],'Color','blue');
      ncplot.title({'IQ plot of header'; fname_s});
      ncplot.txt(sprintf('phase %d deg', round(hdr_ph_deg)));
    end

    uio.pause('This is the frame you selected.  Reception will start here.');
  end % if show al land not searjc

  opt_offset_asamps = frame_off-1 + c2_mi-1; % zero based

  cheat = tvars.ask_yn('"cheat" by estimating phase of body','cheat',0);
  
  body_ph_offset_deg = 0;
  if (~cheat)
    fprintf('\nThe body phase offset will be added to the header phase to get the body phase.\n');
    body_ph_offset_deg = mvars.ask('body phase offset (deg)','body_ph_offset_deg',0);
  end
  rx_going=0;
  
  n_left = n;
  itr=1;
  while ((n_left>0)&&(itr<=num_itr))

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

      data_derot_degs=zeros(nn,1);
      
      frame_bers   = zeros(frame_qty,1);

      si = 1               + (itr-1)*frame_qty*frame_pd_asamps;
      ei = nn*frame_pd_asamps + (itr-1)*frame_qty*frame_pd_asamps;

      if (frame_by_frame)
        ncplot.subplot(2,1);
        plot_eye(si,ei,itr,[]);
        if (use_filt)
          filt_desc = sprintf('gauss fcut %.1fMHz  len %d', fcut_Hz/1e6, filt_len);
          ii(si:ei) = filt.gauss(ii(si:ei), asamp_Hz, fcut_Hz, filt_len);
          qq(si:ei) = filt.gauss(qq(si:ei), asamp_Hz, fcut_Hz, filt_len);
        end
      end
      
      if (sim_hdl.do)
        lfsr.reset();                    
        hdr = lfsr.gen(hdr_len_bits);
          
        ci = corr_circ(hdr, ii);
        cq = corr_circ(hdr, qq);
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
      
      sym_err_cnt=0;
      sym_cnt=0;


      sweep_angs = [];
      frame_i=0;

      % Running sum per bit
      bit_i =1;
      bit_ii=0;
      bit_qq=0;
      bit_n =1;

      allbit_errs=0;
      allbit_cnt=0;
      
      body_adj_asamps = mvars.get('body_adj_asamps',-34);


      
      for f_i=1:nn % for each frame

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

          % frame_off is zero based.
          frame_off=(f_i-1)*frame_pd_asamps + (itr-1)*frame_qty*frame_pd_asamps + opt_offset_asamps;

          if (frame_off+frame_pd_asamps > length(ii))
            break;
          end
            
          rng = (1:frame_pd_asamps)+frame_off;

          % correlate for header in this frame
          ci = corr(hdr, ii(rng));
          cq = corr(hdr, qq(rng));
          c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
          [mxv mxi]=max(c2);

          % Because our corr pattern uses +1 for 1 and -1 for 0,
          % A positive correlation lies along pos x axis.
          hdr_ph_deg = atan2(cq(mxi),ci(mxi))*180/pi;
          hdr_phs_deg(f_i)=hdr_ph_deg;
          hdr_phs_deg_l = f_i;

          
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



          
          if (frame_by_frame)

            % TIME DOMAIN PLOT OF CURRENT FRAME
            ncplot.subplot(1,2);
            ncplot.subplot();
            if (1)
              t_us = 1e6*(rng-1).'/asamp_Hz;
              xunits = 'us';
            else
              t_us = rng;
              xunits = 'samples';
            end
            plot(t_us, ii(rng), '.-', 'Color',coq(1,:));
            plot(t_us, qq(rng), '.-', 'Color',coq(2,:));
            %plot(t_us, c2, '-', 'Color','red');
            [c2_mx c2_mi]=max(c2);
            %line([1 1]*t_us(c2_mi),[0 c2_mx],'Color','red');

            mx = max(mx, max(abs(c2))); % just for plot ylim
            if (c2_mi+hdr_len_asamps <= frame_pd_asamps)
              line([1 1]*t_us(c2_mi+hdr_len_asamps),[0 c2_mx],'Color','magenta');
              % dont plot hdr if not all of it is there.
              h_rng = c2_mi-1+(0:hdr_len_bits-1)*osamp + 2;
              h_rng = [h_rng; h_rng+1];
              h_rng = reshape(h_rng,[],1);
              plot(t_us(h_rng), ii(h_rng+frame_off), '.', 'Color', co(1,:));
              plot(t_us(h_rng), qq(h_rng+frame_off), '.', 'Color', co(2,:));
            end

            if (~rx_going || ~body_adj_asamps)

              % CORRELATE FOR BCODE
              cbi = corr(code_asamps*2-1, ii(rng));
              cbq = corr(code_asamps*2-1, qq(rng));
              ccode = sqrt(cbi.^2 + cbq.^2)/hdr_len_bits;
              plot(t_us, ccode, '-', 'Color','yellow');
              th = std(ccode(qsdc_data_pos_asamps:end));
              % Find best starting offset
              el = qsdc_symbol_len_asamps*length(code); % 80
              si = (floor(qsdc_data_pos_asamps/el)-1)*el; % zero based. 240
              sl = (floor((length(rng)-si)/el)-1)*el;
              si = si+1;
              ei = si+sl-1;
              ccode=sum(reshape(ccode(si:ei),el,[]).');
              [mx mi] = max(ccode);
              si = mod(qsdc_data_pos_asamps, el);
              body_adj_asamps = mod((mi-1)-si + floor(el/2),el)-floor(el/2);
              fprintf('ccode max at %d,  si %d   adj %d\n', mi, si, body_adj_asamps);
            end

            line([1 1]*t_us(qsdc_data_pos_asamps + body_adj_asamps+1), ...
                 [0 c2_mx],'Color','blue');
            if (qsdc_data_pos_asamps + body_adj_asamps+qsdc_data_len_asamps-1 > length(t_us))
              qsdc_data_pos_asamps
              body_adj_asamps
              qsdc_data_len_asamps
              qsdc_data_pos_asamps+body_adj_asamps+qsdc_data_len_asamps-1

              uio.pause('WARN: alices data seems to collides with next hdr. adj sync dly and redo?');
            else
              ei=min(qsdc_data_pos_asamps + body_adj_asamps+qsdc_data_len_asamps-1,length(t_us));
              line([1 1]*t_us(ei), [0 c2_mx],'Color','blue');
            end
            xlim([t_us(1) t_us(end)]);
            [mx mi]=max(pwr_all(rng));
            if (1)
              if (host)
                ncplot.txt(sprintf('host %s', host));
              end
              ncplot.txt(sprintf('frame %d = %.3fus', f_i, frame_off*frame_pd_us));
              %         ncplot.txt(sprintf('offset %d = time %.1f us', frame_off, frame_off*frame_pd_us));
              ncplot.txt(sprintf('max sqrt(I^2+Q^2)  %.1f', mx));
              if (find_hdr)
                ncplot.txt(sprintf('det:  pwr_thresh %d  corr_thresh %d', ...
                                   mvars.get('hdr_pwr_thresh'), mvars.get('hdr_corr_thresh')));
                ncplot.txt(sprintf('corr max %d at %.3fms = idx %d', ...
                                   round(c2_mx), t_us(c2_mi), c2_mi));
              end
            end
            % ylim([-1.2 1.2]*mx);
            xlabel(sprintf('time (%s)',xunits));
            ylabel('amplitude (adc)');
            ncplot.title({mname; fname_s});

            h_rng = rng(1)-1+(1:hdr_len_asamps);
            b_rng_off = frame_off + qsdc_data_pos_asamps + body_adj_asamps;
            b_rng = b_rng_off+(1:qsdc_data_len_asamps);

            % DRAW CORRELATION WITH CODE
            ncplot.subplot();
            plot(1:length(ccode),ccode);
            xlabel('sample');
            title('correlation with code');
            uio.pause();

            % DRAW IQ PLOT OF HEADER
            ncplot.subplot();
            ncplot.iq(ii(h_rng),qq(h_rng));
            h_srng = frame_off+c2_mi-1 + floor(osamp/2) + (0:hdr_len_bits-1)*osamp;
            plot(ii(h_srng),qq(h_srng),'.', 'Color','blue');
            plot(ii(h_srng+1),qq(h_srng+1),'.', 'Color','blue');
            plot(ii(b_rng),qq(b_rng),'.', 'Color','green');
            mx=max([abs(ii);abs(qq)]);
            c=cos(hdr_ph_deg*pi/180)*mx;
            s=sin(hdr_ph_deg*pi/180)*mx;
            line([0 c],[0 s],'Color','blue');
            ncplot.title({'IQ plot of header'; fname_s});
            ncplot.txt(sprintf('frame %d', f_i));
            ncplot.txt(sprintf('phase %d deg', round(hdr_ph_deg)));
            
            if (rx_going)
              uio.pause('review frame');
            else
              
              
              uio.print_wrap('The region of time plot between the two dark blue lines is where the data should be.  If not, you can adjust it.');
              fprintf('Recommend: %d\n', body_adj_asamps);
              body_adj_asamps = mvars.ask('data body adj (asamps)','body_adj_asamps',0);
              mvars.save();
              %            body_adj_ns = tvars.ask('data body adj (ns)','body_adj_ns',1);
              %            tvars.save();
              %            body_adj_asamps = round(body_adj_ns*1e-9*asamp_Hz);
              %            fprintf('    that is %d samples\n', body_adj_asamps);
              rx_going=1;
            end
          end % if frame by frame

          frame_i=frame_i+1;
          % data = cipher_lfsr.gen(bits_per_frame);

          b_rng_off = frame_off + qsdc_data_pos_asamps + body_adj_asamps;
          b_rng = b_rng_off+(1:qsdc_data_len_asamps);
          if (cheat)
            derot_deg = calc_derot(ii(b_rng),qq(b_rng), hdr_ph_deg);
            desc='ideal';
          elseif (~cheat)
            derot_deg = hdr_ph_deg + body_ph_offset_deg;
            desc='hdr ang';
          else
            derot_deg = 0;
            desc='raw';
          end
          iiqq = geom.rotate(-derot_deg*pi/180, [ii(b_rng).';qq(b_rng).']);
          d_ii=iiqq(1,:).';
          d_qq=iiqq(2,:).';

          % ignore transition symbols
          nsyms = qsdc_data_len_asamps/qsdc_symbol_len_asamps;
          trans_rng=(0:nsyms-1)*qsdc_symbol_len_asamps;
          e_rng = setdiff(1:qsdc_data_len_asamps, trans_rng+1);
          e_rng = setdiff(e_rng,                  trans_rng+qsdc_symbol_len_asamps);
          e_rng=e_rng(:);

          % CALC SYMBOL ERRORS IN FRAME
          % TODO: this is really only coded for BPSK.  do other mods too.
          err_sum=0;
          errmsk=logical(zeros(nsyms,1));
          rxed_ii = zeros(nsyms,1);
          rxed_qq = zeros(nsyms,1);
          sl = qsdc_symbol_len_asamps;
          bit_i_sav = bit_i;
          bit_n_sav = bit_n;
          bit_errs = 0;
          bit_cnt  = 0;
          for k=1:nsyms
            if (sym_i+k-1 > length(txed_syms))
              break;
            end
            % per-symbol mean, ignoring transition if possible
            if (sl>2)
              sym_ii=mean(d_ii((k-1)*sl+(2:sl-1)));
              sym_qq=mean(d_qq((k-1)*sl+(2:sl-1)));
            else
              sym_ii=mean(d_ii((k-1)*sl+(1:sl)));
              sym_qq=mean(d_qq((k-1)*sl+(1:sl)));
            end
            rxed_ii(k) = sym_ii;
            rxed_qq(k) = sym_qq;
            
            c=txed_syms(sym_i+k-1); % current codebit
            e = logical(c ~= (sym_ii<0));
            err_sum = err_sum+e;
            errmsk(k) = e;
            nsyms_actual = k;
          end
          
          symbol_ber = err_sum/nsyms_actual;
          if (cheat && (symbol_ber>.5))
            err_sum = nsyms_actual-err_sum;
            symbol_ber = 1-symbol_ber;
            derot_deg = derot_deg +180;
            d_ii=-d_ii;
            d_qq=-d_qq;
            rxed_ii = -rxed_ii;
            rxed_qq = -rxed_qq;
            errmsk = ~errmsk;
          end
          if (k<nsyms)
            errmsk(k+1:nsyms)=0;
          end

          symbol_bers(f_i) = symbol_ber;
          sym_err_cnt = sym_err_cnt + err_sum;
          sym_cnt = sym_cnt + nsyms_actual;
          data_derot_degs(f_i)=derot_deg;
          
          for k=1:nsyms
            if (sym_i+k-1 > length(txed_syms))
              break;
            end
            % Take mean of symbols over duration of bit,
            % multiplied by sign of bcode.
            % This is essentially a correlation with bcode.
            bit_ii = bit_ii + rxed_ii(k) * (bcode(bit_n)*2-1);
            bit_qq = bit_qq + rxed_qq(k) * (bcode(bit_n)*2-1);
            bit_n  = bit_n + 1;
            if (bit_n > qsdc_bit_dur_syms)
              % fprintf('bit %d expect %d  is %.2f\n', bit_i, txed_bits(bit_i), bit_ii);
              bit_errs = bit_errs + ((bit_ii<0) ~= txed_bits(bit_i));
              bit_cnt = bit_cnt+1;
              bit_i=bit_i+1;
              bit_ii=0;
              bit_qq=0;
              bit_n=1;
            end
            sym_i = sym_i + 1;
          end
          

          allbit_errs = allbit_errs+bit_errs;
          allbit_cnt  = allbit_cnt +bit_cnt;

          if (frame_by_frame)
            % PlOT DATA VS INDEX, SUPERIMPOSE ERRORS IN REGD
            ncplot.init();
            ncplot.subplot(1,2);
            ncplot.subplot();
            mx=max(max(d_ii),max(d_qq));
            plot(1:qsdc_data_len_asamps, d_ii,'-','Color',coq(1,:));
            plot(1:qsdc_data_len_asamps, d_qq,'-','Color',coq(2,:));

            is=(frame_i-1)*qsdc_data_len_asamps+1;
            ie=min(is+qsdc_data_len_asamps-1, length(txed_asamps));
            txrng= is:ie;
            plot(txrng-(is-1), (2*txed_asamps(txrng)-1)*mx/2, '-','Color','yellow');

            
            if (0) % emphasize points
              plot(e_rng, d_ii(e_rng),'.','Color',ch(1,:));
              plot(e_rng, d_qq(e_rng),'.','Color',ch(2,:));
            else   % draw line at means
              for k=1:nsyms
                line((k-1)*qsdc_symbol_len_asamps+[1 qsdc_symbol_len_asamps], ...
                     rxed_ii(k)*[1 1],'Color',ch(1,:));
                line((k-1)*qsdc_symbol_len_asamps+[1 qsdc_symbol_len_asamps], ...
                     rxed_qq(k)*[1 1],'Color',ch(2,:));
                bit_n_sav = bit_n_sav+1;
                if (bit_n_sav >= qsdc_bit_dur_syms) % black divider between bits
                  line(k*qsdc_symbol_len_asamps+.5*[1 1],[-1 1]*mx/2,'Color','black');
                  bit_i_sav=bit_i_sav+1;
                  bit_n_sav=0;
                end
              end
            end     
            symrng = (0:(nsyms-1)).'*qsdc_symbol_len_asamps + qsdc_symbol_len_asamps/2+.5;
            plot(symrng(errmsk), rxed_ii(errmsk), '.', 'Color','red');
            ncplot.txt(sprintf('frame %d', frame_i));
            ncplot.txt(desc);
            ncplot.txt(sprintf('derotated %.1f deg%s', derot_deg,util.ifelse(cheat,' (cheat)','')));
            
            ncplot.txt(sprintf('symbol BER %g', symbol_ber));

            ncplot.txt(sprintf('data bits %d  errors %d', bit_cnt, bit_errs));
            

          xlabel('index');
          ncplot.title({'time plot of QSDC data'; fname_s});

          if (0)
            ci = corr_circ(data(1:32), d_ii);
            cq = corr_circ(data(1:32), d_qq);
            c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
            [ds dsi] =  max(c2);
            if (dsi>0)
              line(dsi, [0 c2_mx],'Color','black');
            end
          end


          % DRAW IQ PLOT OF BODY
          ncplot.subplot();
          ncplot.iq(d_ii, d_qq);
          h_srng = body_adj_asamps+frame_off+qsdc_data_pos_asamps+(0:nsyms-1)*4 + 2;
          plot(d_ii(e_rng), d_qq(e_rng), '.', 'Color','blue');
          rad = sqrt(mean(d_ii(e_rng).^2+d_qq(e_rng).^2));
          ncplot.txt(desc);
          ncplot.txt(sprintf('frame %d', frame_i));
          ncplot.txt(sprintf('derotated by %.1f', derot_deg));
          ncplot.txt(sprintf('sqrt <I^2+Q^2> = %.1f', rad));
          ncplot.title({'IQ plot of QSDC data'; fname_s});
          end % if frame by frame

            

          
          if (frame_by_frame)                  
            choice = uio.ask_choice('(n)ext, goto (e)nd, or (q)uit', 'neq', choice);
            if (choice=='q')
              return;
            elseif (choice=='e')
              frame_by_frame=0;
            end
          end

          if (is+qsdc_data_len_asamps-1 >  length(txed_asamps))
            break;
          end
      end % for f_i (each frame)


      cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
      cipher_symlen_s = cipher_symlen_asamps / asamp_Hz;


      body_pwr_mW = 10^(mean_pwr_dBm/10);
      fprintf('body pwr %sW\n', uio.sci(body_pwr_mW/1000));
      n = body_pwr_mW/1000 * qsdc_bit_dur_s / (h_JpHz * c_mps / wl_m);
      fprintf('body pwr %.2fdB = %sW = %.1f photons per bit\n', mean_pwr_dBm, uio.sci(body_pwr_mW/1000), n);

      %uio.pause();
      

      fprintf('symbol BER %d/%d = %g\n',  ...
              sym_err_cnt, sym_cnt, max(1,sym_err_cnt)/sym_cnt);

      fprintf('  data BER %d/%d = %g\n', ...
              allbit_errs, allbit_cnt, max(1,allbit_errs)/allbit_cnt);

      uio.pause();


      ncplot.init();
      %hdr_phs_deg=mod(hdr_phs_deg+180,360)-180;
      
      %      hdr_phs_deg = util.mod_unwrap(hdr_phs_deg, 360);
      %data_derot_degs = mod(data_derot_degs+180,360)-180;
      %  data_derot_degs = util.mod_unwrap(data_derot_degs, 360);
      hdr_phs_deg     = ctr_phases(hdr_phs_deg, hdr_phs_deg(3));
      data_derot_degs = ctr_phases(data_derot_degs, data_derot_degs(3));
      fr_t_us = (0:hdr_phs_deg_l-1)*frame_pd_s*1e6;
      ei=hdr_phs_deg_l;
      plot(fr_t_us, hdr_phs_deg(1:ei), '.-','Color',coq(1,:));
      plot(fr_t_us, data_derot_degs(1:ei), '.-','Color',coq(2,:));
      %        s=sprintf('magenta: body phase  mean %d deg', round(mean(body_phs_unwrap_deg(1:cipher_frame_qty))));
      if (cheat)
        d_deg = hdr_phs_deg(1:ei) - data_derot_degs(1:ei);
        d_deg = ctr_phases(d_deg, d_deg(3));
        plot(fr_t_us, d_deg,'Color',coq(3,:));
      end
      ncplot.txt(sprintf('   blue: hdr ph  mean %d deg', round(mean(hdr_phs_deg))));
      ncplot.txt(sprintf('  green: body ph mean %d deg', round(mean(data_derot_degs))));
      if (cheat)
        ncplot.txt(sprintf('mean hdr-body %d deg', round(mean(d_deg))));
      end
      
      %        diff_deg = mod(body_phs_unwrap_deg - phs_unwrap_deg+180,360)-180;
      xlabel('time (us)');
      ylabel('phase (deg)');
      ncplot.title({'Phase drift'; fname_s});
      
      return;
      
      
      n_left = n_left - nn;

      if (1)
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
        ncplot.txt(sprintf('  bob hdr at idx %d\n', mi));
        ncplot.txt(sprintf('alice hdr at idx %d\n', a_mi));
        ncplot.txt(sprintf('  ideal sync_dly %d\n', mi-a_mi));
      end
      rng=si:ei;
      ncplot.txt(sprintf('  I  mean %.1f  std %.1f', mean(ii(rng)), std(ii(rng))));
      ncplot.txt(sprintf('  Q  mean %.1f  std %.1f', mean(qq(rng)), std(qq(rng))));




      
      
      ncplot.subplot();
      hdr_phs_deg(1)=mod(hdr_phs_deg(1)+180,360)-180;
      phs_unwrap_deg = util.mod_unwrap(hdr_phs_deg, 360);
      %      fx=[opt_skip frame_qty-1];

      if (0)
        fx = (opt_skip+1:cipher_frame_qty).';
        p=polyfit(fx, phs_unwrap_deg(fx), 1);
        fy=polyval(p, fx);
        plot((fx-1)*frame_pd_s*1e6, mod(fy+180,360)-180,'-','Color','green');
      end

      plot(fr_t_us, phs_unwrap_deg, '.-','Color',coq(1,:));
      if (find_hdr)
        s='   blue: hdr phase';
      else
        s='   blue: phase';
      end
      xlabel('time (us)');
      ylabel('hdr phase (deg)');
      s=[s sprintf('  mean %d deg', round(mean(phs_unwrap_deg)))];
      s=[s sprintf('  std %.1f deg', std(phs_unwrap_deg))];
      ncplot.txt(s);
      ncplot.title({fname_s;'phase drift'});
      
      if (cipher_en)

        

        if (0)
        plot(fr_t_us(1:cipher_frame_qty), ...
             diff_deg(1:cipher_frame_qty), '.-','Color','red');
        ncplot.txt(sprintf('    red: body minus hdr   mean %d', round(mean(diff_deg(1:cipher_frame_qty)))));
        end

        ncplot.txt(sprintf('twopi %d', tx_hdr_twopi));
        
        %      ncplot.txt(sprintf('avg drift %.1f deg/us (green)', p(1)/(frame_pd_s*1e6)))
        %    ylim([-180 180]);
        ncplot.txt(sprintf('body pwr %.2fdBm = %sW = %.1f photons', mean_pwr_dBm, uio.sci(body_pwr_mW/1000,1), n));
        ncplot.txt(sprintf('BER %d/%d = %.3e', cipher_err_cnt, cipher_bit_cnt, cipher_ber));


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
   ci = corr_circ(pat, ii, 0);
   cq = corr_circ(pat, qq, 0);
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



function phs = ctr_phases(phs, ph_deg)
  ph_deg = mod(ph_deg+180,360)-180;
  phs = mod(phs -ph_deg +180, 360)+ph_deg-180;
end
