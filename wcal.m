function wcal(arg)
% desc: writes a calibration file to tunlsr device
% usage:
%   wcal
%   wcal fsr   = write most recent FSR calibration
%   wcal iqmap = write most recent iqmap calibration
%
 
  import nc.*


  % This file managed by show.m, which might be running concurrently,
  % and might write to it later.  So we only read it here.
%  vfdir = [getenv('USERPROFILE') '\AppData\Local\nucrypt'];
%  ini_vars = vars_class([vfdir '\tunlsr_show_ini.txt']);
%  fnf = ini_vars.get('mapfile',[]);

  u=uio;
  uio.set_always_use_default(0)

  tvars = vars_class('tvars.txt');

  ask=1;
  varname='';
  fnf = [];
  fnf_deprec='';
  desc='';
  if (nargin>0)
    if (strcmp(arg,'fsr'))
      desc = 'fsr ';
      fnf_deprec = tvars.get('fsr_fname');
      varname = 'fsr_fnames';
    elseif (strcmp(arg,'iqmap')||strcmp(arg,'map'))
      desc = 'iqmap ';
      fnf_deprec = tvars.get('iqmap_fname');
      varname = 'iqmap_fnames';
    elseif (strcmp(arg,'gas')||strcmp(arg,'gaslines'))
      desc = 'gaslines ';
      fnf_deprec = tvars.get('gaslines_fname');
      varname = 'gaslines_fnames';
    else
      fnf = arg;
      ask=0;
    end
  end


  port = tvars.get('tunlsr_port');
  [port idn] = tvars.ask_port({'tunlsr','qna'}, 'stable_laser_dev', 115200);
  if (isempty(port))
    return;
  end

  is_tunlsr=0;
  is_qna=0;
  if (strcmp(idn.name,'qna1'))
    is_qna=1;
    dut=qna1_class(port);
  elseif (strcmp(idn.name,'qna2'))
    is_qna=1;
    dut=qna2_class(port);
  else
    is_tunlsr=1;
    dut=tunlsr_class(port);
  end



  serialnum = dut.devinfo.sn;

  if (ask)
    if (isempty(fnf))
      if (~isempty(varname))
	fnf = tvars.get_in_cell_per_key(varname, serialnum);
%	fnf
      end
    end
    if (isempty(fnf))
      fnf = fnf_deprec;
    end
    if (~isempty(fnf))
      fprintf('most recent %scalibration file is:\n%s\n use it? ', desc, fnf);
      ask = ~uio.ask_yn(1);
    end
    if (ask)
      log_path = fullfile('log', ['d' datestr(now,'yymmdd')]);

      pname = tvars.get('pname', '.');
      [fname, pname, fidx] = uigetfile('*.*', ...
				       ['map*.txt' '... select file'], ...
				       log_path, 'MultiSelect', 'off');
      if (fidx==0)
	return;
      end % nothing selected
      tvars.set('pname', pname);
      fnf = [pname fname];
    end
  end


%  ini_vars.delete;

  vars = vars_class(fnf);
  fname = fileutils.nopath(fnf);

  desc = vars.get('desc','');
  if (~isempty(desc))
    fprintf('desc: %s\n', desc);
  end

  filetype = vars.get('filetype');
  if (~strcmp(filetype,'iqmap') && ~strcmp(filetype,'fsr')&& ~strcmp(filetype,'gaslines'))
    fprintf('ERR: this is a %s file, not a calibration file\n', filetype);
    if (~uio.ask_yn('use anyway',0))
      return;
    end
  end




  if (~isempty(serialnum)&& ~strcmp(serialnum, dut.devinfo.sn))
    fprintf('ERR: this file is for serial number %s not %s\n', serialnum, dut.devinfo.sn);
    if (~uio.ask_yn('use anyway',0))
      return;
    end
  end

  % set adc to phase mapping
  iqmap2 = vars.get('iqmap2',[]);
  iqmap = vars.get('iqmap',[]);
  if (~isempty(iqmap) && ~isempty(iqmap2))
    uio.print_wrap('WARN: this calibration file contains both an iqmap and an iqmap2.  The difference is that iqmap2 uses per-combiner-output offsets and iqmap0 assumes zero offset.  You can choose which one you want to use');
    if (tvars.ask_yn('use iqmap2?','use_iqmap2',0))
      iqmap=[];
    else
      iqmap2=[];
    end
  end
  if (~isempty(iqmap)||~isempty(iqmap2))
    if (~isempty(iqmap2))
      fprintf('writing iqmap2 = [%.2e %.2e %.2e ...]\n', iqmap2(1,1:3));
      dut.set_iqmap2(iqmap2);
      tvars.set('iqmap_fname', fnf);
    else
      if (~isempty(iqmap))
        fprintf('writing iqmap = [%.2e %.2e %.2e ...]\n', iqmap(1,1:3));
        dut.set_iqmap(iqmap);
        tvars.set('iqmap_fname', fnf);
      end
    end
    tvars.set_in_cell_per_key('iqmap_fnames', serialnum, fnf);
  end

  % set free spectral range constants
  fsr = vars.get('fsr',[]);
  if (~isempty(fsr))
    fprintf('writing FSR %.6fGHz and associated constants\n', fsr(1)/1e9);
    dut.cfg_fsr(fsr(1), fsr(2), fsr(3), fsr(4), fsr(5));

    tvars.set_in_cell_per_key('fsr_fnames', serialnum, fnf);

%    tvars.set('fsr_fname', fnf);
  end

  % set gasline constants
  gaslines = vars.get('gaslines',[]);
  lsr_idx  = vars.get('laser_idx',1);
  if (~isempty(gaslines))
    fprintf('writing gaslines for laser %d', lsr_idx);
    fprintf(' %d', gaslines(:,1));
    fprintf('\n');
    fprintf('              slopes ');
    fprintf(' %.3f', gaslines(:,7));
    fprintf('\n');
    dut.set_gaslines(lsr_idx, fname, gaslines);
    tvars.set('gaslines_fname', fnf);
    tvars.set_in_cell_per_key('gaslines_fnames', serialnum, fnf);
  end

  if (is_qna)
    dut.cfg_write();
  end
  
  tvars.save;

  
  fprintf('wrote calibration file\n %s\n', fnf);
  
  dut.delete;

end
