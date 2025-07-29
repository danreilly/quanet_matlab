function qnet_show(meas_fnames)
  mname='qnet_show.m';	 
  import nc.*;

  ini=vars_class('tvars.txt');

  if (nargin<1)
    meas_fnames = ini.ask_fname('measurement file(s)', ...
			       'voa_tst_fname', 1);
    if (~iscell(meas_fnames))
      meas_fnames={meas_fnames};
    end
    pname = fileparts(meas_fnames{1});
    while(1)
      if (~uio.ask_yn('pick more measurement files',0))
        break;
      end
      fnames = uio.ask_fname(pname, 'attenuation measurement file(s)', 1);
      if (isempty(fnames))
        break;
      end;
      if (~iscell(fnames))
        fnames={fnames};
      end
      meas_fnames = [meas_fnames; fnames];
    end
    if (isempty(meas_fnames))
      return;
    end
  end

  ini.save;

  if (~iscell(meas_fnames))
    meas_fnames={meas_fnames};
  end

  err=0;
  for mi=1:length(meas_fnames)
    fname = meas_fnames{mi};
    f_path = fileparts(fname);
    mvars{mi} = vars_class(fname);
    if (mi==1)
      dev_name    =mvars{1}.get('dev_name',0);
      fwver       =mvars{1}.get('fwver',0);
      serialnum   =mvars{1}.get('serialnum','?');
      date_concise=mvars{1}.get('date_concise','?');
      date        =mvars{1}.get('date','?');
      tstnum      =mvars{1}.get('tstnum',0);

      if (0)
      fname=sprintf('%s\\%s_%s_voa_test_%s_%03d.pdf', f_path, dev_name, serialnum, ...
                    date_concise, tstnum);
      report = report_class(fname,'VOA Test Report');
      report.write(sprintf('\\begin{center} \\Large\n'));
      report.write(sprintf('VOA Test Report\\\\for %s serialnum %s\\\\\n', ...
                           dev_name, serialnum));
      report.write(sprintf('\\end{center}\n'));
      report.write(sprintf('engineer %s\\\\\n', mvars{1}.get('engineer','?')));
      report.write(sprintf('date %s\\\\\n', mvars{1}.get('date','?')));
      report.write(sprintf('fwver %s\\\\\n', sprintf(' %d', fwver)));
      report.write(sprintf('measurement files:\\\\\n'));
      for mii=1:length(meas_fnames)
        report.write(sprintf('  \\verb"%s"\\\\\n', meas_fnames{mii}));
      end
      report.write(sprintf('calibration files:\\\\\n'));
      report.write(sprintf('  \\verb"%s"\\\\\n', mvars{1}.get('calfile')));
      end
    else
      if (~strcmp(serialnum, mvars{mi}.get('serialnum')))
        fprintf('ERR: different serial numbers!\n');
        err=1;
      end
      if (~strcmp(fwver, mvars{mi}.get('fwver')))
        fprintf('ERR: different firmware numbers!\n');
        err=1;
      end
    end
  end


  fname=meas_fnames{1};


  %  for mi=1:length(meas_fnames)
  %    tstnum = regexp(fileutils.rootname(meas_fnames{mi}),'\d+');
  %    results_fname = [results_fname sprintf('_%02d', tstnum)];
  %  end
  %  results_fname = [results_fname '.png'];

  mvars = vars_class(fname);
  ttl = {mname};
  ttl=[ttl; fileutils.rootname(fname)];

  data_hdr = mvars.get('data_hdr')
  data = mvars.get('data');
  time_us_col  = mvars.datahdr2col(data_hdr, 'time_us');
  beat_kHz_col = mvars.datahdr2col(data_hdr, 'beat_kHz');
  fm_col       = mvars.datahdr2col(data_hdr, 'fm')

  if (time_us_col)
    time_us = data(:, time_us_col);
  end
  if (beat_kHz_col)
    beat_kHz = data(:, beat_kHz_col);
  end
  if (fm_col)
    fm = data(:, fm_col);
  end
  ncplot.init();
  [co, ch, cq] = ncplot.colors();
  
  ncplot.subplot(2,1);
  
  ncplot.subplot();
  ncplot.plot(time_us, beak_kHz,'.','Color',cq(1,:));
  xlabel('time (us)');
  ylabel('beat (kHz)');
  ncplot.title([ttl; 'drift']);
  
end
