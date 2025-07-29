function t7
    % freq dependence of aerodiode laser apon current
    i_ma = [42.7 44.3 45.6];
    diff(i_ma)
    i_wl_nm = [1548.503 1548.518 1548.535];
    diff(i_wl_nm)
    c = 3e8;
    f0_Hz = c / (i_wl_nm(1)*1e-9)

    df_Hz = diff(i_wl_nm)./i_wl_nm(1) .* f0_Hz;

    plot(diff(i_ma), df_Hz/1e6,'.');
    xlabel('curr change (mA)');
    ylabel('freq change (MHz)');

    round(df_Hz/1e6 ./ diff(i_ma))
'MHz per ma'    

    
end
