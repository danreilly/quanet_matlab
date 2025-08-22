function plot_250819_ber
  import nc.*
  mname = 'plot_2508219_ber';
  h_JpHz = 6.62607e-34;
  wl_m = 1544e-9;
  c_mps= 299792458;


  fname = 'log/d250819/r_25.txt';
  [mvars m aug] = load_measfile(fname);
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
  
  pwrs_mon=[-41  -46.6 -53.4 -61.8 -65];
  pwrs_bod=[-8.5 -8.4  -8.2  -8.2 -12.6];
  
  pwrs_dBm=pwrs_mon+pwrs_bod
  sym_bers = [0   0  .161  .064  .334];
  bit_bers = [0  0    0     0    .06];

  idxs=find(sym_bers==0);
  sym_bers(idxs)=1/20480;

  
  idxs=find(bit_bers==0);
  bit_bers(idxs)=1/1024;
  
  pwrs_W = 10.^(pwrs_dBm/10)/1000;


  
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
  

  
  n = pwrs_W * bit_dur_s / (h_JpHz * c_mps / wl_m);
  ncplot.subplot();
  ncplot.txt(sprintf('symbol dur %s', uio.dur(symbol_dur_s)));
  ncplot.txt(sprintf('bit dur %s', uio.dur(bit_dur_s)));
  ncplot.txt(sprintf('wavelen %.2f nm', wl_m*1e9));
  plot(n, sym_bers, '.-','Color',co(1,:));
  plot(n, bit_bers, '.-','Color',co(2,:));
  set(gca(),'XScale','log','YScale','log');
  xlabel('photon per bit');
  ylabel('BER');
  ncplot.title(mname);

  
end
