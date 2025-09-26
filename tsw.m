function tsw
  import nc.*
  mname='tsw.m';
  fprintf('%s\n', mname);
  uio.print_wrap('This sweeps the correlation threshold measures the rate of correlation counts (number per 1000 frames), while keeping the sync delay fixed.  It finds a threshold resulting in a sharp spike in correlations.  Use this after changing transmit power.');
  qna1_1=qna1_class('com11');
  zcu1 = zcu_u_cli_class('tcp@169.254.3.4:8921');
  zcu2 = zcu_u_cli_class('tcp@169.254.15.98:8921');
  qna2_2=qna2_class('com1');

  fprintf('setting Bob to transmit always\n');
  zcu1.set_tx_always(1);

  find_thresh(zcu2);

  fprintf('setting Bob to NOT transmit always\n');
  zcu1.set_tx_always(0);
  
  return;
  
  %NESTED
  function err = find_thresh(zcu)
    import nc.*
    
    thi = round(zcu.settings.corr_thresh * 1.1);
    thi = max(200, thi);
    ths=(thi:-2:1);
    
    ths_l = length(ths);
    m=zeros(ths_l,1);
    for t_i=1:ths_l
      th = ths(t_i);
      zcu.set_corr_thresh(th);
      cnt = zcu.meas_cnt();
      m(t_i) = cnt;
    end
    ths
    mx=max(m);
    idx=find(m==mx,1); % sweep is backwards
    idx = min(idx+3, length(ths));
    th = ths(idx);
    zcu.set_corr_thresh(th);
    ncplot.init();
    plot(ths, m,'.');
    plot(th, mx,'.','Color','red');
    xlabel('thresh (ADC)');
    ylabel('number of pilots detected');
    ncplot.txt(sprintf('sync_dly %d (fixed)', zcu.settings.syn_dly));
    ncplot.txt(sprintf('thresh %d', th));
    ncplot.title({mname;'sweep of correlation threshold'});
    figure(gcf());
  end


end

