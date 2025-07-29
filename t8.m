function t8
  import nc.*
  fsamp_Hz = 1e9;
  hdr_pd_samps  = floor(1e-6 * fsamp_Hz);
  hdr_len_samps = floor(100e-9 * fsamp_Hz);
  body_len_samps = hdr_pd_samps - hdr_len_samps;
  t_us = (0:hdr_pd_samps-1)/fsamp_Hz*1e6;

  ncplot.init();
  ncplot.subplot(4,1);
  
  hdr_env = zeros(1,hdr_pd_samps);
  hdr_env(1:hdr_len_samps)=.9
  hdr_env(hdr_len_samps+2:end)=-.1;
  ncplot.subplot();
  plot(t_us, hdr_env,'.','MarkerSize',2);
  xlabel('time (us)');
  ylabel('value (Pi rad)');
  ylim([-.2 1.1]);
  ncplot.title('B_IM1 = Bobs Intensity Modulation 1');
  
  
  rf_pm = zeros(1,hdr_pd_samps);
  rf_pm(1:hdr_len_samps)=(rand(1,hdr_len_samps)>0.5)-.5;
  m=8;
  rf_pm(hdr_len_samps+1:end)=((floor(rand(1,body_len_samps)*m)-(m-1)/2)/m *2);  
  ncplot.subplot();
  plot(t_us, rf_pm,'.','MarkerSize',2);
  xlabel('time (us)');
  ylabel('value (Pi rad)');
  ncplot.title('B_PM = Bobs Phase Modulation');

  rf_im = zeros(1,hdr_pd_samps);
  hi = .9;
  lo = hi * hdr_len_samps / (hdr_pd_samps-hdr_len_samps);
  
  rf_im(1:hdr_len_samps)= hi + (rand(1,hdr_len_samps)-.5)*0;
  rf_im(hdr_len_samps+1:end)= -lo + (rand(1,body_len_samps)-.5)*.2;
  ncplot.subplot();
  plot(t_us, rf_im,'.','MarkerSize',2);
  xlabel('time (us)');
  ylabel('value (Pi rad)');
  ncplot.title('B_IM2 = Bobs Intensity Modulation 2');

  a_bit_dur_s = 50e-9;
  bit_dur_samps = round(a_bit_dur_s * fsamp_Hz);

  body_len_samps
  start_margin_samps = bit_dur_samps;
  end_margin_samps   = floor(start_margin_samps/2);
  
  body_bits = floor((body_len_samps - start_margin_samps - end_margin_samps) ...
		    /bit_dur_samps);
  body_bits
  body=(rand(1,body_bits)>.5)-.5;
  body=reshape(repmat(body, bit_dur_samps, 1),1,[]);
  fprintf('body len %d\n',   length(body)  );

hdr_pd_samps  
  a_pm =  zeros(1,hdr_pd_samps);
  a_pm(hdr_len_samps+start_margin_samps+(1:length(body)))=body;

%  a_pm(hdr_len_samps+(1:body_len_samps))=.11
  ncplot.subplot();
  plot(t_us, a_pm,'.','MarkerSize',2);

  r1 = hdr_len_samps + (1:start_margin_samps);
  plot(t_us(r1), a_pm(r1),'-','Color','red');
  k = hdr_len_samps + start_margin_samps + length(body)+1;
  plot(t_us(k:end), a_pm(k:end),'-','Color','red');
  
  xlabel('time (us)');
  ylabel('value (Pi rad)');
  ylim([-1 1]*.6);
  ncplot.title('A_PM = Alice Phase Modulation');

  
if (0)
  uio.pause();
  ncplot.init();
  opt.noplot=0;
  opt.nowindow=0;
  ncplot.fft(hdr_env, 1/fsamp_Hz, opt);
end  
end
