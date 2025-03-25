function sig = ideal_notch_filter(sig, fs, fc, bw)
  l = length(sig);
  ts1 = timeseries(sig, (0:l-1).'/fs);
  ts2 = idealfilter(ts1, [fc-bw/2 fc+bw/2], 'notch');
  sig = ts2.data;
end
