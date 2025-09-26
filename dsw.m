function dsw
  import nc.*
  mname='dsw.m';
  fprintf('%s\n', mname);
  uio.print_wrap('This sweeps the sync delay and measures correlation counts.  It finds a delay and threshold that result in a sharp spike in correlations.  Use this after setting polarizations, and before fine-tuning the trasnmit power.');
  qna1_1=qna1_class('com11');
  qna1_1.set_voa_attn_dB(1, 10);
  
  qna2_2=qna2_class('com1');

  zcu1 = zcu_u_cli_class('tcp@169.254.3.4:8921');
  zcu2 = zcu_u_cli_class('tcp@169.254.15.98:8921');

  zcu1.set_tx_always(1);
  
  find_sync_dly(zcu2);
  
  zcu1.set_tx_always(0);
end


function err = find_sync_dly(zcu)
  import nc.*
  th = 100;
  %  zcu.ser.set_dbg(1);
  zcu.set_corr_thresh(th);

  plot_all=1;
  if (plot_all)
    ncplot.init();
    [co,ch,cq]=ncplot.colors();
  end
  for tri=1:100
    h = zcu.dsweep();% a row vec
    h_l = length(h);
    dlys=((1:h_l)-1)*4;
    if (plot_all)    
     plot(dlys, h, '-','Color',co(1,:));
    end    
    [mx mi]=max(h);
    %    fprintf('raw hist:\n');
    %    find(h==mx)
    
    sh=round(h_l/2)-mi;
    h2=circshift(h,[1,sh]); % center the maximums
    [mx mi2]=max(h2);
    idxs=find(h2==mx); % the largest ones
    
    fprintf('try %d: th %d  mx %d  at %d  width %d\n', tri, th, mx, mi, length(idxs));

    if (length(idxs)<2)
      th = round(zcu.settings.corr_thresh/2);
      fprintf('decrease\n');
      if (th<2)
        fprintf('ERR: no pilots seen\n');
        err=1;
        return;
      end
      zcu.set_corr_thresh(th);
    elseif ( (length(idxs)>4) || ~(all(diff(idxs)==1)))
      % too many or not all contiguous
      th = round(zcu.settings.corr_thresh+10);
      zcu.set_corr_thresh(th);
    elseif (mx<1020)
      th = th-5;
      zcu.set_corr_thresh(th);      
    else
      %      ci=ceil(length(idxs)/2);
      %      idx=idxs(ci);
      idx = idxs(1);
      idx = mod(idx-1-sh, h_l)+1; % shift back to actual idx



      dly = (idx-1)*4;

      fprintf('set dly %d\n', dly);
      zcu.set_sync_dly(dly);
      zcu.get_settings();
      pause(0.2);
      dly = zcu.settings.syn_dly;
      [avg mx cnt] = zcu.meas_pwr();
      [avg mx cnt] = zcu.meas_pwr();
      cnt
      
if (0)      
      zcu.set_sync_dly(dly+4);
      zcu.get_settings();
      pause(0.2);
      dly = zcu.settings.syn_dly
      [avg mx cnt] = zcu.meas_pwr();
      [avg mx cnt] = zcu.meas_pwr();
      cnt

      zcu.set_sync_dly(dly+4);
      zcu.get_settings();
      pause(0.2);
      dly = zcu.settings.syn_dly
      [avg mx cnt] = zcu.meas_pwr();
      [avg mx cnt] = zcu.meas_pwr();
      cnt
end
      
      dlys=((1:h_l)-1)*4;
      plot(dlys, h, '.');
      plot(dly, h((dly/4)+1), '.','Color','red');
      ncplot.txt(sprintf('sync dly %d', dly));
      ncplot.txt(sprintf('thresh %d', th));
      ncplot.txt('Sweep of sync dly vs Pilot Detection');
      xlabel('sync delay (cycles)');
      ylabel('pilot correlation (ADC)');
      zcu.set_io_dbg(1);
      zcu.settings
      err = 0;
      return;
    end
    
  end
end
