
% junk for testing RP metrics

function t11
  m_dBm = -30.26

  % .000965, .000960 .000927  .0009996 .000943
  dark_adc = 0.000943;
  mean_adc = 0.00408;
  body_adc = 0.00198;
  hdr_adc  = 0.01616;

  fprintf(' hdr %.2g - %.2g\n', hdr_adc-dark_adc);
  fprintf('body %.2g - %.2g\n', body_adc-dark_adc);
  ext_dB =10*log10( (hdr_adc-dark_adc)/(body_adc-dark_adc));
  fprintf('ext rat %.2f dB\n', ext_dB);
  
  sig_minus_mon_dB = -7.24;
  sig_dBm = m_dBm + sig_minus_mon_dB;

  body_minus_sig_dB = 10*log10( (body_adc-dark_adc)/(mean_adc-dark_adc));
  body_pwr_dBm = sig_dBm - 8.84;

  body_pwr_W = 10^(body_pwr_dBm/10)/1000;
  
  asamp_Hz = 1.2333333e9;
  h_JpHz = 6.62607e-34;
  wl_m = 1550e-9;
  c_mps= 299792458;
  chip_s = 4/asamp_Hz;
  
  n =  body_pwr_W * chip_s / (h_JpHz * c_mps / wl_m);

  n

end
