function show(meas_fnames)
  mname='qnet_show.m';	 
  import nc.*;

  ini=vars_class('tvars.txt');

  if (nargin<1)
      '<1'
    meas_fnames = ini.ask_fname('measurement file(s)', ...
			        'meas_fname', 1);
    if (~iscell(meas_fnames))
      meas_fnames={meas_fnames};
    end
    pname = fileparts(meas_fnames{1});
    while(1)
      break;
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
  if (isempty(meas_fnames))
    return;
  end
  ini.set('meas_fname', meas_fnames{1});
  ini.save;  

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

  data_hdr = mvars.get('data_hdr');
  data = mvars.get('data');
  if (size(data,1)<4)
    fprintf('ERR: no data\n');
    return;
  end
  beat_dur_us = mvars.get('beat_dur_us');
  step_en   = mvars.get('step_en');
  step_type = mvars.get('step_type');
  step_amt  = mvars.get('step_amt');
  time_us_col  = mvars.datahdr2col(data_hdr, 'time_us');
  beat_kHz_col = mvars.datahdr2col(data_hdr, 'beat_kHz');
  goal_kHz_col = mvars.datahdr2col(data_hdr, 'goal_kHz');
  err_kHz_col = mvars.datahdr2col(data_hdr, 'err_kHz');
  fm_col       = mvars.datahdr2col(data_hdr, 'fm');

  if (time_us_col)
    time_us = util.mod_unwrap(data(1:end, time_us_col),2^16);
    time_us = time_us-time_us(1);
  else
    fprintf('ERR: no time_us column');
    return;
  end
  if (beat_kHz_col)
    beat_kHz = data(:, beat_kHz_col);
  end
  if (goal_kHz_col)
    goal_kHz = data(:, goal_kHz_col);
  end
  if (err_kHz_col)
    err_kHz = data(:, err_kHz_col);
  end
  if (fm_col)
    fm = data(:, fm_col);
  end
  ncplot.init();
  [co, ch, cq] = ncplot.colors();


  if (~step_en)
    desc='drift';
  elseif (step_type=='e')
    desc='feedback starting up';
  elseif (step_type=='f')
    desc='FM step';
  else
    desc='feedback goal step'; 
  end

  
  ncplot.subplot(3,1);

  %  ncplot.subplot();
  %  plot(1:length(time_us),time_us, '.');
  
  ncplot.subplot();
  plot(time_us, beat_kHz/1000, '.','Color',cq(1,:));
  beat_goal_kHz = mvars.get('beat_goal_kHz');
  if (beat_goal_kHz)
    ncplot.txt(sprintf('beat goal %d kHz', beat_goal_kHz));
  end
  ncplot.txt(sprintf('fdbk pd set %d actual %.1f us', beat_dur_us, mean(diff(time_us))));
  xlim([0 time_us(end)]);
  xlabel('time (us)');
  %  ylabel(sprintf('beat offset from %.3fMz (kHz)', beat_kHz(1)/1000));
  ylabel(sprintf('beat (MHz)'));
  ncplot.title([ttl; desc]);

  
  if (goal_kHz_col)
    ncplot.subplot();
    plot(time_us, goal_kHz, '.', 'Color',cq(1,:));
    xlim([0 time_us(end)]);
    xlabel('time (us)');
    ylabel('goal (kHz)');
    ncplot.title([ttl; desc]);
  end
  
  if (err_kHz_col)
    ncplot.subplot();
    plot(time_us, err_kHz, '.', 'Color',cq(1,:));
    mse_kHz = sqrt(mean(err_kHz.^2));
    if (beat_goal_kHz)
      ncplot.txt(sprintf('beat goal %d kHz', beat_goal_kHz));
    end
    ncplot.txt(sprintf('err mse %.f kHz', mse_kHz));
    xlim([0 time_us(end)]);
    xlabel('time (us)');
    ylabel('err (kHz)');
    ncplot.title([ttl; desc]);
  end
  
  if (fm_col)
    ncplot.subplot();
    plot(time_us, fm, '.','Color',cq(1,:));
    if (step_type=='f')
      ncplot.txt(sprintf('FM step %d DAC', step_amt));
    end
    beat_tc_us = mvars.get('beat_tc_us',[]);
    if (~isempty(beat_tc_us) && ...
        ((step_type=='g') || (step_type=='e')))
        ncplot.txt(sprintf('feedback timeconst %d us', ...
                           beat_tc_us));
    end
    xlim([0 time_us(end)]);
    xlabel('time (us)');
    ylabel('FM setting (DAC)');
    ncplot.title([ttl; desc]);
  end
  
end
