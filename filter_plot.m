function res = filter_plot(b, a, fsamp_Hz, range_Hz, opt)

  opt.foo = 1;
  opt = set_if_undef(opt, 'cross', []);
  opt = set_if_undef(opt, 'num_points', 100);

  f_s = 10.^(linspace(log10(range_Hz(1)), ...
                      log10(min(fsamp_Hz/2,range_Hz(2))), opt.num_points).');
  gains_dB = zeros(opt.num_points,1);

  orda = length(a)-1;
  ordb = length(b)-1;

  f_s_l = length(f_s);
  for k=1:f_s_l
    h = (b * exp(j*2*pi *  f_s(k)/fsamp_Hz * (0:ordb).')) / ...
        (a * exp(j*2*pi *  f_s(k)/fsamp_Hz * (0:orda).'));
    gains_dB(k)=10*log10(real(h * conj(h)));
  end

  idx = 1;
  k=0;
  cr=zeros(1,0);
  if (~isempty(opt.cross))
    while(1)
      if (gains_dB(idx)>opt.cross)
        idx = find(gains_dB(idx:end)<opt.cross,1)+idx-1;
        if (isempty(idx))
          break;
        end
        k=k+1;
        cr(k)=f_s(idx);
      end
      idx = find(gains_dB(idx:end)>opt.cross,1)+idx-1;
      if (isempty(idx))
        break;
      end
      if (~isempty(idx))
        k=k+1;
        cr(k)=f_s(idx);
      end
    end
    res.crossings = cr;
  end
  plot(f_s, gains_dB, '.');
  xlim([f_s(1) f_s(end)]);
  ylabel('gain (dB)');
  xlabel('freq (Hz)');
end

function s = set_if_undef(s, fldname, val)
  if (~isfield(s, fldname))
    s = setfield(s, fldname, val);
  end
end
