function t6
  import nc.*
  x = -100:100;
  a = 100;
  m = 0;
  g = 10;
  o = 0;
  y = a*g./(pi*((x-m).^2+g^2)) + o;
  ncplot.init();
  opt.dbg=1;
  ncplot.fft(y, 1, opt);

  % if m=0,
  % ln of FFT of lorentzian is: -g*pi*abs(k)
  % a straight line, slope reveals g.
  
end
