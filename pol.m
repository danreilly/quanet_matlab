function pol
  import nc.*
  mname='pol.m';
  fprintf('%s\n', mname);
  uio.print_wrap('This sweeps the receiver waveplates while measuring recieved IQ power.  It finds settings that maximize this power.');
  
  zcu1 = zcu_u_cli_class('tcp@169.254.3.4:8921');
  qna1_1=qna1_class('com11');
  qna1_2=qna2_class('com9');

  zcu2 = zcu_u_cli_class('tcp@169.254.15.98:8921');
  qna2_2=qna2_class('com1');

  fprintf('setting Bob to transmit always\n');
  zcu1.set_tx_always(1);
  
  b=7;
  fprintf('setting Bob VOA attn %d\n', b);
  qna1_1.set_voa_attn_dB(1, 10);

  fprintf('setting Alice rx polarization\n');
  efpc_search(qna2_2, zcu2);
  
  fprintf('setting Bob rx polarization\n');
  efpc_search(qna1_2, zcu1);


  fprintf('setting Bob to NOT transmit always\n');
  zcu1.set_tx_always(0);
  
end

function efpc_search(qna, zcu)
  rets_deg=0:10:400;
  rets_l=length(rets_deg);
  pwrs=zeros(1,rets_l);
  mmx=0;
  dbg=0;
  wp=1;
  tries=0;
  while(1)
    fprintf('wp%d: ', wp);
    for r_i=1:rets_l
      qna.set_waveplates_deg(2, wp, rets_deg(r_i));
      if (r_i==1)
        %        pause(0.3);
      end
      [avg mx cnt] = zcu.meas_pwr();
      [avg mx cnt] = zcu.meas_pwr();
      pwrs(r_i) = mx;
      if (dbg)
        fprintf(' %d', mx);
      end
    end
    if (dbg)
      fprintf('\n');
    end
    [mx mi]=max(pwrs);
    mmx=max(mx, mmx);
    qna.set_waveplates_deg(2, wp, rets_deg(mi));
    pause(0.3);    
    [avg mx cnt] = zcu.meas_pwr();
    [avg mx cnt] = zcu.meas_pwr();
    
    fprintf('%d -> %d\n', rets_deg(mi), mx);
    if (dbg)
      mx
      pause();
    end
    tries=tries+1;
    if ((tries>=3)&&(mx>0.95*mmx))
      break;
    end
    wp=mod(wp,3)+1;
  end
end
