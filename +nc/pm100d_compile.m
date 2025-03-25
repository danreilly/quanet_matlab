function pm100d_compile
  import nc.*
  fprintf('\nnc.pm100d_compile.m\n');
  if (~exist('+nc'))
     fprintf('ERR: must be run in dir above +nc\n');
  end

  cvars=vars_class('+nc\pm100d_compile_vars.txt');
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

  fprintf('\n  NOTE: If you get "Error: link of "xxx.mexw64" failed, its possible that file\n');
  fprintf('        is locked from being executed on another pc.\n');
  fprintf('compiling mex code for pm100d routines\n');
  vxipath = getenv('VXIPNPPATH');
  if (isempty(vxipath))
    fprintf('ERR: environment variable VXIPNPPATH not defined\n');
    fprintf('     VISA libraries might not be installed properly on this machine\n');
    nc.uio.pause();
  end
  vxiincpath = [vxipath '/include'];
  vxilibpath = [vxipath '/lib/msc'];

  mex -I"C:\Program Files (x86)\IVI Foundation\Visa\WinNt\include" +nc/pm100d_mex.c +nc/PM100D_Drv.c -L"C:\Program Files (x86)\IVI Foundation\Visa\WinNt\Lib_x64\msc" -L"C:\Program Files (x86)\IVI Foundation\Visa\WinNt\PM100D_Drv" -lPM100D_Drv -lvisa64 -outdir +nc

  %mex('pm100d_mex.c',['COMPFLAGS="-I' vxiincpath '"'])
  %mex pm100d_mex.c -I 
  %-L PM100D_Drv.lib visa32.lib

  cvars.set('compiler', ccfg.Name);
  cvars.set_context();
  cvars.save;

end
