function t3
  import nc.*
  n=50;

  o = 0;
  a = 50;
  g = 10;
  m = 0;


  x = linspace(-100,100,256).';
  x_l = length(x);
  y = a*g./(pi*((x-m).^2+g^2)) + o;
  size(y)
  %  y = y + randn(x_l,1)*4;

if (0)
          slopt.dbg = 1;
          %       	  slopt.dbg = (fi==172);
	  slopt.m = 0;
	  slopt.init_y_thresh = .10;
	  slopt.weighting='y';
	  [a m g o rmse] = fit.lorentzian(x, y, slopt);
end
      tsamp = mean(diff(x))
      
      fsamp = 1/(mean(diff(x)));
      ff=abs(fft(y));

      n2 = floor(x_l/2);

      
      ncplot.init();
      size((-n2:(n2-1)))
      plot((-n2:(n2-1)).', ff, '.-');

      p = ff(n2+2)

      p/pi/tsamp
      
    
          

      %  plot(x,y,'.');

  
  
  return;  


  t = (0:(length(b)-1)) * 5/50;

  
  xlabel('time (us)');
  ylabel('amplitude (V)');
  
  plot(t, b,'.');
  

end
