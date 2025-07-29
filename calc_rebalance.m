function res = calc_rebalance(ii, qq)

    i_off = -round(mean(ii));
    q_off = -round(mean(qq));
      
    ii==ii+i_off;
    qq==qq+q_off;
        

    iq=-sum(ii.*qq);
    it=[sum(qq.^2) iq; iq sum(ii.^2)]; % inertia tensor
    [v l] = eig(it);
    [mn mi] = min(diag(l));
    v=v(:,mi); % eigenvector of minimal eigenvalue
    mx=max(abs(ii));
    % line([v(1) -v(1)]*mx,[v(2) -v(2)]*mx,'Color','red');
    th = atan2(v(2),v(1)); % initial estimate
    c = cos(th);
    s = sin(th);

    im2= [c s;-s c]*[ii qq].';
    
    a = 1/max(abs(im2(1,:)));
    b = 1/max(abs(im2(2,:)));

    for itr=1:10

      im2=[a 0;0 b]*[c s;-s c]*[ii qq].';
      err = im2(1,:).'.^2+im2(2,:).'.^2 - 1;
      err_ms = mean(err.^2);

      if (0)
          ncplot.init();
          plot(im2(1,:),im2(2,:),'.','Markersize',1);
          set(gca(),'PlotBoxAspectRatio', [1 1 1]);
          xlim([-1.1 1.1]);
          ylim([-1.1 1.1]);
          ncplot.txt(sprintf('itr %d', itr));
          ncplot.txt(sprintf('err %g ms', err_ms));
          uio.pause();
      end
      
      if ((itr>1) && (err_ms-prev_err_ms < 1e-6))
          break;
      end
      
      jj = [ 2*a*( c*ii + s*qq).^2 ...
             2*b*(-s*ii + c*qq).^2 ...
             2*a^2*( c*ii + s*qq).*(-s*ii+c*qq)+2*b^2*(-s*ii + c*qq).*(-c*ii-s*qq)];
      mm = (jj.'*jj);
      rc = rcond(mm);
      if (rc < 1e-15)
        fprintf('ERR: poor cond\n');
        break;
      end
      p = mm\(jj.'*-err);
      a=a+p(1);
      b=b+p(2);
      th=th+p(3);
      prev_err_ms = err_ms;
    end
    %    th=(90-imbal_deg)*pi/180;
    %    mmm = [1 0; cos(th) sin(th)]*[ii.'; qq.'];
    %    mmm = [cos(th) sin(th); -sin(th) cos(th)] * [ii.'; qq.'];

    ab = 1/min(a,b);
    a=a*ab;
    b=b*ab;
    im2=[a 0;0 b]*[c s;-s c]*[ii qq].';
    mx=max(abs(im2(:)));

    res.i_off = i_off;
    res.q_off = q_off;
    res.i_factor = a;
    res.q_factor = b;
    res.th_deg = th*180/pi;
    
    res.ab = ab;
end
