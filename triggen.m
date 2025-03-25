function triggen
  import nc.*
  tvars = nc.vars_class('tvars.txt');
  quo_w  = tvars.ask('width of quotient', 'QUO_W', 5);
  trig_w = tvars.ask('width of trig mem out', 'TRIG_W', 5);
  tvars.save();

  fname = 'trig_rom.mem';
  
  [f errmsg] = fopen(fname,'w');
  if (f<0)
    fprintf('ERR: cant open file\n');
    return;
  end
  
  n = 2^(quo_w+1);
  tmax = 2^trig_w-1;
  hw = ceil(trig_w/4);
  hwf = ceil(trig_w/2);
  for k=0:(2^quo_w-1)
    th = atan2(1-k/n,k/n);
    cc = round(cos(th) * tmax);
    ss = round(sin(th) * tmax);
    if ((k<8)||(k>=2^quo_w-8))
      fprintf('%.6f = %.1f deg  -> %d %d  %s %s\n', k/n, th*180/pi, cc, ss, dec2hex(cc, hw), dec2hex(ss, hw));
      if (k==7)
	fprintf('...\n');
      end
    end
    fprintf(f, '%s\n', dec2hex(bitor(ss*2^trig_w, cc), hwf));
  end
  fclose(f);
  fprintf('wrote %s\n', fname);
end
