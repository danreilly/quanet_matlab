
function analyze_pwr(pwr_adc2, frame_pd_asamps, asamp_Hz)

  l = length(pwr_adc2);
  n = floor(l/frame_pd_asamps);
  
  ncplot.init();
  [co,ch,coq]=ncplot.colors();

  pmd=median(pwr_all);
  pmx=max(pwr_all);
  
  c2_mi = find(pwr_all>(pmd+pmx)/2,1);
  sl = l-c2_mi+1;
  plot(mod(0:sl-1 + c2_mi, frame_pd_asamps)*1e6/asamp_Hz, ...
       pwr_adc2(c2_mi:end), '.', 'Color', coq(1,:));
  
  uio.pause();
end
