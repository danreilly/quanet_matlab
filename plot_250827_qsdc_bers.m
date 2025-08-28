function plot_250827_qsdc_bers
  import nc.*
  mname = 'plot_2508227_qsdc_bers';
  h_JpHz = 6.62607e-34;
  wl_m = 1544e-9;
  c_mps= 299792458;


  fname = 'log/d250826/r_17.txt';
  mvars = vars_class(fname);
  asamp_Hz = mvars.get('asamp_Hz', 0);
  pilot_len_bits = mvars.get('hdr_len_bits', 0);
  osamp = mvars.get('osamp', 0);
  pilot_len_s = pilot_len_bits*osamp/asamp_Hz;
  frame_pd_asamps = mvars.get('frame_pd_asamps',0);
  frame_pd_s = frame_pd_asamps/asamp_Hz;
  qsdc_symbol_len_asamps = mvars.get('qsdc_symbol_len_asamps',4);
  symbol_dur_s = qsdc_symbol_len_asamps/asamp_Hz;
  qsdc_bit_dur_syms = mvars.get('qsdc_bit_dur_syms',10);
  bit_dur_s = qsdc_bit_dur_syms * symbol_dur_s;
  encrypt_en = mvars.get('encrypt_en');

  
  pwrs_dBm=[-56 -60 -66.1];
  sym_bers = [.03   .03  .09];
  bit_bers = [.007 .004 .007];
  pwrs_W = 10.^(pwrs_dBm/10)/1000;
  n = pwrs_W * bit_dur_s / (h_JpHz * c_mps / wl_m);  
  
  ncplot.init();
  [co,ch,cq]=ncplot.colors();
  ncplot.subplot(2,1);

  ncplot.subplot();
  plot(pwrs_dBm, sym_bers, '.-','Color',co(1,:));
  plot(pwrs_dBm, bit_bers, '.-','Color',co(2,:));
  set(gca(),'yscale','log');
  xlabel('sig pwr (dBm)');
  ylabel('BER');
  ncplot.title({mname;sprintf('Alice TXes 10k fiber, %s frame, %s pilot', ...
                              uio.dur(frame_pd_s), uio.dur(pilot_len_s))});

  ncplot.subplot();
  ncplot.txt(sprintf('symbol dur %s', uio.dur(symbol_dur_s)));
  ncplot.txt(sprintf('bit dur %s', uio.dur(bit_dur_s)));
  ncplot.txt(sprintf('wavelen %.2f nm', wl_m*1e9));
  ncplot.txt(sprintf('%sencrypted', util.ifelse(encrypt_en,'','NOT ')));
  plot(n, sym_bers, '.-','Color',co(1,:));
  plot(n, bit_bers, '.-','Color',co(2,:));
  set(gca(),'XScale','log','YScale','log');
  legend({'symbol BER';'bit BER'});
  xlabel('photon per bit');
  ylabel('BER');
  ncplot.title(mname);

  uio.pause();
  
  fname = 'log/d250827/r_14.txt';
  mvars = vars_class(fname);
  asamp_Hz = mvars.get('asamp_Hz', 0);
  pilot_len_bits = mvars.get('hdr_len_bits', 0);
  osamp = mvars.get('osamp', 0);
  pilot_len_s = pilot_len_bits*osamp/asamp_Hz;
  frame_pd_asamps = mvars.get('frame_pd_asamps',0);
  frame_pd_s = frame_pd_asamps/asamp_Hz;
  qsdc_symbol_len_asamps = mvars.get('qsdc_symbol_len_asamps',4);
  symbol_dur_s = qsdc_symbol_len_asamps/asamp_Hz;
  qsdc_bit_dur_syms = mvars.get('qsdc_bit_dur_syms',10);
  bit_dur_s = qsdc_bit_dur_syms * symbol_dur_s;
  encrypt_en = mvars.get('encrypt_en');




  
  pwrs_dBm =[-56.4 -57.7  -60.3 -65.5 -66.6];
  sym_bers =[.05   .09    .11   .31   .37];
  bit_bers =[.002  .001  .003  .01    .03];
  pwrs_W = 10.^(pwrs_dBm/10)/1000;
  n = pwrs_W * bit_dur_s / (h_JpHz * c_mps / wl_m);

  ncplot.subplot();
  plot(pwrs_dBm, sym_bers, '.-','Color',co(1,:));
  plot(pwrs_dBm, bit_bers, '.-','Color',co(2,:));
  set(gca(),'yscale','log');
  xlabel('sig pwr (dBm)');
  ylabel('BER');
  ncplot.title({mname;sprintf('Alice TXes 10k fiber, %s frame, %s pilot', ...
                              uio.dur(frame_pd_s), uio.dur(pilot_len_s))});

  ncplot.subplot();
  ncplot.txt(sprintf('symbol dur %s', uio.dur(symbol_dur_s)));
  ncplot.txt(sprintf('bit dur %s', uio.dur(bit_dur_s)));
  ncplot.txt(sprintf('wavelen %.2f nm', wl_m*1e9));
  ncplot.txt(sprintf('%sencrypted', util.ifelse(encrypt_en,'','NOT ')));
  plot(n, sym_bers, '.-','Color',co(1,:));
  plot(n, bit_bers, '.-','Color',co(2,:));
  legend({'symbol BER';'bit BER'});
  set(gca(),'XScale','log','YScale','log');
  xlabel('photon per bit');
  ylabel('BER');
  ncplot.title(mname);

  
end
  
