function plot_250721_ber
  import nc.*
  mname = 'plot_250721_ber';

  pwrs_mon=[-48.4 -52.4 -56.3 -60.7 -65.6];
  pwrs_bod=[-5.8  -5.8  -6.1  -5.9  -5.9]
  
  
  pwrs_dBm=pwrs_mon+pwrs_bod;
  bers = [1/26558  2.6e-4 4.4e-3 4.8e-2 1.7e-1];

  pwrs_W = 10.^(pwrs_dBm/10)/1000;
  
  ncplot.init();
  ncplot.subplot(2,1);


  ncplot.subplot();
  plot(pwrs_dBm, bers, '.-');
  set(gca(),'yscale','log');
  xlabel('sig pwr (dBm)');
  ylabel('BER');
  ncplot.title({mname;'no IM, Pi modulation, 100ns hdr, 1us frame'});

  sym_dur_s = 3.2e-9;

  
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
