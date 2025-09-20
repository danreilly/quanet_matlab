function genhex(arg)
  import nc.*
  mname='p.m';

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
    fname = tvars.ask_fname('measurement file', dflt_fname_var);
  end
  tvars.save();


  [mvars m aug] = load_measfile(fname);
  if (isempty(m))
    return;
  end
  fname = mvars.name;
  fname_s = fileutils.fname_relative(fname,'log');
  aug0=reshape(repmat(aug(1,:),4,1),[],1);
  aug1=reshape(repmat(aug(2,:),4,1),[],1);
  aug2=reshape(repmat(aug(3,:),4,1),[],1);
  aug3=reshape(repmat(aug(4,:),4,1),[],1);
  aug4=reshape(repmat(aug(5,:),4,1),[],1);
  aug5=reshape(repmat(aug(6,:),4,1),[],1);
  aug6=reshape(repmat(aug(7,:),4,1),[],1);
  aug7=reshape(repmat(aug(8,:),4,1),[],1);
  


  
  use_lfsr = mvars.get('use_lfsr',1);
  num_itr  = mvars.get('num_itr',1);
  
  tx_same_hdrs = mvars.get('rx_same_hdrs',[]);
  if (isempty(tx_same_hdrs))
    tx_same_hdrs = mvars.get('tx_same_hdrs',0);
  end
  % fprintf('rx same hdrs %d\n', tx_same_hdrs);
  
  tx_0 = mvars.get('tx_0',0);
  
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('frame_pd_samps', 0); % deprecated
  end
  if (~frame_pd_asamps)
    frame_pd_asamps = mvars.get('probe_pd_samps', 2464); % deprecated
  end

  tst_sync = mvars.get('tst_sync', 0);
  tst_sync=0;
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

  asamp_Hz = mvars.get('asamp_Hz', 0);
  if (asamp_Hz==0)
    asamp_Hz = mvars.get('fsamp_Hz', 1.233333333e9);
  end
  
  osamp = mvars.get('osamp', 4);
  cipher_symlen_asamps = mvars.get('cipher_sylem_asamps', osamp);
  cipher_m = mvars.get('cipher_m',0); % cipher uses m-psk
  
  hdr_len_asamps = hdr_len_bits * osamp;
  hdr_len_s = hdr_len_asamps/asamp_Hz;


  tx_hdr_twopi = mvars.get('tx_hdr_twopi',0);
  host = mvars.get('host','');
  lfsr_rst_st = mvars.get('lfsr_rst_st', '50f');
  annotation=mvars.get('annotation','');

  

  % IQ SCATTERPLOT
  ii = m(:,1);
  qq = m(:,2);
  ncplot.init();
  [co,ch,coq]=ncplot.colors();
  ncplot.subplot(1,2);
  ncplot.subplot();
  iqopt.markersize=1;

  ncplot.iq(ii, qq, iqopt);
  ncplot.title({fname_s; 'raw IQ scatterplot'});
  p = ii.^2 + qq.^2;
  n_rms = sqrt(mean(ii.^2 + qq.^2));
  i_std = std(ii);
  q_std = std(qq);
  if (~isempty(host))
    ncplot.txt(sprintf('%s', host));
  end
  if (1)
    if (~isempty(annotation))
      ncplot.txt(annotation);
    end
    ncplot.txt(sprintf('num samples %d', length(ii)));
    ncplot.txt(sprintf('mean I %.2f  std %.3f', mean(ii), i_std));
    ncplot.txt(sprintf('mean Q %.2f  std %.3f', mean(qq), q_std));
    % ncplot.txt(sprintf('filter %s', filt_desc));
    ncplot.txt(sprintf('pwr std %.1f ', std(p)));
    ncplot.txt(sprintf('E radius %.1f ADCrms', n_rms));

  end

  tvars.save();


  fprintf('  annotation %s\n', annotation);
  if (uio.ask_yn('gen hex for sim',-1))
    s = fileutils.nopath(fname);
    s=fileutils.replext(s,'.hex');
    fname3=[fileutils.path(fname) '\' s];
    fprintf(' %s\n', fname3);
    fid=fopen(fname3,'w','l','US-ASCII');
    if (fid<0)
      fprintf('ERR: cant open %s\n', fname3);
    end
    m=reshape(m.',[],1);
    for k=1:length(m)
      v = m(k)+(m(k)<0)*(2^16);
      %      if (k<=10)
      %        fprintf('%d = %04x\n', m(k), v);
      %      end
      %      fprintf(fid, '%04x', util.ifelse(m(k)>=0, m(k), 2^16+m(k)));
      fprintf(fid, '%04x', v);
    end
    fclose(fid);
  end
    
  tvars.save();  






end
