function [ii qq] = decipher(ii, qq, mvars, tvars)
  ffi=  tvars.get('first_frame_idx');
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  osamp = mvars.get('osamp', 4);
  asamp_Hz = mvars.get('asamp_Hz', 0);

  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  hdr_len_asamps = hdr_len_bits * osamp;

  cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
  cipher_m = mvars.get('cipher_m',0); % cipher uses m-psk

  cipher_len_asamps = frame_pd_asamps - hdr_len_asamps;
  cipher_len_bits   = cipher_len_asamps * round(log2(cipher_m)) / ...
      cipher_symlen_asamps;
  
  cipher_symlen_s = cipher_symlen_asamps / asamp_Hz;
  
  cipher_lfsr = lfsr_class(hex2dec('280001'), hex2dec('abcde'));
  % cipher_lfsr = lfsr_class(hex2dec('280001'),    hex2dec('aabbc'));
  cipher = zeros(cipher_len_bits, 1);

  
  f_l=floor((length(ii)+1-ffi)/frame_pd_asamps); % for each frame


  fprintf('cipher len %d asamps per frame\n', cipher_len_asamps);
  fprintf('           %d bits per frame\n', cipher_len_bits);
  
  for f_i=1:f_l % for each frame
    frame_off=(f_i-1)*frame_pd_asamps + ffi-1; % 0 based

    is = frame_off + hdr_len_asamps+1; % idx of start of cipher

    cipher = cipher_lfsr.gen(cipher_len_bits);
    if (cipher_m==8)
      cipher = reshape(cipher.',4,[]);
      cipher = 8*cipher(1,:)+4*cipher(2,:)+1*cipher(3,:)+cipher(4,:);
    elseif (cipher_m==4)
      cipher = reshape(cipher.',2,[]);
      cipher = 2*cipher(1,:)+cipher(2,:);
    else
      cipher = reshape(cipher.',1,[]);
    end

    cipher = repmat(cipher,cipher_symlen_asamps,1);
    cipher = cipher(:);
    ie = is+cipher_len_asamps-1;
    % for every 1 in cipher, rot by -90.  for each 0 rot by 90.
    tmp = qq(is:ie) .* -(cipher*2-1);
    qq(is:ie) = ii(is:ie) .* -(1-cipher*2);
    ii(is:ie) = tmp;
    
  end  
end
