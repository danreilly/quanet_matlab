function sig = filt_pass(tsamp_s, sig, passlist, frange_Hz)
% passlist: nx2 matrix.  First col is ctrs_Hz.  second col is fwid_Hz.  
% ideal bandpass filter
  import nc.*
  sig_l = length(sig);
  sig = sig(:); % ensure vert vector
  nfft2 = floor(sig_l/2)+1;
  sig_mean = mean(sig);
  sig = sig - sig_mean;

  if (nargin<4)
    frange_Hz=[];
  end  
  f_n = fft(sig);

  r_Ohms = 1;


  fft_pwr = pwr(f_n);
  
  ncplot.init();
  cq=ncplot.colors_qtr();

  freqs_Hz=(0:nfft2-1).'/(sig_l*tsamp_s);





  flt=zeros(sig_l,1);

  for fi=1:size(passlist,1)
    fctr_Hz = passlist(fi,1);
    fwid_Hz = passlist(fi,2);
    i_bs = round((fctr_Hz - fwid_Hz/2) * (sig_l*tsamp_s)+1);
    i_be = round((fctr_Hz + fwid_Hz/2) * (sig_l*tsamp_s)+1);
    flt(i_bs:i_be)=1;
    flt(nfft2+1:sig_l)=flt(nfft2-1:-1:2);
  end

  if (~isempty(frange_Hz))
    i_s = min(max(round(frange_Hz(1)*(sig_l*tsamp_s)),1),nfft2);
    i_e = min(max(round(frange_Hz(2)*(sig_l*tsamp_s)),1),nfft2);
    mx=max(fft_pwr(i_s:i_e));
    plot(freqs_Hz(i_s:i_e), fft_pwr(i_s:i_e)/mx, 'Color',cq(1,:));
    plot(freqs_Hz(i_s:i_e), flt(i_s:i_e), 'Color','red');
    title('filter');  
    uio.pause;
  end
  f_n = f_n .* flt(:);

  if (0)
    fft_pwr = pwr(f_n);
    ncplot.init();
    plot(freqs_Hz(i_s:i_e), fft_pwr(i_s:i_e)/mx, 'Color',cq(1,:));
    plot(freqs_Hz(i_s:i_e), rc(i_s:i_e), 'Color','red');
    title('raised cosine filter and filtered signal');  
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
