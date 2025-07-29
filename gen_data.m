function gen_data
  import nc.*
  mname='p.m';

  opt_show=1;
  h_JpHz = 6.62607e-34;
  wl_m = 1544.53e-9;
  c_mps= 299792458;

  opt_fnum=-1;
  if (nargin>0)
    [v n]=sscanf(arg,'%d');
    if (n==1)
      opt_fnum = v;
    end
  end
  
  tvars = nc.vars_class('tvars.txt');
 
  fname='';
  dflt_fname_var = 'fname';

  cipher_lfsr = lfsr_class(hex2dec('280001'), hex2dec('abcde'));
  % cipher_lfsr = lfsr_class(hex2dec('280001'),    hex2dec('aabbc'));

  %  symlen_asamps = tvars.ask('asamps/sym', 'qsdc_data_symlen_asamps', 4);

  if (0) 
    msg_len_s = tvars.ask('message duration (us)', 'msg_len_us')*1e-6;
    asamp_Hz =  1.233333333e9;
    msg_len_bytes = round(msg_len_s * asamp_Hz/symlen_asamps/8);
  else
    msg_len_bytes = tvars.ask('message len (bytes)', 'msg_len_bytes');
  end;
  msg_len_bytes = round(msg_len_bytes/16)*16;

  tvars.save();
  
  cipher = cipher_lfsr.gen(msg_len_bytes*8);

  cipher = reshape(cipher,8,[]);
  data = 2.^(0:7)*cipher;
  for k=1:8
    fprintf('   %d  x%s %d\n', k-1, dec2hex(data(k),2), data(k));
  end
  
  fname = tvars.ask('message file (.bin)', 'msg_fname','');

  tvars.save();
  
  fid=fopen(fname, 'w', 'l', 'US-ASCII');
  if (fid<0)
    fprintf('ERR: cant open file\n');
  end
  cnt = fwrite(fid, data, 'uint8');
  fprintf('wrote %s (%d bytes)\n', fname, length(data));
  fclose(fid);

end
