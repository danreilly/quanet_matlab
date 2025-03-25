function t4
  import nc.*

  fsamp = 1.233333333e9;


  if (1)
    osamp = 4;
    lfsr = lfsr_class(hex2dec('a01'), hex2dec('50f'));
    hdr = lfsr.gen(1024)*2-1;
    sig=reshape(repmat(hdr.',osamp,1),[],1);

  else
    l = 1024
    sig = sin(2*pi*100e6*((1:l)-1)/fsamp);    
    sig = sig + randn(1, l)/10;
  end
  
  ncplot.init();
  [co,ch,cq]=ncplot.colors();
  

  opt.no_window=0;
  %  ncplot.fft(sig, 1/fsamp, opt);
  plot(sig,'Color','blue');

  fcut = fsamp*3/16
  sig = filt.gauss(sig, fsamp, fcut, 8);
  opt.color='red';
  plot(sig, 'Color', 'red');
  ncplot.txt(sprintf('fcut %sHz', uio.sci(fcut)));
  %  ncplot.fft(sig, 1/fsamp, opt);
  ylim([-2 2]);
  
    
end
