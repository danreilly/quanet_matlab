% run this from epa directory as:
% nc.compile
%
function compile
  import nc.*
  fprintf('\nnc.compile.m\n');
  if (~exist('+nc'))
     fprintf('ERR: must be run in dir above +nc\n');
  end

  cvars=vars_class('+nc\compile_vars.txt');
  fprintf('prior compilation:\n');
  fprintf('   host %s\n', cvars.get('host'));
  fprintf('   date %s\n', cvars.get('date'));
  fprintf('   compiler %s\n', cvars.get('compiler'));


  ccfg=mex.getCompilerConfigurations('C');
  fprintf('next will use:\n   compiler %s\n', ccfg.Name);
  if (~strcmp(ccfg.Language,'C'))
    fprintf('WARN: This is a %s compiler.\n', ccfg.Language);
  end
  if (~uio.ask_yn('proceed?'))
    return;
  end

  fprintf('\n  NOTE: If you get "Error: link of "xxx.mexw64" failed"\n');
  fprintf('        sometimes thats because it is running on another pc.\n');

  fprintf('compiling mex code for sershare client routines\n');
  mex +nc/sershare_mex.c +nc/sershare.c wsock32.lib Ws2_32.lib -outdir +nc;

  fprintf('compiling mex code for local_port_inq\n');
  mex +nc/local_port_inq_mex.c -outdir +nc;

  if (exist('+nc/ser_mex.mexw64')==3)
    nc.ser_mex(0); % close anything that was open
  end
  fprintf('compiling mex code for ser_mex\n');
  mex +nc/ser_mex.c +nc/ser.c -outdir +nc;

  cvars.set('compiler', ccfg.Name);
  cvars.set_context();
  cvars.save;

end
