% double check cipher
function t12
  import nc.*
  cipher_lfsr = lfsr_class(hex2dec('280001'), hex2dec('abcde'));
  for k=1:3
    cipher = cipher_lfsr.gen(118);
    fprintf('%d: %s\n',k, sprintf(' %d', cipher.'));
  end
end
