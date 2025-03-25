function t1
  import nc.*
  lo_dBm=[13.5 10.5 8  -100];
  lo_mW=10.^(lo_dBm/10);
  n =[108 86 73.6 50];
  pf = nc.fit.polyfit(lo_mW, n,1);
  ncplot.init();
  plot(lo_mW, n,'.');
  fx=[min(lo_mW) max(lo_mW)];
  fy=polyval(pf,fx);
  line(fx,fy,'Color','green');
  xlabel('LO (mW)');
  ylabel('noise (ADC RMS)');
  title({'Effect of LO on noise';'det: zx60-p103L';'amps: zx60-p103L GVA-84'});  

end
