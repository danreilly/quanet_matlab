function im_preemp
  import nc.*
  mname = 'im_preemp';
  tvars = nc.vars_class('tvars.txt');


  osamp = tvars.ask('oversampling', 'osamp', 4);

  asamp_Hz = 1.2333333e9;
  if (0)
    frame_pd_us = tvars.ask('frame period (us)', 'frame_pd_us', 0);
    frame_pd_asamps = round(frame_pd_us*1e-6 * asamp_Hz/4)*4;
    fprintf('frame pd %d asamps\n', frame_pd_asamps);
  else
    frame_pd_asamps = tvars.ask('frame period (asamps)', 'frame_pd_asamps', 1200);
  end
  frame_pd_us = frame_pd_asamps /asamp_Hz * 1e6;
  fprintf('frame pd %d asamps = %.3f us \n', frame_pd_asamps, frame_pd_us);  
  
  % hdr_len_bits = tvars.ask('header len (bits)', 'hdr_len_bits', 0);
  hdr_len_ns = tvars.ask('header len (ns)', 'hdr_len_ns', 0);
  hdr_len_asamps = round(hdr_len_ns * 1e-9 * asamp_Hz);
  hdr_len_s = hdr_len_asamps / asamp_Hz;
  hdr_len_ns = hdr_len_s *1e9;
  fprintf('hdr len %s\n', uio.dur(hdr_len_s));

  tc_s = tvars.ask('rise timeconst (us)', 'preemph_tc_us', 1)*1e-6;

  %  tc_s = (1/asamp_Hz)/(1/16)
  
  tc_fall_s = tvars.ask('fall timeconst (us)', 'preemph_fall_tc_us', 1)*1e-6;
  
  body_asamps = frame_pd_asamps-hdr_len_asamps;
  
  
  frame=zeros(1,frame_pd_asamps);
  h = tvars.ask('up fraction', 'up_fraction', 0.5);
  m = (1-h)/hdr_len_asamps;
  frame(1:hdr_len_asamps) = h + m*((1:hdr_len_asamps)-1);
  
  % Goes negative this amt
  lo = hdr_len_asamps/body_asamps;

  lo
  while (1)
    slope_dur_s = tvars.ask('body slope dur (ns)', 'slope_dur_ns', 1)*1e-9;
    if (hdr_len_s+slope_dur_s <= frame_pd_us*1e-6)
      break;
    end
    fprintf('ERR: that duration exceeds the rest of the frame (%g us)', frame_pd_us-hdr_len_s*1e6);
  end  
  slope_dur_asamps = round(slope_dur_s * asamp_Hz);
  h = tvars.ask('down fraction', 'down_fraction', 0.5);
  drop = 1+lo;
  m = -(drop)*(1-h)/slope_dur_asamps;
  frame(hdr_len_asamps+(1:slope_dur_asamps)) = 1-h*drop + m*((1:slope_dur_asamps)-1);


  frame=frame(1:frame_pd_asamps);
  t_us = (0:(frame_pd_asamps-1))/asamp_Hz *1e6;
  
  tvars.save();


  fname = sprintf('preemph_f%d.bin', frame_pd_asamps);
  
  ncplot.init();
  ncplot.subplot(1,2);

  ncplot.subplot();
  plot(t_us, frame, '-','Color','yellow');
  xlabel('time (us)');
  if (1)
    v=0;
    sig=zeros(size(frame));
    if (tc_s < 1/ asamp_Hz)
      f=1;
    else
      f = (1/asamp_Hz)/tc_s;
    end
    fprintf('  rise f = %g\n', f);
    fl=0;
    for k=1:frame_pd_asamps
      if (~fl && (k>=hdr_len_asamps))
        if (tc_fall_s < 1/asamp_Hz)
          f=1;
        else
          f = (1/asamp_Hz)/tc_fall_s;
        end
        fprintf('  fall f = %g\n', f);    
        fl=1;
      end
      v = v + (frame(k)-v) * f;
      sig(k) = v;
    end
  elseif (0)
    sig=filt.gauss(frame, asamp_Hz, 1/tc_s, hdr_len_asamps*4);
  else
    ts = timeseries(frame, t);
    ival=[0 1/tc_s];
    ts = idealfilter(ts, ival, 'pass');
    %  sig = getdatasamples(ts,[1:frame_pd_asamps]);
    sig = squeeze(ts.Data);
  end
  fprintf('mean sig %g\n', mean(sig));
  plot(t_us, sig, '-','Color','red');
  xlabel('time (us)');
  ncplot.title({'im_preemp.m'; fname});
  
  ncplot.subplot();
  
  %  sig = sig - mean(sig);
  sig = round(sig/max(sig) * (2^15-1));
  sig = min(sig, 2^15-1);
  fprintf('sig ranges from %d = x%s to %d = -x%s\n', ...
          max(sig), dec2hex(max(sig)), ...
          min(sig), dec2hex(-min(sig)));

  
  plot(t_us, sig, '-');
  ncplot.title({'im_preemp.m'; fname});
  xlabel('time (us)');



  if (0)
    v=0;
    
    frame(1:hdr_len_asamps)=max(sig);
    frame(hdr_len_asamps+(1:body_asamps)) = sig(end);

    filt_const_w = tvars.ask('bit width of filter constant', 'filt_const_w', 8);
    tvars.save();
    sig2=zeros(size(frame));
    f = (1/asamp_Hz)/tc_s;
    fprintf('float pt f = %g\n', f);
    f = round(f*2^filt_const_w);
    fprintf('fixed prec f x%x = %d\n', f, f);
    g = 2^(filt_const_w) - f;
    fprintf('           g x%x = %d\n', g, g);
    fl=0;
    for k=1:frame_pd_asamps
      if (~fl && (k>=hdr_len_asamps))
        f = (1/asamp_Hz)/tc_fall_s;
        f = round(f*2^filt_const_w);
        g = 2^(filt_const_w) - f;
        fl=1;
      end
      v = round((v * g + frame(k) * f)/2^filt_const_w);
      sig2(k) = v;
      % fprintf('%g %g\n', frame(k), v);
    end
    plot(t_us, sig2, '-');
    ncplot.txt(sprintf('filt const bitwid %d\n', filt_const_w));
    ncplot.title('im_preemp.m');
  end  

  % we might want to implement this simple FIR in hdl,
  % which would eliminate the need for BRAM to store the header.

  % Rather than always using 2^15 we could use a lower value,
  % and use the same profile on all QNICs.
  % This would allow some adjustment margin,
  % which could be done by the use digital to adjust it on a per-QNIC basis.
  %
  % Or if profile is generated, could just configure starting hi
  % and lo values on a per-qnic basis.


  %  sig = [sig; sig];
  %  sig = sig(:);


  fid=fopen(fname, 'w', 'l', 'US-ASCII');
  if (fid<0)
    fprintf('ERR: cant open file\n');
  end
  cnt = fwrite(fid, sig(:), 'int16');
  fprintf('wrote %s (%d bytes)\n', fname, length(sig)*2);
  fclose(fid);
  
end    
