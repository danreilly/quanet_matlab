function rp
  import nc.*


  opt_show=1;
  if (nargin>0)
      [skip n]=sscanf(arg,'%d')
      if (n==1)
        skip
      else
        opt_show=1;
      end
  end
  
  tvars = nc.vars_class('tvars.txt');
 

  fname='';
  
  dflt_fname_var = 'fname';
  fn_full = tvars.get(dflt_fname_var,'');
  max_fnum = 0; % tvars.get('max_fnum', 0);
  if (iscell(fn_full))
    str = fn_full{1};
  else
    str = fn_full;
  end
  [n is ie] = fileutils.num_in_fname(str);
  if (ie>0)
    places = ie-is+1;
    fmt = ['%s%0' num2str(places) 'd%s'];
    fn2 = sprintf(fmt, str(1:is-1), n+1, str(ie+1:end));

    
    if (0) % exist(fn2, 'file') && (max_fnum<=n))
      fprintf('prior file:\n  %s\n', str);
      fprintf('but newer file exists:\n  %s\n', fn2);
      fprintf('use it?');
      if (nc.uio.ask_yn(1))
        tvars.set('fname', fn2);
        tvars.set('max_fnum', n+1);
        fname =fn2;
      end
    end
    
  end
  if (isempty(fname))  
    fname = tvars.ask_fname('data file', 'fname');
  end
  pname = fileparts(fname);
  pname_pre = fileparts(str);
  if (~strcmp(pname, pname_pre))
    'new dir'
    tvars.set('max_fnum', 0);
  end
  tvars.save();


  fname_s = fileutils.fname_relative(fname,'log');
  if (1)
    fid=fopen(fname,'r');
    [m cnt] = fscanf(fid, '%g');
    fclose(fid);
    m = m(:);
    %  hdr_pd_samps = 3700;
  end
  fname_s = fileutils.fname_relative(fname,'log');

  fsamp_Hz = 122880000;
  m_l = length(m);
  
  t_us = (0:(m_l-1))/fsamp_Hz * 1e6;
  ncplot.init();
  plot(t_us,m,'.');
  xlabel('time (us');
  ylabel('amplitude (V)');
  ncplot.title({'red pitaya data'; fname_s});
end
