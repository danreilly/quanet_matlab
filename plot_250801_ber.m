function plot_250801_ber
  import nc.*
  mname='plot_250801_ber.m'
  sym_dur_s = 3.2e-9;
  pwrs_dBm  = [-52.88 -57.1   -57.9 -60.8 -65.7];
  sym_bers  = [.163   .138    .138  .138    .5 ];
  data_bers = [0       0      0     0       .5 ];
  pwrs_W = 10.^(pwrs_dBm/10)/1000;
  ncplot.subplot(2,1);
  ncplot.subplot();
  plot(pwrs_dBm, sym_bers, '.-');
  plot(pwrs_dBm, data_bers, '.-','Color','green');
  %  set(gca(),'YScale','log');
  ncplot.txt(sprintf('symbol dur %s', uio.dur(sym_dur_s)));
  xlabel('pwr (dBm)');
  ylabel('BER');
  ncplot.title(mname);

  h_JpHz = 6.62607e-34;
  wl_m = 1544e-9;
  c_mps= 299792458;

  n = pwrs_W * sym_dur_s / (h_JpHz * c_mps / wl_m);
  ncplot.subplot();
  ncplot.txt(sprintf('symbol dur %s', uio.dur(sym_dur_s)));
  ncplot.txt(sprintf('wavelen %.2f nm', wl_m*1e9));
  plot(n, sym_bers, '.-');
  plot(n, data_bers, '.-','Color','green');
  set(gca(),'XScale','log');
  %  set(gca(),'XScale','log','YScale','log');
  xlabel('photon number');
  ylabel('BER');
  ncplot.title(mname);
  
end
