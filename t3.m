function t3
  import nc.*
  n=50;
  ncplot.init();    

  
  b=.01*randn(n*8,1)+.095;
  for k=0:3
    b((1:n)+k*(n*2)) =  b((1:n)+k*(n*2))*1.1 +.005;
  end
  b=b(30:end);

  t = (0:(length(b)-1)) * 5/50;

  
  xlabel('time (us)');
  ylabel('amplitude (V)');
  
  plot(t, b,'.');
  

end
