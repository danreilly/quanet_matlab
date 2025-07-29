
function res = calc_pwr(pwr_adc2, frame_pd_asamps, hdr_len_asamps, asamp_Hz, fname_s, cpopt)
  import nc.*
  
  l = length(pwr_adc2);
  n = floor(l/frame_pd_asamps);
  
  ncplot.init();
  [co,coh,coq]=ncplot.colors();


  if (cpopt.start_idx==0)
    pmd=median(pwr_adc2);
    pmx=max(pwr_adc2);
    si = find(pwr_adc2 > (pmd+pmx)/2,1);
  else
    si = cpopt.start_idx;
  end
  if (cpopt.len_asamps)
    sl = cpopt.len_asamps;
  else
    sl = l-si+1;
  end
  plot(mod(0:sl-1, frame_pd_asamps).'*1e6/asamp_Hz, ...
       pwr_adc2(si-1+(1:sl)), '.', 'Color', coq(1,:));
  m=zeros(frame_pd_asamps,1);
  for k=1:frame_pd_asamps
    m(k) = mean(pwr_adc2(si+k-1:frame_pd_asamps:si-1+sl));
  end
  plot((0:frame_pd_asamps-1).'*1e6/asamp_Hz, ...
       m, '.', 'Color', coh(1,:));
  
  d=20;
  pwr_hi = mean(m(d:hdr_len_asamps-d));
  line([d hdr_len_asamps-d]*1e6/asamp_Hz, ...
       [1 1]*pwr_hi, 'Color','blue');
  is = hdr_len_asamps+d*20;
  ie = frame_pd_asamps-d;
  pwr_mean = mean(m);
  pwr_lo = mean(m(is:ie));
  line([is ie]*1e6/asamp_Hz, ...
       [1 1]*pwr_lo, 'Color','blue');
  ncplot.txt(sprintf(' hi %.1f adc^2    lo %.1f adc^2', pwr_hi, pwr_lo));

  ext_rat = (pwr_hi/pwr_lo);
  ext_dB =  10*log10(ext_rat);
  ncplot.txt(sprintf('ext ration %.1f dB', ext_dB));

  m2lo_dB =  10*log10(pwr_mean/pwr_lo);
  m2hi_dB =  10*log10(pwr_mean/pwr_hi);
  
  ncplot.txt(sprintf('mean-low %.1f dB', m2lo_dB));


  res.ext_rat = ext_rat;
  res.ext_db = ext_dB;
  res.m2lo_db = m2lo_dB;

  mean_pwr_mW = 10^(cpopt.mean_pwr_dBm/10);
  ncplot.txt(sprintf('mean pwr %.1f dBm = %sW', cpopt.mean_pwr_dBm, ...
                     uio.sci(mean_pwr_mW/1000,2)));
  body_pwr_dBm = cpopt.mean_pwr_dBm - m2lo_dB;
  res.body_pwr_dBm = body_pwr_dBm;
  body_pwr_W = 10^(res.body_pwr_dBm/10)/1000;


  res.hdr_pwr_dBm = cpopt.mean_pwr_dBm - m2hi_dB;
  pwr_mW = 10^(res.hdr_pwr_dBm/10);    
  ncplot.txt(sprintf('hdr pwr %.1f dBm = %sW', res.hdr_pwr_dBm, ...
                     uio.sci(pwr_mW/1000,2)));
  
  h_JpHz = 6.62607e-34;
  wl_m = 1550e-9;
  c_mps= 299792458;
  ncplot.txt(sprintf('body pwr %.1f dBm = %sW', body_pwr_dBm, ...
                     uio.sci(body_pwr_W,2)));

  res.n =  body_pwr_W * cpopt.chip_s / (h_JpHz * c_mps / wl_m);
  ncplot.txt(sprintf('photons per %s = %.1e', uio.dur(cpopt.chip_s), res.n));

                     
  
  xlabel('time (ms)');
  ylabel('IQ power (adc ^ 2)');
  ncplot.title({'extinction analysis'; fname_s});

end
