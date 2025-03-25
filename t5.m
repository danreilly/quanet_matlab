function t5
  import nc.*
  load('tmp.mat');

  gopt.m = 0;
  gopt.dbg =1;
  gopt.weighting = 'n';
  gopt.init_y_thresh = .5;
  %  gopt.fwhm = 1.5e6; % 5.9e3;
  %  gopt.fwhm = 3e6;

  %      hh_wid = 2*sqrt(-ln(0.5)*2*s^2)
  %  (hh_wid/2) / sqrt(-ln(0.5)*2) =  s
  %  'fit gauss;'
  %  gopt.std = (1e7/2) / sqrt(-log(0.5)*2);
  [a m s o rmse] = fit_lorentzian(x_all, y_all, gopt);
  
end

    function [a m g o rmse] = fit_lorentzian(x, y, opt)
      % weighted lorentzian fit
      % Dan Reilly
      % data must be a postive-going lorentzian
      %      fit(x) = a*g./(pi*((x-m).^2+g^2)) + o
      % g is the half-width at half height.
      % max height (above offset o) is a/(pi*g)
      % slope at x is:
      %      -2*a*g*(x-m)./(pi*((x-m).^2+g^2)^2)
      % options:
      %  opt.m: [] or starting mid value.
      %  opt.fwhm: 0 or starting full-width at half-max.  Supercedes
      %            init_y_thresh
      %  opt.init_y_thresh: determines pts used for initial guess at gamma
      %                range: 0..1  default: .25
      err=0;

      if (size(y,2)>1)
        error('nc.fit.lorentzian(): y must be vertical');
      end
      if (size(x,2)>1)
        error('nc.fit.lorentzian(): x must be vertical');
      end
      if (length(x)<2)
        error('nc.fit.lorentzian(): x is not a vetor');
      end
      if (length(y)<2)
        error('nc.fit.lorentzian(): y is not a vetor');
      end

      s2p = sqrt(2*pi);

      import nc.*
      opt.foo=1;
      opt = util.set_field_if_undef(opt, 'maxiter', 20);
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'fwhm', 0);
      opt = util.set_field_if_undef(opt, 'init_y_thresh', .25);
      opt = util.set_field_if_undef(opt, 'm', []);
      opt = util.set_field_if_undef(opt, 'weighting', 'n');
      opt = util.set_field_if_undef(opt, 'offset', []);
      opt = util.set_field_if_undef(opt, 'gscale', 1);


      if (isempty(opt.offset))
        if (1)
          % take median y of values within 5% of the ends
          th = 0.05;          
          x_mx = max(x);
          x_mn = min(x);
          idxs=[];
          while(length(idxs)<10)
            idxs = find((x< x_mn+(x_mx-x_mn)*th)|(x>x_mx-(x_mx-x_mn)*th));
            if (length(idxs)>10) break; end
            th = th * 1.5;
          end
          y_off = median(y(idxs));
        else
          l = length(y);
          y_mx = max(y);
          y_mn = min(y);
          idxs = find(y < y_mn + (y_mx-y_mn)*0.1); % lower 1%
          y_off = median(y(idxs));
        end
      else
        t_off = opt.offset;
      end

      dbg = opt.dbg;
      if (dbg)
        fprintf('WARN: nc.fit.lorentzian() called with opt.dbg=1\n');
        [co,ch,cq]=ncplot.colors();
      end

      if (0) % dbg)
        h = figure;
        ncplot.init();
        plot(x, y, '.');
        ncplot.title('fit_lorentzian.m');
        line([min(x) max(x)], [1 1]*y_off, 'Color', 'red');
	% ncplot.txt(sprintf('guess o = %g', y_off));
        uio.pause;
        delete(h);
      end
      y = y - y_off;
      o = 0;

      % normalize a little to help numerically
      if (sum(y)==0)
        ysum = 1;
      else
        ysum = abs(sum(y));
      end
      y = y/ysum;

      
      l = length(y);

      a = max(y);

      if (isempty(opt.m))
        m=mean(x(find(y>0.90*a))); % x coord of mean of upper 90%
        if (isempty(m))
          m=0;
        end
      else
        m = opt.m;
      end

      if (opt.fwhm)
        fwhm = opt.fwhm;
        g = fwhm/2;
      else % try to figure it out
        idxs = find(y>opt.init_y_thresh*a); % sub-fit to upper 3/4 of y
        sf_x = (x(idxs)-m).^2;
        sf_y = log(y(idxs));
        sf_l = length(idxs);
        % Now we fit a straight line to sf_x, sf_y
        % we could do:  p = polyfit(sf_x, sf_y, 1);
        % but we try to do better:
        d = [sf_x repmat(1,sf_l,1)];
        if (1)
          wd2=diag(ones(sf_l,1));
        else % weighting helps exclude bad points
          % This weights center more higly
          wd2 = diag(1./(sf_x+1)).^2;
        end
        mm = (d.'*wd2*d);
        rc = rcond(mm);
        if (rc < 1e-15)
          p=fit.polyfit(sf_x, sf_y, 1);
        else
          p = mm\(d.'*wd2*sf_y); % this is better than polyfit
			             %   p = polyfit(xf, sf_y, 1);
        end
        s = 1/sqrt(abs(p(1)));
        % The half-height half-width of a ??? is:
        fwhm = sqrt(-log(0.5)*2*s^2);

        if (opt.dbg)
            h = figure;
	    ncplot.init;
            [co,ch,cq]=ncplot.colors();            
	    ncplot.subplot(2,1);
	    ncplot.subplot;
	    plot(x,y,'.', 'Color', cq(1,:));
            hold('on');
	      plot(x(idxs),y(idxs),'.','Color','green');
	      ncplot.txt(sprintf('a %g', a));
	      ncplot.txt(sprintf('m %g', m));
	      ncplot.txt(sprintf('upper %d% in green',100*opt.init_y_thresh));
	      ncplot.title({'nc.fit.lorentzian.m: DEBUG';
		            'normalized points above thresh 0.20';
		            'used to determin initial STD estimate'});
	      xlabel('x');
	      xlabel('y (norm)');

	      ncplot.subplot;
	      plot(sf_x, sf_y, '.');
	      hold('on');
	      xx=[min(sf_x) max(sf_x)];
	      yy=polyval(p, xx);
	      plot(xx, yy, '-', 'Color', 'green');
	      xlabel('(x-m)^2');
	      ylabel('log(y)');
	      ncplot.txt(sprintf('std est %g', s));
	      ncplot.txt(sprintf('fwhm  %g', fwhm));
	      ncplot.title({'nc.fit.lorentzian.m: DEBUG';
		            'initial STD estimate';
		            'comes from the slope of this'});
	      uio.pause();
              delete(h)
          end
          g = (fwhm/2);
      end
      



      % If we assume we know m and g, we can calc the best a and o:
      if (opt.weighting=='y')
        wd2 = diag(1./(1+(x-m).^2/g^2));
      else
        wd2 = diag(ones(l,1));
      end
      d = [g./((x-m).^2+g^2) ones(l,1)];
      mm = (d.'*wd2*d);
      rc = rcond(mm);
      if (rc<1e-15)
        a = a*g;
      else
        p = mm\(d.' * wd2 * y);
        a = p(1);
        o = p(2);
      end
      if (dbg)
        fprintf('FITL: start  a=%g  o=%g\n', a, o);
      end
    

      if (opt.weighting=='n')
        wd2 = diag(ones(l,1)); % none.  if using this and subtracting median, seems to not converge well
      end

      rec = zeros(opt.maxiter,5);
   
      % param matrix is p=[dm ds].'
      itr=0;
      while(itr<opt.maxiter)

        if (opt.weighting=='y')
          % wd2 = diag(y).^2;
          wd2 = diag(1./(1+(x-m).^2/g^2));
        end
          
        fit = a * g  ./ ((x-m).^2+g^2) + o;
        err = fit-y;
	err_mean = mean(err);
	o   = o - err_mean;
	err = err - err_mean;

	mse = (err.'*err)/l; % TODO: should be weighted
	itr=itr+1;
	rec(itr,:)=[mse a m g o];
	done = (mse<1e-16);
	nochange = ((itr>4)&&(abs(mse-mse_pre)<1e-10));
        
	if (opt.dbg)
	  ncplot.init();
	  plot(x, [y fit], '.');
	  xlim([min(x) max(x)]);
	  ylim([min(y) max(y)]);
	  ncplot.txt(sprintf(' iter %d', itr));
	  ncplot.txt(sprintf(' a m g o [%g %g %g %g]', a, m, g, o));
	  ncplot.txt(sprintf(' rmse %g', sqrt(mse)));
	  if (done)
            ncplot.txt(sprintf(' close enough! done.'));
	  end
	  if (nochange)
            ncplot.txt(sprintf(' not changing! done.'));
	  end
	  %      plot_txt(sprintf(' deltas [%g %g %g]', p(1),p(2),p(3)));
	  ncplot.title({'nc.fit.lorentzian.m: DEBUG';
			'iterative step of fitting'});
	  uio.pause;
	end

	if (done || nochange)
	  break;
	end

        % try mot change m the same time as g
        

        d = [(fit-o)/a  ...
             (fit-o)*2.*(x-m)./((x-m).^2+g^2)];% ...
                                               %            -(fit-o).*(1/g + 2*g./((x-m).^2+g^2))/opt.gscale ];
        mm = (d.'*wd2*d);
	rc = rcond(mm);
	if (rc>1e-15)
  	    p = mm\(d.'*wd2*-err);
	    a = a+p(1);
	    m = m+p(2);
            %        g = g+p(3)/opt.gscale; % change more slowly
            %	o = o+p(3);
	end
        
        d =     -(fit-o).*(1/g + 2*g./((x-m).^2+g^2))/opt.gscale;
        mm = (d.'*wd2*d);
	rc = rcond(mm);
	if (rc>1e-15)
  	  p = mm\(d.'*wd2*-err);
	  g = g+p(1);
        end
        
	mse_pre=mse;	      
      end

      idx=find(rec(1:itr,1)==min(rec(1:itr,1)),1);
      rmse = sqrt(rec(idx,1));
      a=rec(idx,2);
      m=rec(idx,3);
      g=rec(idx,4);
      o=rec(idx,5);

      % de-normalize by ysum and y_off;
      y = y * ysum + y_off;
      o = o * ysum + y_off;
      a = a * ysum;
      % convert to canonical form

      a = a * pi;

      fit = a*g./(pi*((x-m).^2+g^2)) + o;
      err = y-fit;
      mse = (err.'*err)/l;
      fwhm = 2*g; % full width half max

      if (dbg)
	ncplot.init;
	plot(x,[y fit],'.');
	ncplot.txt(sprintf(' FWHM %g', fwhm));
	ncplot.txt(sprintf(' rec rmse %g', rmse));
	ncplot.txt(sprintf(' final rmse %g', sqrt(mse)));
	uio.pause;
      end


    end
