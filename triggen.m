function triggen
  import nc.*
  tvars = nc.vars_class('tvars.txt');
  fprintf('\ntriggen\n');
  uio.print_wrap('This generates a rom file for a trig lookup table used by phase_est.vhd.  You feed it QUO=min(|I|,|Q|)/MAG, which can only range from 0 to 0.5.  This is all fixed precision.');
  quo_w  = tvars.ask('rom address width', 'QUO_W', 5);
  trig_w = tvars.ask('width of trig (sin or cos) values', 'TRIG_W', 5);
  tvars.save();

  fname = 'trig_rom.mem';
  [f errmsg] = fopen(fname,'w');
  if (f<0)
    fprintf('ERR: cant open file\n');
    return;
  end

  fname2 = 'trig_rom.vhd';
  [f2 errmsg] = fopen(fname2,'w');
  if (f2<0)
    fprintf('ERR: cant open file\n');
    return;
  end
  fprintf(f2, '  type rom_t is array(0 to %d) of std_logic_vector(%d downto 0);\n', ...
          2^quo_w-1, 2*trig_w-1);
  fprintf(f2, '  signal rom: rom_t := (\n    ');
  
  n = 2^(quo_w+1);
  tmax = 2^trig_w-1;
  hw = ceil(trig_w/4);
  hwf = ceil(trig_w/2);
  for k=0:(2^quo_w-1)
    th = atan2(1-k/n,k/n);
    cc = round(cos(th) * tmax);
    ss = round(sin(th) * tmax);
    if ((k<8)||(k>=2^quo_w-8))
      fprintf('%.6f = %.1f deg  -> %d %d  %s %s\n', k/n, th*180/pi, ...
              cc, ss, dec2hex(cc, hw), dec2hex(ss, hw));
      if (k==7)
	fprintf('...\n');
      end
    end
    fprintf(f, '%s\n', dec2hex(bitor(ss*2^trig_w, cc), hwf));


    if (mod(trig_w*2,4)==0)
      fprintf(f2, 'X"%s"', dec2hex(bitor(ss*2^trig_w, cc), hwf));
    else
      fprintf(f2, 'B"%s"', dec2bin(bitor(ss*2^trig_w, cc), trig_w*2));
    end 
    if (k==(2^quo_w-1))
      fprintf(f2, ');\n');
      break;
    elseif (mod(k,4)==3)
      fprintf(f2,',\n    ');
    else
      fprintf(f2,', ');
    end
    
  end
  fclose(f);
  fprintf('wrote %s\n', fname);


  fprintf(f2,'  attribute rom_style : string;\n');
  fprintf(f2,'  attribute rom_style of ROM : signal is "block";\n');
  fclose(f2);
  fprintf('wrote %s\n', fname2);
end
