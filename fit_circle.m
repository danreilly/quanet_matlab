function [ctr radius sweep_deg phs_deg] = fit_circle(ii, qq, fcopt)
  import nc.*
  if (nargin<3)
    fcopt.noplot=0;
  end
  fcopt = util.set_field_if_undef(fcopt, 'no_txt', 0);

  dbg=0;

if (0)
  % eliminate bias
  n=64;
  mx=max(max(abs(ii)),max(abs(qq)));
  sp=(2*mx)/n;
  eye=zeros(n,n);
  for k=1:length(ii)
    xi=util.ifelse(ii(k)>=mx,n,  floor((ii(k)+mx)/sp)+1);
    yi=util.ifelse(qq(k)>=mx,n,n-floor((qq(k)+mx)/sp));
        % fprintf('%d %d\n', xi, yi);
    if ((xi>0)&&(xi<=n)&&(yi>0)&&(yi<=n))
      eye(yi,xi)=1;
    end
  end
end
  


  
  im=mean(ii);
  qm=mean(qq);
  [mn mi] = min((ii-im).^2+(qq-qm).^2);
  if (dbg)
    plot(ii(mi),qq(mi),'.','Color','red');
  end
  im=ii(mi);
  qm=qq(mi);

  v = calc_min_inertia(ii, qq);
  [mx xs] = max(v.' * [ii-ii(mi) qq-qq(mi)].');
  [mn xe] = min(v.' * [ii-ii(mi) qq-qq(mi)].');

  if (dbg)
   plot(ii(xs),qq(xs),'.','Color','blue');
   plot(ii(xe),qq(xe),'.','Color','blue');
  end
  
  [a v] = perp_mid([ii(xs) qq(xs)], [im qm]);
  if (dbg)
   plot(a(1),a(2),'.','Color','magenta');
   line(a(1)+[0 v(1)]*1000,a(2)+[0 v(2)]*1000,'Color','magenta');
  end
  [b w] = perp_mid([ii(xe) qq(xe)], [im qm]); 
  % plot(b(1),b(2),'.','Color','magenta');
  %  line(b(1)+[0 w(1)]*400,b(2)+[0 w(2)]*400,'Color','magenta');

  % a-b = [-v w] p
  p = [-v w]\(a-b);
  c=a+v*p(1); % first estimate of the ctr
          %  plot(c(1),c(2),'.','Color','red');
  % line([a(1) c(1)],[a(2) c(2)],'Color','magenta');
  % line([b(1) c(1)],[b(2) c(2)],'Color','magenta');

  r = sqrt((c(1)-im)^2+(c(2)-qm)^2); % est radius

  for itr=1:10
    ths=(0:256)*2*pi/256;

    % line(r*cos(ths)+c(1), r*sin(ths)+c(2), 'Color','black');
    
    err = (ii-c(1)).^2 + (qq-c(2)).^2 - r^2;
    err_rms = sqrt(mean(err.^2));
    if ((err_rms<1e-6)|| ((itr>1)&&(abs(err_rms-err_rms_prev)<1e-6)))
      break;
    end
    jc1 = -2*(ii-c(1));
    jc2 = -2*(qq-c(2));
    jr  = -2*r*ones(size(ii));
    jac = [jc1 jc2 jr];
    mm = (jac.' * jac);
    rc = rcond(mm);
    if (rc>1e-15)
      p = mm\(jac.'*-err);
      c(1) = c(1)+p(1);
      c(2) = c(2)+p(2);
      r = r + p(3);
    end
    err_rms_prev = err_rms;
  end

  if (~fcopt.noplot)
    line(r*cos(ths)+c(1), r*sin(ths)+c(2), 'Color','green');
  end
  
  % line([c(1) im],[c(2) qm],'Color','black');
  
  m=[im-c(1) qm-c(2)];
  m=m/norm(m);
  

  vs = [ii.'-c(1); qq.'-c(2)];
  for k=1:size(vs,2)
    vs(:,k)=vs(:,k)/norm(vs(:,k));
  end
  m2 = ([0 1;-1 0]*m.').';
  idxs = find(m2*vs > 0);
  [mxv mxi]=min(m*vs(:,idxs));
  xs=idxs(mxi);
  
  idx2s = setdiff(1:length(ii),idxs);
  %  plot(ii(idx2s),qq(idx2s),'.', 'Color','magenta');  
  [mnv mni]=min(m*vs(:,idx2s));
  xe=idx2s(mni);
  
  if (~fcopt.noplot)
    line([c(1) ii(xs)],[c(2) qq(xs)],'Color','blue');
    line([c(1) ii(xe)],[c(2) qq(xe)],'Color','magenta');
  end
  
  vs = [ii(xs)-c(1); qq(xs)-c(2)];
  ve = [ii(xe)-c(1); qq(xe)-c(2)];
  vs = vs/norm(vs);
  ve = ve/norm(ve);
  
  cth = vs.' * ve; % dot prod
  sth = vs.' * [0 1;-1 0]*ve; % cross prod
  sweep_deg = mod(atan2(sth,cth)*180/pi,360);

  vm = geom.rotate(sweep_deg*pi/180/2, vs)*100;

  phs_deg = atan2(vm(2),vm(1))*180/pi;
  
  if (~fcopt.noplot)
    line(c(1)+[0 vm(1)],c(2)+[0 vm(2)],'Color','red');
    if (~fcopt.no_txt)
      ncplot.txt(sprintf(' sweep %.1f deg', sweep_deg));
      ncplot.txt(sprintf(' phase %.1f deg', phs_deg));
      ncplot.txt(sprintf('radius %d ADC units', round(r)));
    end
  end

  ctr = c;
  radius = r;
  
end
    
function [pm v] = perp_mid(p1, p2)
  x=mean([p1(1) p2(1)]);
  y=mean([p1(2) p2(2)]);
  pm = [x; y];
  v = [ p2(1)-p1(1); p2(2)-p1(2)];
  % line(p1(1)+[0 v(1)]*400, p1(2)+[0 v(2)]*400, 'Color','blue');
  v = [ -p2(2)+p1(2);  p2(1)-p1(1)];
  v = v/norm(v);
end
