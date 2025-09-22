function archive(arg)
  import nc.*
  mname='archive.m';

  uio.print_wrap('\narchive\n\nThis program allows you to set an annotation for a data file, then it can copy it to the archive, which is backed up (and released to other team members) by git.  You dont want to do this with most data files');

  
  %  lfsr0 = lfsr_class(hex2dec('25'), hex2dec('0a')); % cp 100101  rst_st  001010
  %  lfsr0.gen(16)

  opt_show=1;
  h_JpHz = 6.62607e-34;
  wl_m = 1544.53e-9;
  c_mps= 299792458;

  opt_fnum=-1;
  if (nargin>0)
    [v n]=sscanf(arg,'%d');
    if (n==1)
      opt_fnum = v;
    end
  end

  tvars = nc.vars_class('tvars.txt');
 
  fname='';
  dflt_fname_var = 'fname';


  if (opt_fnum>=0) 
    fn_full = tvars.get(dflt_fname_var,'');
    max_fnum = 0; % tvars.get('max_fnum', 0);
    if (iscell(fn_full))
      str = fn_full{1};
    else
      str = fn_full;
    end
    [pname fname ext] = fileparts(str);
    [n is ie] = fileutils.num_in_fname(fname);
    if (ie>0)
      places = ie-is+1;
      %fmt = ['%s%0' num2str(places) 'd%s'];
      fmt = '%s%d%s';
      fn2 = sprintf(fmt, fname(1:is-1), opt_fnum, fname(ie+1:end));
      fname = fullfile(pname, [fn2 ext]);
      if (~exist(fname,'file'))
        fprintf('WARN: requested does not exist:\n');
        fprintf('   %s\n', fname);
        fname='';
      else
        tvars.set(dflt_fname_var, fname);
      end
    end
  end
  
  
  if (isempty(fname))  
    fname = tvars.ask_fname('data file', dflt_fname_var);
  end
  tvars.save();

  



  [mvars m aug] = load_measfile(fname);
  if (isempty(m))
    fprintf('ERR: there is no data in this file\n');
    return;
  end
  fname = mvars.name;
  fname_s = fileutils.fname_relative(fname,'log');
  alice_txing = mvars.get('alice_txing',0);


  use_lfsr = mvars.get('use_lfsr',1);
  num_itr  = mvars.get('num_itr',1);
    

  if (~alice_txing)
    fprintf('Note: alice was not txing in this file\n');
  end
  tvars.save();  



  


  
  tx_same_hdrs = 1;
  fprintf('rx same hdrs %d\n', tx_same_hdrs);
  
  tx_0 = mvars.get('tx_0',0);
  if (tx_0)
    do_eye=1;
  end
  
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('frame_pd_samps', 0); % deprecated
  end
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('probe_pd_samps', 2464); % deprecated
  end

  tst_sync = mvars.get('tst_sync', 0);    
  is_alice = mvars.get('is_alice', 0);    
  frame_qty = mvars.get('frame_qty', 0);
  if (~frame_qty)    
    frame_qty = mvars.get('probe_qty', 0); % deprecated
    if (~frame_qty)    
      frame_qty = mvars.get('frame_qty', 0); % deprecated
    end
  end
  if (tst_sync)
    frame_qty = frame_qty*2;
  end
  
  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  if (~hdr_len_bits)
    hdr_len_bits = mvars.get('probe_len_bits', 256); % deprecated
  end
  
  osamp = mvars.get('osamp', 4);
  cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
  cipher_m = mvars.get('cipher_m',0); % cipher uses m-psk
  
  hdr_len_asamps = hdr_len_bits * osamp;


    
  asamp_Hz = mvars.get('asamp_Hz', 0);
  if (asamp_Hz==0)
    asamp_Hz = mvars.get('fsamp_Hz', 1.233333333e9);
  end

  tx_hdr_twopi = mvars.get('tx_hdr_twopi',0);
  host = mvars.get('host','');
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  m11=mvars.get('m11',1);
  m12=mvars.get('m12',0);
  already_balanced = ((abs(m11-1)>.001)||(abs(m12)>.001));

  if (alice_txing)  
    qsdc_data_pos_asamps = mvars.get('qsdc_data_pos_asamps',0);
    qsdc_data_len_asamps = mvars.get('qsdc_data_len_asamps',0);
    qsdc_code_len_cbits = mvars.get('qsdc_code_len_cbits',10);
    qsdc_data_is_qpsk = mvars.get('qsdc_data_is_qpsk',0);
    qsdc_symbol_len_asamps = mvars.get('qsdc_symbol_len_asamps',4);
    qsdc_bit_dur_syms = mvars.get('qsdc_bit_dur_syms',10);
    fprintf('QSDC: data_pos_asamps   %d\n', qsdc_data_pos_asamps); 
    fprintf('      data_len_asamps   %d (per frame)\n', qsdc_data_len_asamps); 
    fprintf('      code_len_cbits    %d (per data bit)\n', qsdc_code_len_cbits);
    fprintf('      symbol_len_asamps %d\n', qsdc_symbol_len_asamps); 
    fprintf('      symbols per bit   %d\n', qsdc_bit_dur_syms);
    fprintf('      is_qpsdk          %d\n', qsdc_data_is_qpsk);
  end    

  mean_pwr_dBm = mvars.get('mean_pwr_dBm', []);
  fprintf('mean_pwr_dBm %.2f (signal monitor power)\n', mean_pwr_dBm);

  annotation = mvars.get('annotation','');
  if (~isempty(annotation))
    fprintf('\nCURRENT ANNOTATION:\n\n');
    fprintf('%s\n\n', annotation);
    if (uio.ask_yn('change annotation',-1))
      annotation = uio.ask('enter anntotation','');
      mvars.set('annotation', annotation);
      mvars.save();
      fprintf('\nwrote:\n  %s\n', fname);
    end
  else
    annotation = uio.ask('enter anntotation','');
    mvars.set('annotation', annotation);
    mvars.save();
      fprintf('\nwrote:\n  %s\n', fname);
  end
  tvars.save();
  if (uio.ask_yn('copy to archive'))
    datedir = fileutils.nopath(fileutils.path(fname));
    dstdir = fullfile('archive', datedir);
    fileutils.ensure_dir(dstdir);
    fname_dst  = fullfile('archive', datedir, fileutils.nopath(fname));

    s = fileutils.nopath(fname);
    s(1)='d';
    s=fileutils.replext(s,'.raw');
    fname2=[fileutils.path(fname) '\' s];
    fname2_dst = fullfile('archive', datedir, fileutils.nopath(fname2));

    r_copy(fname, fname_dst);
    r_copy(fname2, fname2_dst);
    fprintf('\nwrote:\n  %s\n  %s\n', fname_dst, fname2_dst);

    [f_path f_base f_ext]=fileparts(fname);
    fname_out=fullfile(f_path,[f_base '_out' f_ext]);
    fname_out_dst = fullfile('archive', datedir, fileutils.nopath(fname_out));
    if (exist(fname_out))
      r_copy(fname_out, fname_out_dst);
      fprintf('  %s\n', fname_out_dst);
    end
    
    fprintf('\n');
    
  end
   
end



function r_copy(s, d)
  if (~exist(s,'file'))
    fprintf('ERR: cant copy %s\n', s);
    fprintf('            to %s\n', d);
    fprintf('     because it does not exist\n');
    pause;
  else
    [stat, msg, msgid] = copyfile(s,d);
    if (~stat)
      fprintf('ERR: r_copy failed to copy %s\n', s);
      fprintf('     to %s\n', d);
      fprintf('     even though the source exists!\n');
      fprintf('     Matlab supplies the following error message:\n');
      fprintf('        %s\n', msg);
      fprintf('hit enter\n');
      pause;
    end
  end
end
