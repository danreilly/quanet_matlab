
function rx_at(frame_pd_asamps, frame_qty, opt_offset_asamps, ii, qq,...
              sim_hdl, lfsr)
  nxt_f_i=0;

  frame_by_frame=1;
  lfsr.reset();
  hdr = lfsr.gen(hdr_len_bits);
  hdr = repmat(hdr.',osamp,1);
  hdr = hdr(:)*2-1;

  nxt_f_i=0;
  for f_i=1:nn % for each frame

    % frame_off is zero based.
    frame_off=(f_i-1)*frame_pd_asamps + (itr-1)*frame_qty*frame_pd_asamps + opt_offset_asamps;

    if (frame_off+frame_pd_asamps > length(ii))
      break;
    end
    
    rng = (1:frame_pd_asamps)+frame_off;
          
    % fprintf('rng(1) %d\n', rng(1));

    % correlate for header in this frame
    ci = corr(hdr, ii(rng));
    cq = corr(hdr, qq(rng));
    c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
    [mxv mxi]=max(c2);

    % Because our corr pattern uses +1 for 1 and -1 for 0,
    % A positive correlation lies along pos x axis.
    hdr_ph_deg = atan2(cq(mxi),ci(mxi))*180/pi;
    hdr_phs_deg(f_i)=hdr_ph_deg;
    hdr_phs_deg_l = f_i;
          
    if (sim_hdl.do)
      
      sum_shft = floor(log2(hdr_len_bits -1));
      c2 = abs(ci)+abs(cq);
      m_c=max(abs(c2));
      fprintf('HDL: before crop max corr %d = x%x\n', m_c, m_c);
      c2 = bitshift(abs(ci)+abs(cq), -sum_shft);
      m_c=max(abs(c2));
      th = 2^sim_hdl.mag_w;
      % fprintf('max corr %d = x%x, crop thresh x%x\n', m_c, m_c, th);
      idxs = find(c2>=th);
      cl=length(idxs);
      c2(idxs)=th-1;
      idxs = find(c2<-th);
      cl=cl+length(idxs);
      c2(idxs)=-th;
      if (cl)
        fprintf('WARN: %d samples cropped\n', cl);
      end
      
      m_c=max(abs(c2));
      fprintf('after crop: max corr %d = x%x\n', m_c, m_c);
      %           elseif (mean_before_norm)
      %             ci_sum = ci_sum + ci/nn;
      %             cq_sum = cq_sum + cq/nn;
      %           else
    end



          
       if (frame_by_frame && (frame_i >= nxt_f_i))

            % TIME DOMAIN PLOT OF CURRENT FRAME
            ncplot.subplot(1,2);
            ncplot.subplot();
            if (0)
              t_us = 1e6*(rng-1).'/asamp_Hz;
              xunits = 'us';
            else
              t_us = rng;
              xunits = 'samples';
            end
            plot(t_us, ii(rng), '.-', 'Color',coq(1,:));
            plot(t_us, qq(rng), '.-', 'Color',coq(2,:));
            %plot(t_us, c2, '-', 'Color','red');
            [c2_mx c2_mi]=max(abs(c2));
            line([1 1]*t_us(c2_mi),[0 c2_mx],'Color','red');

            mx = max(mx, max(abs(c2))); % just for plot ylim
            if (c2_mi+hdr_len_asamps <= frame_pd_asamps)
              line([1 1]*t_us(c2_mi+hdr_len_asamps),[0 c2_mx],'Color','magenta');
              % dont plot hdr if not all of it is there.
              h_rng = c2_mi-1+(0:hdr_len_bits-1)*osamp + 2;
              h_rng = [h_rng; h_rng+1];
              h_rng = reshape(h_rng,[],1);
              plot(t_us(h_rng), ii(h_rng+frame_off), '.', 'Color', co(1,:));
              % plot(t_us(h_rng), qq(h_rng+frame_off), '.', 'Color', co(2,:));
            end

            if (1) % ~rx_going || ~body_adj_asamps)
              % CORRELATE FOR BCODE
              cbi = corr(code_asamps*2-1, ii(rng));
              cbq = corr(code_asamps*2-1, qq(rng));
              ccode = sqrt(cbi.^2 + cbq.^2)/hdr_len_bits;
              plot(t_us, ccode, '-', 'Color','yellow');
              th = std(ccode(qsdc_data_pos_asamps:end));
              % Find best starting offset
              el = qsdc_symbol_len_asamps*length(code); % 80
              si = qsdc_data_pos_asamps;
              sl = floor((length(rng)-si)/el)*el;
              si = si+1;
              ei = si+sl-1;
              ccode=sum(reshape(ccode(si:ei),el,[]).');
              [mx mi] = max(ccode);
              eh=floor(el/2);
              mi= mod(mi-1+eh,el)-eh; % an offset
              if (f_i==1)
                sug_body_adj_asamps = mi;
                fprintf('ccode max at %d,  si %d   adj %d\n', mi, si, sug_body_adj_asamps);
              end
            end
            line([1 1]*t_us(qsdc_data_pos_asamps + body_adj_asamps+1), ...
                 [0 c2_mx],'Color','blue');

            if (f_i==1)
              line([1 1]*t_us(qsdc_data_pos_asamps + sug_body_adj_asamps+1), ...
                   [0 c2_mx],'Color','green');
              if (qsdc_data_pos_asamps + sug_body_adj_asamps+qsdc_data_len_asamps-1 > length(t_us))
                fprintf('WARN: suggested offset seems to collides with next hdr.');
              else
                ei=min(qsdc_data_pos_asamps + sug_body_adj_asamps+qsdc_data_len_asamps-1,length(t_us));
                line([1 1]*t_us(ei), [0 c2_mx],'Color','blue');
              end
            end
            xlim([t_us(1) t_us(end)]);
            [mx mi]=max(pwr_all(rng));
            if (0)
              if (host)
                ncplot.txt(sprintf('host %s', host));
              end
              ncplot.txt(sprintf('frame %d = %.3fus', f_i, frame_off*frame_pd_us));
              %         ncplot.txt(sprintf('offset %d = time %.1f us', frame_off, frame_off*frame_pd_us));
              ncplot.txt(sprintf('max sqrt(I^2+Q^2)  %.1f', mx));
              if (find_hdr)
                ncplot.txt(sprintf('det:  pwr_thresh %d  corr_thresh %d', ...
                                   mvars.get('hdr_pwr_thresh'), mvars.get('hdr_corr_thresh')));
                ncplot.txt(sprintf('corr max %d at %.3fms = idx %d', ...
                                   round(c2_mx), t_us(c2_mi), c2_mi));
              end
            end
            % ylim([-1.2 1.2]*mx);
            xlabel(sprintf('time (%s)',xunits));
            ylabel('amplitude (adc)');
            ncplot.title({mname; fname_s});

            h_rng = rng(1)-1+(1:hdr_len_asamps);
            b_rng_off = qsdc_data_pos_asamps + body_adj_asamps;
            b_rng = rng(1)-1+b_rng_off+(1:qsdc_data_len_asamps);

            fprintf('        frame at idx %d\n', rng(1));
            fprintf('qsdc_data_pos_asamps %d\n', qsdc_data_pos_asamps);
            fprintf('     body_adj_asamps %d\n', body_adj_asamps);
            fprintf('    qsdc data offset %d (0 based)\n', b_rng_off);
            fprintf('    qsdc data at idx %d\n', b_rng(1));
            
            if (0)
              % DRAW CORRELATION WITH CODE
              % This approach did not work so well when I moved to 16cycle alice symbols
              ncplot.subplot();
              plot(1:length(ccode),ccode);
              xlabel('sample');
              title('correlation with code');
              uio.pause();
            end
            
            % DRAW IQ PLOT OF HEADER
            ncplot.subplot();
            ncplot.iq(ii(h_rng),qq(h_rng));
            h_srng = frame_off+c2_mi-1 + floor(osamp/2) + (0:hdr_len_bits-1)*osamp;
            plot(ii(h_srng),qq(h_srng),'.', 'Color','blue');
            plot(ii(b_rng),qq(b_rng),'.', 'Color','green');
            mx=max([abs(ii);abs(qq)]);
            c=cos(hdr_ph_deg*pi/180)*mx;
            s=sin(hdr_ph_deg*pi/180)*mx;
            line([0 c],[0 s],'Color','blue');
            ncplot.title({'IQ plot of header'; fname_s});
            ncplot.txt(sprintf('frame %d', f_i));
            ncplot.txt(sprintf('phase %d deg', round(hdr_ph_deg)));
            
            if (rx_going)
              uio.pause('review frame');
            else
              uio.print_wrap('The region of time plot between the two dark blue lines is where the data should be.  If not, you can adjust it.');
              fprintf('Current (blue): %d\n', body_adj_asamps);
              if (f_i==1)
                fprintf('Recommend (green): %d\n', sug_body_adj_asamps);
              end
              
              body_adj_asamps = mvars.ask('data body adj (asamps)','body_adj_asamps',0);
              if (~in_archive)
                mvars.save();
              end
              %            body_adj_ns = tvars.ask('data body adj (ns)','body_adj_ns',1);
              %            tvars.save();
              %            body_adj_asamps = round(body_adj_ns*1e-9*asamp_Hz);
              %            fprintf('    that is %d samples\n', body_adj_asamps);
              rx_going=1;
            end
          end % if frame by frame

          frame_i=frame_i+1;
          % data = cipher_lfsr.gen(bits_per_frame);

          b_rng_off = qsdc_data_pos_asamps + body_adj_asamps;
          b_rng = rng(1)-1+b_rng_off+(1:qsdc_data_len_asamps);
          if (phase_est_en)
            derot_deg = 0;
            desc='HDL derot';
          elseif (cheat)

            nsyms = qsdc_data_len_asamps/qsdc_symbol_len_asamps;
            exp_asamps=zeros(qsdc_data_len_asamps,1);
            for k=1:nsyms
              if (sym_i+k-1 > length(txed_syms))
                break;
              end
              c=txed_syms(sym_i+k-1); % current codebit
              exp_asamps((k-1)*qsdc_symbol_len_asamps + (1:qsdc_symbol_len_asamps),1) = ...
                  repmat(c, qsdc_symbol_len_asamps, 1);
            end
            cci = sum(ii(b_rng).*exp_asamps);
            ccq = sum(qq(b_rng).*exp_asamps);
            derot_deg = 180+atan2(ccq,cci)*180/pi;
            
            % derot_deg = calc_derot(ii(b_rng),qq(b_rng), hdr_ph_deg);
            desc='ideal';
          elseif (~cheat)
            derot_deg = hdr_ph_deg + body_ph_offset_deg;
            desc='hdr ang';
          else
            derot_deg = 0;
            desc='raw';
          end
          iiqq = geom.rotate(-derot_deg*pi/180, [ii(b_rng).';qq(b_rng).']);
          d_ii=iiqq(1,:).';
          d_qq=iiqq(2,:).';

          % ignore transition symbols
          nsyms = qsdc_data_len_asamps/qsdc_symbol_len_asamps;
          trans_rng=(0:nsyms-1)*qsdc_symbol_len_asamps;
          e_rng = setdiff(1:qsdc_data_len_asamps, trans_rng+1);
          e_rng = setdiff(e_rng,                  trans_rng+qsdc_symbol_len_asamps);
          e_rng=e_rng(:);

          % CALC SYMBOL ERRORS IN FRAME
          % TODO: this is really only coded for BPSK.  do other mods too.
          err_sum=0;
          errmsk=logical(zeros(nsyms,1));
          rxed_ii = zeros(nsyms,1);
          rxed_qq = zeros(nsyms,1);
          sl = qsdc_symbol_len_asamps;
          bit_i_sav = bit_i;
          bit_n_sav = bit_n;
          bit_errs = 0;
          bit_cnt  = 0;
          for k=1:nsyms
            if (sym_i+k-1 > length(txed_syms))
              break;
            end
            % per-symbol mean, ignoring transition if possible
            if (sl>2)
              sym_ii=mean(d_ii((k-1)*sl+(2:sl-1)));
              sym_qq=mean(d_qq((k-1)*sl+(2:sl-1)));
            else
              sym_ii=mean(d_ii((k-1)*sl+(1:sl)));
              sym_qq=mean(d_qq((k-1)*sl+(1:sl)));
            end
            rxed_ii(k) = sym_ii;
            rxed_qq(k) = sym_qq;
            
            c=txed_syms(sym_i+k-1); % current codebit
            e=logical(c~=(sym_ii<0));
            
            err_sum = err_sum+e;
            errmsk(k) = e;
            nsyms_actual = k;
          end
          
          symbol_ber = err_sum/nsyms_actual;
          if (cheat && (symbol_ber>.5))
            fprintf('FLIP %d\n', frame_i);
            err_sum = nsyms_actual-err_sum;
            symbol_ber = 1-symbol_ber;
            derot_deg = derot_deg +180;
            d_ii=-d_ii;
            d_qq=-d_qq;
            rxed_ii = -rxed_ii;
            rxed_qq = -rxed_qq;
            errmsk = ~errmsk;
          end
          if (k<nsyms)
            errmsk(k+1:nsyms)=0;
          end

          symbol_bers(f_i) = symbol_ber;
          sym_err_cnt = sym_err_cnt + err_sum;
          sym_cnt = sym_cnt + nsyms_actual;
          data_derot_degs(f_i)=derot_deg;

          for k=1:nsyms
            if (sym_i+k-1 > length(txed_syms))
              break;
            end
            % Take mean of symbols over duration of bit,
            % multiplied by sign of bcode.
            % This is essentially a correlation with bcode.
            bit_ii = bit_ii + rxed_ii(k) * (bcode(bit_n)*2-1);
            bit_qq = bit_qq + rxed_qq(k) * (bcode(bit_n)*2-1);
            bit_n  = bit_n + 1;
            if (bit_n > qsdc_bit_dur_syms)
              % fprintf('bit %d expect %d  is %.2f\n', bit_i, txed_bits(bit_i), bit_ii);
              bit_errs = bit_errs + ((bit_ii<0) ~= txed_bits(bit_i));
              bit_cnt = bit_cnt+1;
              bit_i=bit_i+1;
              bit_ii=0;
              bit_qq=0;
              bit_n=1;
            end
            sym_i = sym_i + 1;
          end
          

          allbit_errs = allbit_errs+bit_errs;
          allbit_cnt  = allbit_cnt +bit_cnt;
          if (frame_by_frame && (frame_i>=nxt_f_i))
            % PlOT DATA VS INDEX, SUPERIMPOSE ERRORS IN REGD
            ncplot.init();
            ncplot.subplot(1,2);
            ncplot.subplot();
            mx=max(max(d_ii),max(d_qq));
            plot(1:qsdc_data_len_asamps, d_ii,'-','Color',coq(1,:));
            % plot(1:qsdc_data_len_asamps, d_qq,'-','Color',coq(2,:));

            is=(frame_i-1)*qsdc_data_len_asamps+1;
            ie=min(is+qsdc_data_len_asamps-1, length(txed_asamps));
            txrng= is:ie;
            plot(txrng-(is-1), (2*txed_asamps(txrng)-1)*mx/2, '-','Color','yellow');

            fprintf('i&q start at idx %d = %s\n', b_rng(1), uio.dur((b_rng(1)-1)/asamp_Hz,3));

            expect = (2*txed_asamps(txrng)-1).';
            dc_i = expect * d_ii(1:length(txrng));
            dc_q = expect * d_qq(1:length(txrng));
            
            xlim([1 qsdc_data_len_asamps]);
            if (0) % emphasize points
              plot(e_rng, d_ii(e_rng),'.','Color',ch(1,:));
              plot(e_rng, d_qq(e_rng),'.','Color',ch(2,:));
            else   % draw line at means
              for k=1:nsyms
                line((k-1)*qsdc_symbol_len_asamps+[1 qsdc_symbol_len_asamps], ...
                     rxed_ii(k)*[1 1],'Color',ch(1,:));
                %  line((k-1)*qsdc_symbol_len_asamps+[1 qsdc_symbol_len_asamps], ...
                %             rxed_qq(k)*[1 1],'Color',ch(2,:));
                bit_n_sav = bit_n_sav+1;
                if (bit_n_sav >= qsdc_bit_dur_syms) % black divider between bits
                  line(k*qsdc_symbol_len_asamps+.5*[1 1],[-1 1]*mx/2,'Color','black');
                  bit_i_sav=bit_i_sav+1;
                  bit_n_sav=0;
                end
              end
            end     
            symrng = (0:(nsyms-1)).'*qsdc_symbol_len_asamps + qsdc_symbol_len_asamps/2+.5;
            plot(symrng(errmsk), rxed_ii(errmsk), '.', 'Color','red');
            if (0)
            ncplot.txt(sprintf('frame %d', frame_i));
            ncplot.txt(desc);
            ncplot.txt(sprintf('derotated %.1f deg%s', derot_deg,util.ifelse(cheat,' (cheat)','')));
            ncplot.txt(sprintf('data bits %d  errors %d', bit_cnt, bit_errs));
            end
            ncplot.txt(sprintf('frame %d symbol ER %g', frame_i, symbol_ber));

          xlabel('index');
          ncplot.title({'time plot of QSDC data'; fname_s});

          if (0)
            ci = corr_circ(data(1:32), d_ii);
            cq = corr_circ(data(1:32), d_qq);
            c2 = sqrt(ci.^2 + cq.^2)/hdr_len_bits;
            [ds dsi] =  max(c2);
            if (dsi>0)
              line(dsi, [0 c2_mx],'Color','black');
            end
          end


          % DRAW IQ PLOT OF BODY
          ncplot.subplot();
          ncplot.iq(d_ii, d_qq);
          h_srng = body_adj_asamps+frame_off+qsdc_data_pos_asamps+(0:nsyms-1)*4 + 2;
          plot(d_ii(e_rng), d_qq(e_rng), '.', 'Color','blue');
          rad = sqrt(mean(d_ii(e_rng).^2+d_qq(e_rng).^2));
          ncplot.txt(desc);
          ncplot.txt(sprintf('frame %d', frame_i));
          ncplot.txt(sprintf('derotated by %.1f', derot_deg));
          ncplot.txt(sprintf('sqrt <I^2+Q^2> = %.1f', rad));
          ncplot.title({'IQ plot of QSDC data'; fname_s});
          end % if frame by frame

            

          if (frame_by_frame && (frame_i >= nxt_f_i))          
            choice = uio.ask_choice('(n)ext, (s)skipto,  goto (e)nd, or (q)uit', 'nseq', choice);
            if (choice=='q')
              return;
            elseif (choice=='s')
              nxt_f_i = uio.ask('skip to which frame', 0);
            elseif (choice=='e')
              tic();
              frame_by_frame=0;
            end
          end

          if (is+qsdc_data_len_asamps-1 >  length(txed_asamps))
            break;
          end
      end % for f_i (each frame)
end
