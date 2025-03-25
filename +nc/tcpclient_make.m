% run this from epa directory as:
% nc.compile
%
function tcpclient_make
  fprintf('\ntcpclient_make.m\nCcompiling mex code for tcpclient routines\n');
  ccfg=mex.getCompilerConfigurations('C');
  fprintf('  using %s compiler: %s\n', ccfg.Language, ccfg.Name);
  fprintf('  NOTE: If you get "Error: link of "xxx.mexw64" failed"\n');
  fprintf('        sometimes thats because it is running on another pc.\n');
  mex +nc/tcpclient_mex.c +nc/tcpclient.c wsock32.lib Ws2_32.lib -outdir +nc;
end
