function recon
  import nc.*
  f=fopen('log/d250921/r_63_out.txt');
  n= fscanf(f,'%g');
  fclose(f);
  n=reshape(n,2,[]).';
  size(n)
  n(1:8,:);
  if (0)
    v=n(:,1);
  else  
    v=double(n(:,2)>0);
  end

  
  'metrics of byte'
9*8+1
n(9*8+(1:8),:)
  
v(9*8+(1:8))

  
  idxs=find(n(:,1)>0);
  fprintf('ones mean  %.1f\n',  mean(n(idxs,2)));
  std(n(idxs,2))
  idxs=find(n(:,1)<=0);
  fprintf('zeros mean %.1f\n',  mean(n(idxs,2)));
  std(n(idxs,2))
  

  snt = 2.^(0:7) * reshape(n(:,1),8,[]);
  
  ns = 2.^(0:7) * reshape(v,8,[]);

  k=1;
  ec=0;
  be=0;
  for r=1:32*16
    fprintf(' %d %02x %02x %s\n', ...
            k, snt(k), ns(k), util.ifelse(snt(k)==ns(k),' ','*'));
    be=be+util.bitcnt(bitxor(snt(k),ns(k)));
    ec = ec + (snt(k)~=ns(k));
    k=k+1;
  end
  fprintf('\n');
  fprintf('byte err rate %d / 512 = %g\n', ec, ec/(512));
  fprintf('bit err rate %d / 512 = %g\n', be, be/(512*8));

  
  
if (0)
  k=1;
  for r=1:32
    for c=1:16
      fprintf('%02x', ns(k));
      k=k+1;
    end
  fprintf('\n');
  end
end
end
