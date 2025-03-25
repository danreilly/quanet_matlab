function plog
  import nc.*
  tvars = nc.vars_class('tvars.txt');
  fname='';
  
  dflt_fname_var = 'fname';
  fn_full = tvars.get(dflt_fname_var,'');
  if (iscell(fn_full))
    str = fn_full{1};
  else
    str = fn_full;
  end
  if (isempty(fname))  
    fname = tvars.ask_fname('data file', 'fname');
  end
  pname = fileparts(fname);

  pname_pre = fileparts(str);
  tvars.save();

  fname_s = fileutils.fname_relative(fname,'log');
  [f errmsg] = fopen(fname, 'r');
  if (f<0)
      if (opt.dbg_lvl)
        fprintf('cant open file\n');
        fprintf('     %s\n', fname);
      end
      return;
  end

  % Build the "amps" matrix.
  k=0;
  data=zeros(1,3);
  idxs=[];
  cnts=[]
  amps=zeros(10,5);
  amps_w =0; % width of amps matrix
  while(1)
    li = fgetl(f);
    if (~ischar(li))
      break;
    end
    time_s = ser_class.parse_keyword_val(li, 'time', []);
    if (isempty(time_s))
      break;
    end
    k=k+1;
    data(k,1)=time_s;
    li = fgetl(f); % skip
    while (1) 
      li = fgetl(f); % skip
      pk_a = ser_class.parse_keyword_val(li, 'peak of', []);
      if (isempty(pk_a))
        break;
      end
      if (pk_a > 5)
        pk_idx = ser_class.parse_keyword_val(li, 'idx', []);
        ii = find(idxs == pk_idx, 1);
        if (isempty(ii))
            % fprintf('%.2f at %d\n', pk_a, pk_idx);
          amps_w = amps_w + 1;
          ii = amps_w;
          idxs(ii)=pk_idx;
          cnts(ii)=1;
          amps(k,ii)=pk_a;
        else
          cnts(ii)=cnts(ii)+1;
          amps(k,ii)=pk_a;
        end
        pk_ns   = ser_class.parse_keyword_val(li, '=', []);
      end
    end
    nf_mean = ser_class.parse_keyword_val(li, 'floor', 0);
    nf_std = ser_class.parse_keyword_val(li, 'std', 0);
    data(k,2) = nf_mean;
    data(k,3) = nf_std;
  end
  fclose(f);
  t_max = k;

  [co,ch,cq] = ncplot.colors;

  fsamp_Hz=1.23333e9;

  t_mid = round(k/2);
  
  ncplot.init();
  

  ci=1; % color index

  for c=1:amps_w      
    tr=find(amps(:,c)>1); % a set of rows
    if (cnts(c)>4)
      ci=ci+1;
      col = co(ci,:);
      plot(data(tr,1), amps(tr,c), '-', 'Color', ch(ci,:));
    else
      col = 'black';
      plot(data(tr,1), amps(tr,c), '.', 'Color', 'black');
    end
    

    xi = tr(max(1,round(length(tr)/2))); % pick a row
    
    t_us = idxs(c) / fsamp_Hz *1e6; % reflection time
    text(data(xi,1), amps(xi, c)+4, ...
         sprintf('%.3f us', t_us), ...
         'Color', col);
    ylim([0 60]);

    drawnow();
    uio.pause('sdas');
  end
  
  plot(data(:,1),data(:,2),'Color','black');
  mx=max(amps(:));
  mx
  xlim([data(1,1), data(end,1)]);
  %  ylim([0 mx*1.2]);
  xlabel('time (s)');
  ylabel('amplitude (ADC)');

  ncplot.txt('1/17/2025 1:19pm');
  ncplot.txt('voa 1 24.2');
  ncplot.txt('voa 2 6.3');
  
  
  title({fname_s,'log of reflections'});
end    
