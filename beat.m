function beat
  mname='beat.m';	 
  import nc.*;

  fprintf('This program measures or test beat freq stability  or phase lock\n');

  
  tvars=vars_class('tvars.txt');
  [dev_port idn]=tvars.ask_port('qna', 'dev_port', 115200);
  if (isempty(dev_port))
    return;
  end

  opt.dbg=0;
  dev=qna_class(dev_port, opt);
  archive_var='qnic_archive'; % archive for eps
  
  if (~dev.isopen())
    fprintf('ERR: cant open device on port %s\n', dev_port);
    return;
  end


  while(1)
    archive = tvars.ask_dir('calibration archive', archive_var);
    [f_path f_name f_ext]=fileparts(archive);
    if (~strcmp(f_name,'archive'));
      fprintf('WARN: %s\n', archive);
      fprintf('      is a non-standard calibration archive name\n');
    end
    if (exist(archive, 'dir'))
      break;
    end
    fprintf('WARN: %s\n', archive);
    fprintf('      doesnt exist\n');
  end
  
  engineer = tvars.ask('engineer name','engineer','');
  tvars.save();

  pname = fullfile(archive, [dev.devinfo.name '_' lower(dev.devinfo.sn)], ['d' datestr(now,'yymmdd')]);
  [fname tstnum] = fileutils.uniquename(pname, 'beatstab_00.txt');
  fnf=fullfile(pname,fname);

  
  dev.get_settings();

  fdbk_en = 0;
  %  fdbk_en = tvars.ask_yn('apply fdbk?', 'fdbk_en');
  

  step_en = tvars.ask_yn('apply step?', 'step_en');
  if (step_en)
    step_type = tvars.ask_choice('step type ', 'efg', 'f');
    units = util.ifelse(step_type=='f','dac','kHz');
    step_amt = tvars.ask(sprintf('step amount (%s)', units), 'step_amt');
  else
    step_type='g';
    step_amt=0;
  end
  dsamp = tvars.ask('downsampling', 'dsamp');

  if (step_type=='e')
    % want to see feedback start so turn off in case it was on.
    dev.set_beat_goal(0);
    tc_us =tvars.ask('feedback timeconstant', 'tc_us', dev.settings.beat_tc_us);
    dev.set_beat_fbdk_tc_us(tc_us);
  end
  
  nsamps = tvars.ask('number of samples to capture', 'nsamps');
  
  tvars.save();
  if (fdbk_en)
    stat=dev.get_status();
    dev.set_beat_goal(stat.beat_kHz);
  end


  %  dev.ser.set_dbg(1);
  [data_hdr data]=dev.cap(nsamps, step_type, step_amt, dsamp);
  %  dev.ser.set_dbg(0);

  
  ovars=vars_class(fnf);
  ovars.set('filetype', 'beat_stab');
  ovars.set_context(dev);
  ovars.set('engineer', engineer);
  ovars.set('tstnum', tstnum);
  ovars.set('dsamp', dsamp);
  ovars.set('nsamps', nsamps);
  ovars.set('step_en', step_en);
  ovars.set('step_type', step_type);
  ovars.set('step_amt', step_amt);
  ovars.set('beat_tc_us', dev.settings.beat_tc_us);
  ovars.set('beat_goal_kHz', dev.settings.beat_goal_kHz);
  %  ovars.set('calfile', calfile);
  %  ovars.set('wavelens_nm', wavelens_nm);
  %  ovars.set('attns_dB',attns_dB);
  ovars.set('data_hdr', data_hdr);
  ovars.set('beat_dur_us', dev.settings.beat_dur_us);
  ovars.set('data', data);
  ovars.save;
  fprintf('wrote %s\n', fnf);

  dev.set_beat_goal(0);

  
  dev=[];

  fprintf('running show.m\n');
  show(fnf);
  
end
