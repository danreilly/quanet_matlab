
function sig = filt_comb(tsamp_s, sig, fctr_Hz, foff_Hz, frange_Hz, pow, opt)
% raised cosine comb filer
  import nc.*

  if (nargin<7)
    opt.plot=1;
  end
  sig_l = length(sig);
  sig = sig(:); % ensure vert vector
  nfft2 = floor(sig_l/2)+1;
  sig_mean = mean(sig);
  sig = sig - sig_mean;
                     
  f_n = fft(sig);

  r_Ohms = 1;


  fft_pwr = pwr(f_n);

  

  freqs_Hz=(0:nfft2-1).'/(sig_l*tsamp_s);

  i_s = min(max(round(frange_Hz(1)*(sig_l*tsamp_s)),1),nfft2);
  i_e = min(max(round(frange_Hz(2)*(sig_l*tsamp_s)),1),nfft2);


  i_0 = fctr_Hz * (sig_l*tsamp_s); % index of center
  rc =  (1+cos(((0:nfft2-1) - i_0)/(sig_l*tsamp_s)* pi/foff_Hz))/2; % raised cosine
  rc(nfft2+1:sig_l)=rc(nfft2-1:-1:2);
  rc = rc.^pow;
  
  mx=max(fft_pwr(i_s:i_e));

  if (opt.plot)  
    ncplot.init();
    cq=ncplot.colors_qtr();
    plot(freqs_Hz(i_s:i_e), fft_pwr(i_s:i_e)/mx, 'Color',cq(1,:));
    plot(freqs_Hz(i_s:i_e), rc(i_s:i_e), 'Color','red');
    title('raised cosine filter');  
    uio.pause;
  end

  f_n = f_n .* rc(:);

  if (0)
    fft_pwr = pwr(f_n);
    ncplot.init();
    plot(freqs_Hz(i_s:i_e), fft_pwr(i_s:i_e)/mx, 'Color',cq(1,:));
    plot(freqs_Hz(i_s:i_e), rc(i_s:i_e), 'Color','red');
    title('raised cosine filter and filtered signal');
    ncplot.txt(sprintf('power %.1f', pow));
    uio.pause;
  end
  
  sig = ifft(f_n);
  
  % Nested
  function fft_pwr = pwr(f_n)
    fft_pwr = conj(f_n(1:nfft2)).*f_n(1:nfft2)/sig_l^2/r_Ohms;
    k=sig_l-nfft2-1;
    fft_pwr(2+(0:k)) = fft_pwr(2+(0:k)) ...
        + conj(f_n(sig_l-(0:k))).*f_n(sig_l-(0:k))/sig_l^2/r_Ohms;
  end

  

  
end  
