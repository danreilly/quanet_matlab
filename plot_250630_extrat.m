function plot_250630_extrat
  import nc.*
  mname = 'plot_250630_extrat.m';
    
  bias_V = [ 3.2   3.1    3      2.89   3      2.8   2.7    3.0    2.9  2.95 ];
  pwr_dBm= [-30.3 -30.67 -30.86 -30.88 -30.87 -30.7 -30.3 -30.87 -30.8 -30.87]+6.5;
  ext_dB = [ 20.4  27.8   32     23.4   30.6   17.8  14.8  34.1   22.6  26.2];
  ncplot.subplot(2,1);
  ncplot.subplot();
  plot(bias_V, pwr_dBm,'.');
  xlabel('bias (V)');
  ylabel('mean pwr (dBm)');
  ncplot.title(mname);

  ncplot.subplot();
  plot(bias_V, ext_dB,'.');
  xlabel('bias (V)');
  ylabel('extinction (dB)');
  ncplot.title(mname);

  uio.pause();

  bias_V=[2.7:.1:3.7];
  ext_dB=[6.85 8.36 10.37 12.03 13.9 17.47 17.3 18.6 16.8 15.05 12.66];
  ncplot.init();
  ncplot.subplot(2,1);
  ncplot.subplot();
  plot(bias_V, ext_dB, '.');
  xlabel('bias (V)');
  ylabel('extinction (dB)');
  ncplot.title(mname);
  
  
end
