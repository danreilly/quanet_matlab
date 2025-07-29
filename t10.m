
function t10
    import nc.*
    o_mv = [-288 -260 -228 -180 -84 16 108 176 272];
    itr  = [   4    5   6     7   8  9  10  11  12];
    ncplot.init();
    d_ns =  9.5 + (itr-4)*(13-9.5)/(12-4);
    plot(d_ns, o_mv,'.');
    ncplot.txt('input sig 100MHz');
    xlabel('input delay (ns)');
    ylabel('ouput (mV)');
    title('Quiescent response of SYPD2');
end
