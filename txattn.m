function txattn(arg)
  import nc.*
  fprintf('this sets the quantum transmit VOA (VOAqt) in Bob\n')
  qna1_1=qna1_class('com11');
  % tvars = nc.vars_class('tvars.txt');
  if (nargin<1)
    tx_atten_dB = uio.ask('tx atten (dB)', qna1_1.settings.voa_dB(1));
    % tvars.save();
  else
    tx_atten_dB = sscanf(arg, '%g');
  end
  qna1_1.set_voa_attn_dB(1, tx_atten_dB);
  fprintf('%.2f\n', qna1_1.settings.voa_dB(1));
end
