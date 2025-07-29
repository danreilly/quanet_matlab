function plot_250710_ber
  import nc.*
  mname='plot_250710_ber.m'
  sym_dur_s = 3.2e-9;
  bers    = [9.9e-3 1.3e-2 2.2e-2 1.5e-2 1.2e-2 9.7e-3 1.5e-2 1.3e-1 .4];
  pwrs_dBm =[-30.9 -32.8 -36.7 -39.7 -39.8 -41.8 -45.5 -50 -55];
  pwrs_W = 10.^(pwrs_dBm/10)/1000;
  ncplot.subplot(2,1);
  ncplot.subplot();
  plot(pwrs_dBm, bers, '.-');
  set(gca(),'YScale','log');
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
  plot(n, bers, '.-');
  set(gca(),'XScale','log','YScale','log');
  xlabel('photon number');
  ylabel('BER');
  ncplot.title(mname);
  
end
