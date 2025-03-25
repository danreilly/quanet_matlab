function [b a] = iir_notch(fsamp_Hz, fc, bw_Hz, ord)
% bw_Hz: -3dB bandwidth
% ord: order. must be even



  ord = ord/2;
  m = 2^(1/ord);
  
  c = cos(bw_Hz * 2*pi/fsamp_Hz / 2);
  r = roots([1 -2*c 1-m*(2-2*c)]);
  k = min(r);
  z = exp(j*fc/fsamp_Hz*2*pi);

'dbg iir'
fc/(fsamp_Hz/2)
  
  f = (1 - 2*k*real(z) +k*k)/(2-2*real(z));

  b = f*[1 -2*real(z) 1];
  a = [1 -2*k*real(z) k*k];

  for itr=2:ord
    bm = b.'*b;
    b = [bm(1,:) 0 0 ] + [0 bm(2,:) 0] + [0 0 bm(3,:)];
    am = a.'*a;
    a = [am(1,:) 0 0 ] + [0 am(2,:) 0] + [0 0 am(3,:)];
  end

  if (~isreal(a) || ~isreal(b))
    fprintf('BUG: iir_notch returns imag\n');
  end

end
