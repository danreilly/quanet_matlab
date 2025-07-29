function track
  import nc.*
  mname='track.m';

  n=1024;
  %  n=16;
  data = (rand(1,n)>0.5);


  use_dpsk=0;



  npwrs=(1:30)/10;  
  %  npwrs= 0.1;
  %  npwrs = .6;
  %  npwrs = .2;
  npwrs_l = length(npwrs);
  opt_show=(npwrs_l==1);
  

  snrs_dB= zeros(2, npwrs_l);
  bers   = zeros(2, npwrs_l);

  ncplot.init();
  [co,ch,cq]=ncplot.colors();
  ncplot.subplot(3,1);


  for r=1:2
    use_dpsk=(r==2);

    if (use_dpsk)
      syms = 1 - (ps_enc(data)*2);
      if (n<32)
        data
        syms
      end
    else
      syms = 1-data*2;
    end
      
    for n_i=1:npwrs_l
      npwr = npwrs(n_i);        
      noise = npwr * (randn(1,n)+i*randn(1,n));
      noise_rms = sqrt(mean(real(noise).^2+imag(noise).^2));
      syms_n = syms + noise;

      ii=real(syms_n);
      qq=imag(syms_n);

      snr_dB = 10*log10(1/(noise_rms^2));
      snrs_dB(r, n_i) = snr_dB;
      if (opt_show)
          ncplot.subplot();
          m=max(max(abs(ii)),max(abs(qq)));
          set(gca(),'PlotBoxAspectRatio', [1 1 1]);
          plot(ii,qq,'.','Color',cq(1,:));
          xlim([-m m]);
          ylim([-m m]);
          if (~use_dpsk)
              line([0 0],[-1 1],'Color','green');
          end
          ncplot.title({mname; 'IQ scatterplot'});
          ncplot.txt(util.ifelse(use_dpsk,'DPSK','BPSK'));
          ncplot.txt(sprintf('noise %.3g rms', noise_rms));
          ncplot.txt(sprintf('  SNR %.1f dB', snr_dB));
      end

      
      if (use_dpsk)
        if (1)
          n1 = 1; % abs(ii)+abs(qq);
          ii_n = ii./n1;
          qq_n = qq./n1;
          p_i=1;
          p_q=0;
          cth = zeros(1,n);
          for k=1:n
            cth(k) = ii_n(k)*p_i+qq_n(k)*p_q;
            rx(k)  = cth(k)<0;
            p_i = ii_n(k);
            p_q = qq_n(k);
          end
          if (n<32)
            ncplot.subplot();
            plot((1:n).',[ii_n.' qq_n.'], '.-');
            ncplot.title('1-normed I and Q');

            ncplot.subplot();
            plot((1:n), cth, '.-');
            ncplot.title('dot product');
          end
          
        else
          if (n<32)  
            ncplot.subplot();
            plot((1:n).',[ii.' qq.'],'.-');
            ncplot.title('I and Q over time');
         end  

            
        rx_deg=atan2(qq, ii)*180/pi;
        df_deg=diff([0 rx_deg]);
        df_deg = mod(df_deg+90,360)-90;
        if (n<32)
          ncplot.subplot();
          plot(1:n,rx_deg,'.-','Color',ch(1,:));
          % plot(1:n,df_deg,'.-','Color',ch(2,:));
          ylabel('phase (deg)');
          ncplot.title('phase of sample');
        end
        rx = abs(df_deg)>90;
        end
        if (0)
          rx=zeros(1,n);
          df=zeros(1,n);
          prev = 1;
          th=1/sqrt(2);
          for k=1:n
            df(k) = abs(syms_n(k)-prev);
            rx(k) = df(k)>th;
            prev = syms_n(k);
          end
          if (n<32)
            ncplot.subplot();
            plot(1:n,df,'.-');
            ncplot.title('magnitude of vector difference');
          end
          
        end
          
      else
          rx = syms_n<0;
      end
      ber = sum(data ~= rx)/n;
      if (opt_show)
        ncplot.txt(sprintf('BER %g', ber));
        uio.pause();
      end
      bers(r, n_i)=ber;
    end % n_i
  end  
  ncplot.subplot();
  for k=1:2
    plot(snrs_dB(k,:), bers(k,:), '.', 'Color',ch(k,:));
  end
  legend({'tracked BPSK','DPSK'});
  xlabel('SNR (dB)');
  ylabel('BER');
  ncplot.title(mname);
  
end

function dout = ps_enc(data)
  l=length(data);
  dout=zeros(1,l);
  prev=0;
  for k=1:l
    prev = mod(data(k) + prev,2);
    dout(k)= prev;
  end
end

function dout = ps_dcd(data)
  l=length(data);
  dout=zeros(1,l);
  prev=0;
  for k=1:l
    dout(k) = mod(prev+data(k),2);
    prev = data(k);
  end
end
