function plot_nstd_vs_pings
    import nc.*
    stds=[11.2 7.9 6.4 5.5  5.0];
    frames=[25 50 75 100 125];
    hdr_len_bits=128;
    sig_pwr_dBm = -61;
    sfp_pwr_dBm = -41;
    fiber_len_m = 2000;
    
    
    ncplot.init();
    plot(frames, stds, '.-');
    ncplot.txt(sprintf('sig %.1f dBm', sig_pwr_dBm));
    ncplot.txt(sprintf('sfp %.1f dBm', sfp_pwr_dBm));
    ncplot.txt(sprintf('hdr len %d bits', hdr_len_bits));
    ncplot.txt(sprintf('fiber len %sm', uio.sci(fiber_len_m)));
    xlabel('number of pings');
    ylabel('std of correlation noise floor (ADC)');
    ncplot.title('plot_nstd_vs_pings');
end
