function [mvars m aug] = load_measfile(fname)
  import nc.*
  
  if (strcmp(fileutils.ext(fname),'.raw'))
    s = fileutils.nopath(fname);
    s(1)='r';
    s=fileutils.replext(s,'.txt');
    fname=[fileutils.path(fname) '\' s];
  end
  
  fprintf('reading %s\n', fname);
  mvars = nc.vars_class(fname);
  other_file = mvars.get('data_in_other_file',0);
  if (other_file==2)
    s = fileutils.nopath(fname);
    s(1)='d';
    s=fileutils.replext(s,'.raw');
    fname2=[fileutils.path(fname) '\' s];
    fprintf(' %s\n', fname2);
    fid=fopen(fname2,'r','l','US-ASCII');
    if (fid<0)
      fprintf('ERR: cant open %s\n', fname2);
    end
    [m cnt] = fread(fid, inf, 'int16');
    % class(m) is double
    fclose(fid);
    
    aug = m<0;
    for k=1:cnt
      aug(k)=(m(k)<0); % bitget fails on negative numbers
      if (aug(k))
        m(k)= 2^15+m(k);
      end
      m(k)=bitset(m(k),15,0);
      if (bitget(m(k),14))
        m(k)=m(k)-2^14;
      end
    end
    aug = reshape(aug,8,[]);

    m = reshape(m, 2, cnt/2).';
    
  end
  if (isempty(m))
    fprintf('\nERR: file contains no data\n');
  end
  
end

