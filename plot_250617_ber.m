function plot_250617_ber
  import nc.*
  mname = 'plot_250617_ber';

  pwrs_dBm=[-36.5 -41.5 -46.5 -51.5 -56.5]-.5;
  bers = [9.07e-4 8.4e-4 1.0e-2 1.5e-2 1.1e-1];

  
  
  ncplot.init();
  plot(pwrs_dBm, bers,'.-');
  set(gca(),'yscale','log');
  xlabel('sig pwr (dBm)');
  ylabel('BER');
  ncplot.title({mname;'no IM, Pi modulation, 100ns hdr, 1us frame'});
  uio.pause();  

  pwr_dBm=[-33.6 -38.6 -43.8 -53.7]-3.3-.5;
  bers  = [7.8e-2  8.8e-2  1e-1  7.8e-2 2.3e-1];
  bers2 = [5.4e-3 7.1e-3 1.7e-2 2e-2  1.1e-2];

  plot(pwrs_dBm, bers,'.-','Color','red');
  plot(pwrs_dBm, bers2,'.-','Color','magenta');
  set(gca(),'yscale','log');
  xlabel('sig pwr (dBm)');
  ylabel('BER');
  ncplot.title({mname;'Pi modulation, 100ns hdr, 1us frame'});
  
  

end
