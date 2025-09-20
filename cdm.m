function cdm(arg)
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
  fname_s = fileutils.fname_relative(fname,'log');
  aug0=reshape(repmat(aug(1,:),4,1),[],1);
  aug1=reshape(repmat(aug(2,:),4,1),[],1);
  aug2=reshape(repmat(aug(3,:),4,1),[],1);
  aug3=reshape(repmat(aug(4,:),4,1),[],1);
  aug4=reshape(repmat(aug(5,:),4,1),[],1);
  aug5=reshape(repmat(aug(6,:),4,1),[],1);
  
  m=reshape(m.',[],1);

  cdm_en = mvars.get('cdm_en',0);
  if (~cdm_en)
    fprintf('ERR: hdl correlation not used with this data\n');
    return;
  end
  
  
  use_lfsr = mvars.get('use_lfsr',1);
  cdm_num_iter  = mvars.get('cdm_num_iter',0);
  
  tx_same_hdrs = mvars.get('rx_same_hdrs',[]);
  if (isempty(tx_same_hdrs))
    tx_same_hdrs = mvars.get('tx_same_hdrs',0);
  end
  % fprintf('rx same hdrs %d\n', tx_same_hdrs);
  
  tx_0 = mvars.get('tx_0',0);
  host = mvars.get('host','');
  hdr_len_bits = mvars.get('hdr_len_bits', 0);
  osamp = mvars.get('osamp', 4);
  asamp_Hz = mvars.get('asamp_Hz', 0);
  frame_pd_asamps = mvars.get('frame_pd_asamps', 0);

  l = length(m);
  num_corrs = l/frame_pd_asamps;
  m = m / cdm_num_iter;
  
  [mx mi] = max(m);

  ncplot.init();
  [co,ch,coq]=ncplot.colors();
  
  x=(0:frame_pd_asamps-1)/asamp_Hz * 1e6;
  x_units='us';
  for ci=1:num_corrs
    ncplot.init();
    
    rng=(1:frame_pd_asamps)+((ci-1)*frame_pd_asamps);
    plot(x, m(rng), '-','Color', coq(1,:));
    xlim([x(1) x(end)]);
    xlabel(x_units);
    ylim([0 mx]);
    ncplot.title({fname_s; 'CDC correlation'});
    
    ncplot.txt(sprintf('host %s\n', host));
    if (num_corrs>=1)
      ncplot.txt(sprintf('correlation %d\n', ci));
    end
    ncplot.txt(sprintf('frame period %d samps = %s', frame_pd_asamps, ...
                       uio.dur(frame_pd_asamps/asamp_Hz)));
    ncplot.txt(sprintf('probe len %d bits = %s', hdr_len_bits, ...
                       uio.dur(hdr_len_bits*osamp/asamp_Hz)));
    ncplot.txt(sprintf('num iterations %d', cdm_num_iter));
    ncplot.txt(sprintf('max %d at %s', round(mx), uio.dur((mi-1)/asamp_Hz)));
    if (num_corrs==1)
      break;
    end
    uio.pause();
  end
end  
