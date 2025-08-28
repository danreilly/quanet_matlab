function opt_skip=find_qsdc_first(ii, qq, mvars, tvars, txed_asamps)
  import nc.*
  
  % INPUT PARAMS
  qsdc_data_pos_asamps = tvars.get('qsdc_data_pos_asamps',[]);
  cheat = tvars.get('cheat');
  ffi=  tvars.get('first_frame_idx');
  
  osamp = mvars.get('osamp', 4);
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  hdr_len_asamps = hdr_len_bits * osamp;
  nonhdr_len_asamps = frame_pd_asamps - hdr_len_asamps;
  asamp_Hz = mvars.get('asamp_Hz', 0);

  hdr_len_bits = mvars.get('hdr_len_bits', 0);

  
  qsdc_data_len_asamps = mvars.get('qsdc_data_len_asamps',0);
  qsdc_code_len_cbits = mvars.get('qsdc_code_len_cbits',10);
  qsdc_data_is_qpsk = mvars.get('qsdc_data_is_qpsk',0);
  qsdc_symbol_len_asamps = mvars.get('qsdc_symbol_len_asamps',4);
  qsdc_bit_dur_syms = mvars.get('qsdc_bit_dur_syms',10);
  qsdc_bit_dur_s = qsdc_bit_dur_syms * qsdc_symbol_len_asamps / asamp_Hz;

  body_ph_offset_deg = mvars.get('body_ph_offset_deg');

  opt_plot=1;
  
  f_l=floor((length(ii)+1-ffi)/frame_pd_asamps); % for each frame

  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  lfsr = lfsr_class(hex2dec('a01'), hex2dec(lfsr_rst_st));

  opt_skip=0;  
  
  lfsr.reset();
  hdr = lfsr.gen(hdr_len_bits);
  hdr = repmat(hdr.',osamp,1);
  hdr = hdr(:)*2-1;

  hdr_phs_deg=zeros(f_l,1);
  vmx=0;
  vmi=0;
  vfi=0;
  for sf_i=1:f_l % for each start frame

    c_sum = zeros(nonhdr_len_asamps-qsdc_data_len_asamps+1,1);
    first_frame_off = (sf_i-1)*frame_pd_asamps + ffi-1; % 0 based
    f_i_lim = min(100, (f_l-sf_i+1));
    body_phs_deg=zeros(f_l, length(c_sum));
    for f_i=1:f_i_lim
      
      frame_off = first_frame_off + (f_i-1)*frame_pd_asamps; % 0 based
      h_rng = frame_off+(1:hdr_len_asamps);
      b_rng = frame_off + hdr_len_asamps +  (1:nonhdr_len_asamps);

      if (sf_i==1)
        ci = hdr.'*ii(h_rng);
        cq = hdr.'*qq(h_rng);
        hdr_ph_deg = atan2(cq,ci)*180/pi;
        hdr_phs_deg(f_i)=hdr_ph_deg;
      end
      
      if (0)
        if (cheat)
          derot_deg = calc_derot(ii(b_rng),qq(b_rng), hdr_ph_deg);
          desc='ideal';
        else
          derot_deg = hdr_ph_deg + body_ph_offset_deg;
          desc='hdr ang';
        end
        iiqq = geom.rotate(-derot_deg*pi/180, [ii(b_rng).';qq(b_rng).']);
        d_ii=iiqq(1,:).';
        d_qq=iiqq(2,:).';
      else
        d_ii=ii(b_rng);
        d_qq=qq(b_rng);
      end

      frame_syms = txed_asamps((f_i-1)*qsdc_data_len_asamps + (1:qsdc_data_len_asamps))*2-1;
      %      frame_syms(1:32)
      c_ii = corr(frame_syms, d_ii, 'valid');
      c_qq = corr(frame_syms, d_qq, 'valid');
      
      body_phs_deg(f_i,:) = atan2(c_qq,c_ii)*180/pi;
      
      c = round(sqrt(c_ii.^2+c_qq.^2));
      c_sum = c_sum+c;
    end
    [mx mxi]=max(c_sum);
    if (opt_plot)    
      ncplot.init();
      k=qsdc_data_pos_asamps - hdr_len_asamps+1;

      line(k*[1 1],[0 mx],'Color','green');
      ncplot.txt(sprintf('start frame %d\n', sf_i));
      if (mx > vmx)
        vmx=mx;
        vmi=mxi;
        vfi=sf_i;
      else
        ncplot.txt(sprintf('prior max in frame %d\n', vfi));
      end
      ncplot.txt(sprintf('max %d at idx %d\n', mx, mxi));
      ncplot.txt(sprintf('offset from expected at %d (green) %d\n', k, mxi - k))
      xlabel('index');
      ylim([0 vmx]);
      plot(1:length(c_sum),c_sum,'.');
      fprintf('frame %d at idx %d\n', sf_i, first_frame_off+1);
      fprintf('   max %d at idx %d\n', mx, mxi + hdr_len_asamps + first_frame_off);
      if (uio.ask_yn('is this it?',0))


        ncplot.init();
        [co,ch,cq]=ncplot.colors();
        hdr_phs_deg=mod(hdr_phs_deg(1:f_i_lim)+180,360)-180;
        hdr_phs_deg = util.mod_unwrap(hdr_phs_deg, 360);
        
        body_phs_deg=body_phs_deg(:,mxi);
        body_phs_deg=mod(body_phs_deg(1:f_i_lim)+180,360)-180;
        body_phs_deg = util.mod_unwrap(body_phs_deg, 360);
        
        d_deg = body_phs_deg-hdr_phs_deg;
        d_deg(1)=mod(d_deg(1)+180,360)-180;
        d_deg = mod(d_deg+180-d_deg(1),360)-180+d_deg(1);
        d_deg = util.mod_unwrap(d_deg, 360);
        plot(1:f_i_lim, hdr_phs_deg,  '.', 'Color', cq(1,:));
        plot(1:f_i_lim, body_phs_deg, '.', 'Color', cq(2,:));
        plot(1:f_i_lim, d_deg,        '-', 'Color', co(3,:));
        ncplot.txt(sprintf('mean body-hdr %d\n', round(mean(d_deg))));
        if (uio.ask_yn('look ok',0))
          opt_skip = sf_i-1;        
          break;
        end
      end
    end
  end % start frames
end

