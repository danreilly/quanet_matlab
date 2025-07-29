function t9
  import nc.*
  fprintf('sim pwr det by Red Pitaya\n');
  hdr_pd_s = 1e-6;
  hdr_len_s = 100e-9;
  hdr_ph_pct = 75;
  hdr_ph_s = hdr_pd_s*hdr_ph_pct/100;
  
  num_pds = 100;

  rp_fsamp_Hz = 125e6;

  rp_measlen_dur_s = 1e-3;
  rp_measlen_samps = round(rp_measlen_dur_s * rp_fsamp_Hz)

  rp_samps=randn(rp_measlen_samps,1)*25;
  % rp_samps=zeros(rp_measlen_samps,1)*25;

  % Simulate measurement with fsamp err
  rp_fsamp_err_Hz = rp_fsamp_Hz/1e6;
  for k=1:rp_measlen_samps
    t_s = (k-1)/(rp_fsamp_Hz-rp_fsamp_err_Hz);
    
    if (mod(t_s-hdr_ph_s,hdr_pd_s) < hdr_len_s) % hdr
      p = 100 + randn(1,1)*20;
    else % payload
      p = rand(1,1)*20+10;
    end
    %  fprintf(' %d', p);
    rp_samps(k)=round(rp_samps(k)+p);
  end
  rp_samps=filt.gauss(rp_samps, rp_fsamp_Hz, 60e6, 2);
  

  t_us = (0:rp_measlen_samps-1) / rp_fsamp_Hz * 1e6;
  
  ncplot.init();
  [co,ch,cq]=ncplot.colors();

  ncplot.subplot(3,1);
  ncplot.subplot();
  plot(mod(t_us, hdr_pd_s*1e6), rp_samps,'.','Color',cq(1,:));
  xlabel('time (us)');
  title('data eye of (simulated) samples');


  % processing by RP
  
  % RP re-bins data, to a time granularity of hdr_len/hdr_bins
  hdr_bins=8;
  bin_len_s = hdr_len_s / hdr_bins;
  rp_trise_s = 30e-9;
  rp_trise_bins = ceil(rp_trise_s / bin_len_s)
  
  hdr_pd_bins = ceil(hdr_pd_s / bin_len_s);
  % RP might not compute this array but it effectively re-bins the data.
  bins_l = ceil(hdr_pd_s / bin_len_s);

  bins=zeros(bins_l,1);
  bin_cts=zeros(bins_l,1);
  
  for k=1:rp_measlen_samps
    t_s = (k-1)/rp_fsamp_Hz;
    b_i = mod(floor(t_s/bin_len_s),bins_l)+1;
    bins(b_i)=bins(b_i)+rp_samps(k);
    bin_cts(b_i)=bin_cts(b_i)+1;
  end
  for b_i=1:bins_l
    bins(b_i)=round(bins(b_i)/bin_cts(b_i));
  end
  [mxv mxi]=max(bins);
  [mnv mni]=min(bins);
  mdv = round((mxv+mnv)/2);

  % forward search
  he_i   = mxi;
  he_i_n = mod(mxi-1+1, bins_l)+1;
  for b_i=1:bins_l
    if (bins(he_i_n)<mdv)
      break;
    end
    he_i   = he_i_n;
    he_i_n = mod(he_i-1+1, bins_l)+1;
  end
  
  % backward search
  hs_i = mxi;
  hs_i_n = mod(mxi-1-1, bins_l)+1;
  for b_i=1:bins_l
    if (bins(hs_i_n)<mdv)
      break;
    end
    hs_i   = hs_i_n;
    hs_i_n = mod(hs_i-1-1, bins_l)+1;
  end

  rp_hdr_len_bins = mod(he_i - hs_i, bins_l)
  rp_hdr_len_s = rp_hdr_len_bins * bin_len_s;
  

  % loop through header, compute mean
  hds_i = modi(hs_i + max(1,ceil(rp_trise_bins/2)), bins_l);
  hde_i = modi(he_i - max(1,ceil(rp_trise_bins/2)), bins_l);
  hdr_pwr = calc_mean(bins, hds_i, hde_i);  
  
  % loop through body, compute mean
  bds_i = modi(he_i + max(1,ceil(rp_trise_bins)), bins_l);
  bde_i = modi(hs_i - max(1,ceil(rp_trise_bins)), bins_l);
  body_pwr = calc_mean(bins, bds_i, bde_i);
  % RP need not compute variance but we want to know it.
  

  
  
  % ctr of mass of hdr
  bins_hl=floor(bins_l/2);
  ms=0;
  mt=0;
  mc=0;
  for b_i=1:bins_l
    if (bins(b_i)>mdv)
      mt = mt + bins(b_i);
      rb_i = mod(b_i-mxi+bins_hl-1,bins_l)+1;
      % fprintf('%d %d %d\n', b_i, rb_i, bins(b_i));
      ms = ms + bins(b_i)*rb_i;
    end
  end
  m_i = round(ms / mt) + mxi - bins_hl;
  m_i = mod(m_i-1,bins_l)+1;
  

  ncplot.subplot();
  plot(1:bins_l, bins,'.','Color', cq(1,:));
  %  plot(hs_i, bins(hs_i),'.', 'Color','red');
  %  plot(he_i, bins(he_i),'.', 'Color','red');
  if (hds_i < hde_i)
    line([hds_i, hde_i],[1 1]*hdr_pwr,'Color','blue');
  else
    line([1, hde_i],[1 1]*hdr_pwr,'Color','blue');
    line([hds_i, bins_l],[1 1]*hdr_pwr,'Color','blue');
  end

  
  if (bds_i < bde_i)
    line([bds_i, bde_i],[1 1]*body_pwr,'Color','blue');
  else
    line([1, bde_i],[1 1]*body_pwr,'Color','blue');
    line([bds_i, bins_l],[1 1]*body_pwr,'Color','blue');
  end
  ncplot.txt(sprintf('meas dur %s', uio.dur(rp_measlen_dur_s)));
  ncplot.txt(sprintf('est hdr_len %s', uio.dur(rp_hdr_len_s)));
  %  ncplot.txt(sprintf('margin %d bins', rp_trise_bins));
  ncplot.txt(sprintf(' hdr pwr %.2f adc', hdr_pwr),'blue');
  ncplot.txt(sprintf('body pwr %.2f adc', body_pwr),'blue');
  %  plot(mi, bins(m_i),'.', 'Color','green');
  ylabel('pwr (adc)');
  xlabel('bin (idxs)');
  title('histogram of samples');
 
  
  
end


function r=modi(a, b)
 % mod for one-based indicies
 r=mod(a-1,b)+1;
end        


function mn=calc_mean(data, si, ei)
  data_l = length(data);
  ii = si;
  s=0;
  c=0;
  while(1)
    s = s + data(ii);
    c = c + 1;
    if (ii == ei)
      break;
    end
    ii = modi(ii+1, data_l);
  end
  mn = s / c;
end
    

