function t2
    import nc.*
    ncplot.init();
    ncplot.subplot(1,2);
    if (1)
      nframes = 212;
      p_dBm = [-76 -71 -61 -52]; % peak
      q     = [ 2.4 4.3 8.6  14];
      pk_adc = [38 58  171  486];
      str='NO Connet, method 3';
      desc = 'sfp-sig = 30dB';
    elseif (1)
      nframes = 212;
      p_dBm = [-76 -71 -61 -52]; % peak
      q     = [ 4 6 10 16];
      pk_adc = [28 49 156 454];
      str='NO Connet, method 2';
      desc = 'sfp-sig = 30dB';
      
    elseif (1)
      nframes = 425;
      p_dBm  = [-65 -60 -50]-8.3; % quadrature pwr
      p_dBm = p_dBm+3; % peak
      q      = [2.9  4  8.4];
      pk_adc = [44  78 273];
      p_dBm = p_dBm+3; % peak
      str='Connet CC 65mA';
      desc = 'sfp-sig = 30dB';
        
    elseif (0)
      nframes = 425;
      p_dBm  = [-70 -65 -55]-8.3; % quadrature pwr
      p_dBm = p_dBm+3; % peak
      p_dBm
      pk_adc = [33 33 107];
      q = [2.1  2.9  3.6];
      str='Connet CC 65mA';
      desc = 'sfp-sig = 35dB';
    else
      nframes=200;                
      p_dBm=[-30 -50 -60 -70 -80];
      pk_adc=[8817 2923 483 256 73];
      str='Connet CC 72mA';
      desc='';
    end
    p_mW=10.^(p_dBm/10);
    
    ncplot.subplot();
    plot(p_dBm, pk_adc, '.');
    set(gca(),'YScale','log');
    ncplot.txt(str);
    ncplot.txt(desc);
    xlabel('signal peak (dB)');
    ylabel('correlation peak (ADC)');
    ncplot.title({'sensitivity'; str});

    ncplot.subplot();
    plot(p_dBm, q, '.');
    ncplot.txt(str);
    ncplot.txt(desc);
    xlabel('signal peak (dB)');
    ylabel('quality factor (Q)');
    ncplot.title({'sensitivity'; str});

    
end
    
