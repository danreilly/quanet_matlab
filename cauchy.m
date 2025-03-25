function cauchy
 g = 10
 f = linspace(-100,100);
 f0=0;
 myplot.init;
 y=g^2./(pi*g*((f-f0).^2+g^2));
 plot(f, y, '.');
end
