classdef polaview_class < handle

  properties (Constant=true)

  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug cpds reads
    opt
    settings
    state
%      temp_fname
%      meas_fname
  end

  methods (Static=true)

    %static
    function s2=esc_backslash(s)
    % replace each underscore with backslash-underscore
    % so it appears properly in a plot title.
      s2=s;
      k=1;
      for j=1:length(s)
        if (s(j)=='\')
          s2(k)='\';
          s2(k+1)=s(j);
          k=k+2;
        else
          s2(k)=s(j);
          k=k+1;
        end
      end
    end
    
    % static
    function m=read_mark_file(fname)
    % returns m: nxm matrix. columns are S0,S1,S2,S3,DOP
      m=[];             
      f = fopen(fname, 'r');
      if (f>0)
        fprintf('reading %s\n', fname);
        [a ct]=fscanf(f, '%[^\n]\n',1);
	if (ct~=1)
	  fprintf('ERR: parsed past eof of %s\n', fname);
	  return;
	end
        n = fscanf(f, '%g', inf);
        l = floor(length(n)/6)*6;
        m = reshape(n(1:l), 6, []).';
        m = m(:,2:end);
        fclose(f);
        
      end
    end

  end

  methods
    % CONSTRUCTOR
    function me = polaview_class(opt)
      import nc.*
      me.opt = opt;
      me.state.ppro_use=opt.ppro_use;
      me.state.ppro_gave_help=0;
      me.state.state=0;
      me.state.temp_n=-1;

      ppro_warn=1;
      polarimeter_warn=1;
      [err outp]=dos('tasklist');
      if (~err)
        % Sometimes it is powerpro.exe, sometimes Powerpro.exe
        ppro_warn = isempty(regexpi(outp,'(^|\n)powerpro.exe'));
        polarimeter_warn = isempty(regexpi(outp,'(^|\n)POD-101D.exe'));
      end
      
      if (polarimeter_warn)
        uio.print_wrap('  Make sure PolaView ver 2.5 is in SPHERE mode. Do not click the Run button.  Also make sure there is no pending ALT key for the window. That is, make sure none of the menu labels have underscored letters.  Do not transition away from that application using ALT-TAB.');
        uio.pause();
      end

      if (opt.ppro_use)
        if (ppro_warn)
          uio.pause('\n  WARN: Powerpro might not be running.  Make sure it is.');
        end

        ppro = 'c:\Program Files\PowerPro\powerpro'; % default location for XP
        if (~exist([ppro '.exe']))
          ppro = 'c:\Program Files (x86)\PowerPro\powerpro'; % default location windows7
          if (~exist([ppro '.exe']))
	    fprintf('  PowerPro is not in a default location.\n');
            [fname, pname, fidx] = uigetfile('*.*', 'Where is PowerPro.exe ?', ...
					     'C:', 'MultiSelect', 'off');
            idx=strfind(fname,'.exe');
            if (length(idx)~=1)
              me.state.ppro_use=0;
	      fprintf('  ERR: you did not specify any executable\n');
            else
              ppro=[pname fname(1:idx(1)-1)];
              me.state.ppro_use = (fidx==1);
            end
          end
        end
      end


      if (me.state.ppro_use)
        pproq = ['"' ppro '"']; % double-quoted name of power pro executable
        me.state.pproq = pproq;

        %   cmd=[pproq ' Script.path("' pwd '")'];
        %   [err outp] = dos(esc_backslash(cmd));

        cmd=[pproq ' Script.path("' regexprep(pwd,'\\','/') '")'];
        err = dos(cmd);
        if (err)
          fprintf('ERR: problem setting powerpro path\n');
          fprintf('     you will have to do things manually\n');
          me.state.ppro_use=0;
        end

        if (1)
          cmd=[pproq ' Win.debug(scriptpath)'];
          [err outp] = dos(me.esc_backslash(cmd));
          if (err)
            fprintf('ERR: problem setting powerpro path\n');
            fprintf('     you will have to do things manually\n');
            me.state.ppro_use=0;
          end
        end

      end
      
      if (me.state.ppro_use)
        if(exist('C:\Temp\ppro_done.txt'))
          delete('C:\Temp\ppro_done.txt');
        end
        err = me.run_ppro('.polaview_check');
        if (err)
          me.state.ppro_use = 0;
        end
      end
       
    end

    % DESTRUCTOR
    function delete(me)
      import nc.*
      if (me.state.state==1)
        fprintf('WARN: polaview is still "marking"\n');
      elseif (me.state.state==2)
        fprintf('WARN: polaview is still "recording"\n');
      end
    end


    function err = mark_start(me, fname, wl_nm, num_pts)
    % desc: start continuous recording into a mark file
      import nc.*
      if (me.state.state)
        error('mark_start called but already measuring');
      end
      me.state.meas_fname = fname;
      me.state.meas_f = fopen(me.state.meas_fname, 'w');
      if (me.state.meas_f<0)
        fprintf('ERR: cannot write to %s\n', fname);
        err = 1;
        return;
      end
      fprintf(me.state.meas_f,'Num      S0       S1        S2       S3       DOP\r\n');
      if (nargin>3)
        me.state.pts_left = num_pts;
      else
        me.state.pts_left = Inf;
      end

      me.state.num_marks = 0;
      % PolaView takes only ints!
      wl_nm = min(max(round(wl_nm),1480),1620);
      err=0;
      if (me.state.ppro_use)
        err = me.run_ppro(['.polaview_mark_start(' ...
			     num2str(round(wl_nm)) ')']);
        pause(0.2);
      end
      if (~err)
        me.state.state=1;
      end
    end


    function err = mark(me)
    % desc: samples one polarization state
      import nc.*
      if (me.state.state~=1)
        error('mark() called before mark_start(). Not marking!');
      end
      if (me.state.ppro_use)
        err = me.run_ppro_nocheck(['.polaview_mark()']);
        if (err)
          uio.pause('powerpro could not run.  I will crash.');
          error('crash');
        end
        me.state.num_marks = me.state.num_marks+1;
        if (me.state.num_marks == 99)
          me.move_temp_to_meas();
        end
      else
        err = 0;
        uio.pause('Click the Polaview "Insert" button');
      end
    end
    
    
    function err = mark_stop(me)
    % desc: saves all marked states in a file.
      import nc.*
      if (me.state.state~=1)
        error('mark_stop called but not marking!');
      end
      if (me.state.num_marks)
        me.move_temp_to_meas();
      end
      me.state.state=0;
      
      if (me.state.ppro_use)
        err = me.run_ppro('.polaview_mark_stop()');
      else
        err = 0;
        uio.pause('Click the Polaview "Stop" button');
      end

      fclose(me.state.meas_f);
      fprintf('wrote %s\n', me.state.meas_fname);
    end


    function temp_fname = pick_temp_fname(me)
    % picks a temporary filename guaranteed to not exist      
      import nc.*
      % PolaDetect crashes when it tries to overwrite files
      % or when filename is too long, so now we just write to temp files
      n = 0; % tvars.get('polaview_fnum',0);

      [temp_fname n] = fileutils.uniquename('C:\Temp', sprintf('polaview%01d.txt', mod(me.state.temp_n+1,10)));
      me.state.temp_n=n;
      % fprintf('chose temp fname %d\n', n);
      
      % tvars.set('polaview_fnum',mod(n+1,10));
      % tvars.save();
      temp_fname = fullfile('C:\temp', temp_fname);
      me.state.temp_fname = temp_fname;
      if (exist(temp_fname,'file'))
        delete(temp_fname);
        if (exist(temp_fname,'file'))
          fprintf('\nFAILURE: file exists, but cannot delete %s\n', temp_fname);
          uio.pause;
        end
      end
    end

    function move_temp_to_meas(me)
      import nc.*
      ok=0;
      f1=0;
%      fprintf('move_temp_to_meas(me): %d marks\n', me.state.num_marks);

      me.pick_temp_fname();
      if (me.state.ppro_use)
        err = me.run_ppro(['.polaview_mark_save("' ...
                          me.esc_backslash(me.state.temp_fname) '")']);
      else
        err = 0;
        uio.pause(sprintf('Click the Polaview "Save" button, then enter %s',me.state.temp_fname));
      end
      
      % sometimes powerpro returns so fast the file isnt there yet, so try mult times
      for k=1:40
        if (exist(me.state.temp_fname,'file'))
          f1 = fopen(me.state.temp_fname, 'r');
          if (f1>0)
            break;
          end
        end
        pause(0.25);
      end
      fl=1;
      if (f1>0)
        fprintf('appending from %s\n', me.state.temp_fname);
        [a ct]=fscanf(f1, '%[^\n]\n',1);
	if (ct~=1)
	  fprintf('ERR: %s is empty!\n', me.state.temp_fname);
          error('bug')
        else
          while(1)
            [a ct]=fscanf(f1, '%[^\n]\n',1);
	    if (ct~=1)
	      break;
	    end
            if (fl)
              [vs, vct]=sscanf(a,'%g');
              if ((vct>3)&& ~any(vs(1:4)))
                fprintf('WIERD: got all zerso\n');
                a
              end
              fl=0;
            end
            fprintf(me.state.meas_f, '%s\n', a);
                  fl=0;

          end
          ok=1;
        end
        fclose(f1);
      else
        fprintf('ERR: could not open %s\n', me.state.temp_fname);
      end
      if (~ok)
        fprintf('ERR: failed to append %s\n', me.state.temp_fname);
        fprintf('     to %s\n',fileutils.nopath(me.state.meas_fname));
%        fprintf('     Matlab supplies the following error message:\n');
%        fprintf('        %s\n', msg);
        uio.pause();
      else
        % delete(me.state.temp_fname);
      end
      me.state.pts_left = me.state.pts_left - me.state.num_marks;
      me.state.num_marks = 0;
    end

    function record_start(me, fname, samp_rate_Hz, wl_nm)
    % desc: start continuous recording into a dsop file
      import nc.*
      if (me.state.state)
        error('record_start called but already measuring');
      end
      me.state.meas_fname = fname;

      wl_nm = min(max(round(wl_nm),1480),1620); % PolaDetect takes only ints!
      e=0;

      if (me.state.ppro_use)
        e = me.run_ppro(['.polaview_record_start("' me.esc_backslash(temp_fname) '", "' ...
					         num2str(samp_rate_Hz/1000) '", ' ...
					         num2str(round(wl_nm)) ')']);
        if (~e)
	  for t=1:10*4
            if (exist(temp_fname,'file'))
              break;
            end
            pause(0.25);
	  end
	  if (~me.state.ppro_gave_help)
            if (~exist(temp_fname,'file'))
              fprintf('WARN: ppro does not seem to be cooperating,\n');
              fprintf('      because the file is not being written to.\n');
              fprintf('      Sometimes you have to sort of "prime the pump" by\n');
              fprintf('      breaking this, and running ppro_test.\n\n');
              fprintf('  hit enter >');
              pause;
            end
            me.state.ppro_gave_help=1;
	  end

          fprintf('\nPolaview should write %s\n', temp_fname); % [f_name f_ext]);
          fprintf('waiting for file to grow ');

          t1_s = tic;
          s1=fileutils.get_filesize_bytes(temp_fname);
          s2=s1;
          for t=1:100
            s2=fileutils.get_filesize_bytes(temp_fname);
            if (s2>s1)
              startup_s = toc(t1_s);
              fprintf(' ok\n');
              break;
            end
            fprintf('.');
            pause(0.25);
          end
          e = (s2==s1);
          pause(0.5); 
        end
        if (e)
          fprintf('\nERR: General Photonics PolaDetect GUI is not cooperating\n');
          fprintf('     as a work-around, do it manually\n');
          me.state.ppro_use=0;
	  uio.pause;
	  startup_s = step_s;
        end
      end
      if (e || ~me.state.ppro_use)
        fprintf('\nSwitch to the General Photonics PolaDetect GUI\n');
        fprintf('  Select the Measurement->Oscillioscope menu item.\n');
        fprintf('  Then select the Option->Waveleng menu item.\n');
        fprintf('     Enter %g\n', wl_nm);
        uio.pause();
        fprintf('\n\n');
        fprintf('  Select the Option->Variation Tracking menu item.\n');
        fprintf('  Specify that it sample at 0.61ksps for 1 hr\n');
        idx=findstr(dsop_fname,'\');
        idx=idx(end);
        fprintf('  Specify a .dsop path of:\n');
        fprintf('     %s\n', dsop_fname(1:idx));
        fprintf('  and a file name of:\n');
        fprintf('     %s\n', dsop_fname(idx+1:end));
        fprintf('  Start the dsop tracking.\n');
        uio.pause();
        fprintf('\n\n');
      end
      me.state.state=2;
    end % function record_start
    


    function record_stop(me)
      import nc.*
      if (me.state.state~=2)
        error('record_stop called but not recording!');
      end
      e=0;
      if (me.state.ppro_use)
	e = me.run_ppro(['.polaview_record_stop("")']);
	if (e)
	  fprintf('\nERR: General Photonics PolaDetect GUI is not cooperating\n');
	  fprintf('     problem stopping dsop log\n');
	  fprintf('     as a work-around, do it manually\n');
	end
      end
      if (e || ~me.state.ppro_use)
	fprintf('\nSwitch to the General Photonics PolaDetect window\n');
	fprintf('click the "Stop" button, then hit enter > ');
	pause;
	fprintf('\n');
      end
      me.move_temp_to_meas();
      me.state.state=0;
    end
    
    function err = run_ppro_nocheck(me, ppro_func_call)
      cmd = [me.state.pproq ' ' ppro_func_call];
      err = dos(cmd, '-echo');
      if (err)
        fprintf('ERR: problem launching powerpro');
        return;
      end
    end

    
    function err = run_ppro(me, ppro_func_call)
    % attemps to run specified power-pro function.  The function must be written
    % such that it sets the error flag file if it fails.
      cant=0;
      errf='C:\Temp\ppro_status.txt'; % error flag file
      if (exist(errf, 'file'))
        delete(errf);
        cant=exist(errf,'file');
        if (cant)
          error(sprintf('ERR: %s exists but cant delete it!\n', errf));
        end
      end

      % PROBLEM: sometimes this returns before ppro script is done!!!
      cmd = [me.state.pproq ' ' ppro_func_call];
      % fprintf('  DBG: polaview_class.run_ppro\n    %s\n', ppro_func_call);
      err = dos(cmd, '-echo');
      if (err)
        fprintf('ERR: problem launching powerpro');
        return;
      end

      while(~exist('C:\Temp\ppro_status.txt'))
        pause(3);
        fprintf('waiting for ppro to finish\n');
      end
      f = fopen('C:\Temp\ppro_status.txt');
      [ok ct]=fscanf(f,'%g');
      if (ct~=1)
	error('ppro posted improper rsp in ppro_done.txt');
      end
      fclose(f);
      if (~ok)
        fprintf('ERR: PowerPro reported a failure\n');
        err=1;
        return;
      end

      err=0;
    end

  end

end
