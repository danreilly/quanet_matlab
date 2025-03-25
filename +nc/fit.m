classdef fit
% % 9/14/2017 Dan Reilly
% All "static" methods that do MSE fitting
% Summary:
%   polyfit: like matlab's polyfit, but conditions data to avoid numerical error.
%   gaussian: fits data to a positive-going gaussian
%   polyfit: 
%   spline


  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function [a b c f err_rms]  = sin(sig, fsamp, opt);
      %[a b c f] = nc.fit.sin(sig, fsamp, opt)
      %  desc: finds MMSE fit to vector sig using the model:
      %            a*cos(2*pi*f*t) + b*sin(2*pi*f*t) + c
      %          = sqrt(a^2+b^2)*(cos(2*pi*f*t - atan2(b, a))) + c
      %        assuming the frequency f is already known.
      %        Coded in according to IEEE std 1057, section 4.1.3.1 by Dan Reilly.
      % inputs:
      %   sig: nx1 vector of samples
      %   fsamp: scalar: sample rate at which the samples were taken.  
      %          nx1 vector: sample times
      %   opt: optional structure as follows:
      %     opt.dbg     : 0=normal, 1=debug
      %     opt.weights : nx1 vector of weighting
      %     opt.freq_est 
      %     opt.freq : forces sin to have this frequency. If this is used,
      %                this is a "three-parameter fit"
      import nc.*	     
      sig_l = length(sig);

     
      if (length(fsamp)==1)
	t = (0:sig_l-1).'/fsamp;
      else
        if (size(fsamp,2)~=1)
          error('ERR: fit.sin(sig, t, opt): t (sample times) must be vertical vector');
        end
	t = fsamp;
        fsamp=1/mean(diff(t));
      end
      if (nargin<3)
	opt.dbg=0;
      end
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'dbg_plot', 0);

      if (opt.dbg_plot)
        fg=figure();
      end

      if (isfield(opt,'freq'))
        f = opt.freq;
	d = [cos(2*pi*f*t) sin(2*pi*f*t) ones(sig_l,1)];
	if (isfield(opt,'weights'))
	  ww = diag(opt.weights.^2);
	  x = (d.'* ww *d)\(d.' * ww * sig);
        else
	  x = (d.'*d)\(d.' * sig);
        end
        a = x(1);
	b = x(2);
	c = x(3);


        yy=  a*cos(2*pi*f*t) + b*sin(2*pi*f*t) + c;
        err = yy - sig;
        err_rms = sqrt(mean(err.^2)/sig_l);

        return;
      else

        idx=0;
	if (isfield(opt,'freq_est'))
          f = opt.freq_est;
        else
          ff = fft(sig-mean(sig));
          n2 = floor(sig_l/2)+1;
          [mx idx] = max(abs(ff(1:n2)));
          f = (idx-1)*fsamp/sig_l; % fixed see ieee 1057 spec eqn 90
          if (opt.dbg_plot)
            nc.ncplot.init();
            cq=ncplot.colors_qtr();
            plot(((1:n2)-1)*fsamp/sig_l, abs(ff(1:n2)), '.', 'Color', cq(1,:));
            xlabel('freq (Hz)');
            title('nc.fit,sin() DEBUG');
            ncplot.txt(sprintf('freq %f', f));
            uio.pause;
          end


        end
        opt_est.freq=f; % fix freq to f and find best fit
        [ a b c f] = fit.sin(sig, t, opt_est);
if (idx==1)
  c=( max(sig)+min(sig))/2;
  a=( max(sig)-min(sig))/2;
end
        for k=1:20
          if (opt.dbg)
            fprintf('DBG: fit.sin(): iter %d: f %g\n', k, f);
          end
          yy=  a*cos(2*pi*f*t) + b*sin(2*pi*f*t) + c;
          err = yy - sig;
          err_ms = mean(err.^2)/sig_l;
      	  done = (err_ms<1e-16);
  	  nochange = ((k>4)&&(abs(err_ms-err_ms_pre)<1e-10));
          if (opt.dbg_plot)
            nc.ncplot.init();
            cq=ncplot.colors_qtr();
            plot(t,sig,'.');
            plot(t,yy,'-','Color','green');
            title('nc.fit,sin() DEBUG');
            ncplot.txt(sprintf('iteration %d', k));
            ncplot.txt(sprintf('freq %g', f));
            ncplot.txt(sprintf('mean sq err %g ', err_ms));
  	    if (nochange)
              ncplot.txt(sprintf(' not changing! done.'));
	    end
            uio.pause;
          end

  	  if (done || nochange)
	    break;
	  end

          d = [cos(2*pi*f*t) sin(2*pi*f*t) ones(sig_l,1) ...
           -a*t.*sin(2*pi*f*t)+b*t.*cos(2*pi*f*t)];
          % x = inv(d.'*d)*d.'*y; % mathematically valid, but...
          dd = (d.' * d);
          if (rcond(dd)<1e-10)
            if (opt.dbg_plot)            
              fprintf('WARN: fit_sin: matrix close to singular!\n');
            end
            % quit now before we divide by zero
            break;
          end
          
          x = (dd) \ (d.' * sig); % matrix division is more efficient
          a = x(1);
          b = x(2);
          c = x(3);
          df = x(4)/2/pi;
          f = f + df;
          % fit_vpp = 2*sqrt(a^2+b^2);
%          if (abs(df)/f<1e-12)
           % fprintf('stopping at %d\n', k);
%$            break;
%          end
          err_ms_pre = err_ms;
        end
      end

      err_rms = sqrt(err_ms);

      if (opt.dbg_plot)
        delete(fg);
      end

    end

    function [a m g o rmse] = lorentzian(x, y, opt)
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
      l = length(y);
      if (length(x) ~= l);
        error(sprintf('nc.fit.lorentzian(): length of x=%d does not equal length of y=%d', length(x), l));
      end
      if (l<3)
          error(sprintf('nc.fit.lorentzian(): length(y)=%d is less than three. Fitting impossible.', l));
      end
      if (l<10)
          fprintf('WARN: nc.fit.lorentzian(): length(y)=%d so fitting may be hard', l);
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
        th = opt.init_y_thresh;
        while(1)
          idxs = find(y>th*a); % sub-fit to upper part of y
          if (length(idxs) >= min(10, (l/2)))
              break;
          end
          th = th * .9; % lower the threshold
        end        
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

    function [a m g o rmse] = lorentzian_old(x, y, opt)
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

      % Note: I really fit to:
      %     fit = a / ((x-m)^2+g)

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
        g = (fwhm/2)^2; % not for gen eqn but for our fit
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
          g = (fwhm/2)^2; % not for gen eqn but for oure fit
      end
      



      % If we assume we know m and g, we can calc the best a and o:
      if (opt.weighting=='y')
        wd2 = diag(1./(1+(x-m).^2/g));
      else
        wd2 = diag(ones(l,1));
      end
      d = [1./((x-m).^2+g) ones(l,1)];
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
          wd2 = diag(1./(1+(x-m).^2/g));
        end
          
        fit = a ./ ((x-m).^2+g) + o;
        err = y-fit;
	err_mean = mean(err);
	o   = o + err_mean;
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

%	d = [fit/a  fit*2.*(x-m)./((x-m).^2+g)  -fit./((x-m).^2+g) repmat(1,size(x))];
%        mm = (d.'*wd2*d);
	rc = 0; % rcond(mm);
	if (rc>1e-15)
	    p = mm\(d.'*wd2*err);

            
        else

          d = [(fit-o)/a  (fit-o)*2.*(x-m)./((x-m).^2+g)  -(fit-o)./((x-m).^2+g)/opt.gscale ];
          mm = (d.'*wd2*d);
	  rc = rcond(mm);
	  if (rc<1e-15)
            fprintf('WARN: fit_lorentzian: matrix close to singular!\n');
	    % quit now before we divide by zero
	    break;
	  end
	  p = mm\(d.'*wd2*err);

          p(4)=0;			      
        end

	a = a+p(1);
	m = m+p(2);
	g = g+p(3)/opt.gscale; % change more slowly
	o = o+p(4);

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
      g = sqrt(g);
      a = a * pi / g;


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

    function [a m s o rmse] = gaussian(x, y, opt)
      % weighted gaussian fit
      % Dan Reilly
      % a fit that weights the main lobe of a gaussian
      %      fit = a/(sqrt(2*pi)*s)*exp(-(x-m).^2/(2*s^2)) + o;
      % where a may be positive or negative.
      % The half-height width of a gaussian is:
      %      hh_wid = 2*sqrt(-ln(0.5)*2*s^2)
      % 
      % inputs:
      %  opt.weigting: 'n'=none, 'y'=weight by y offset
      %  opt.std: 0=calc starting stddv estimate, other=starting std dev estimate
      %  opt.m: [] or starting mid value.

      %  rmse = root mean square error
      err=0;

      if ((size(x,2)~=1) || (size(x,1)<4))
	error('nc.fit.gaussian(x,y,opt): x must be a vertical vector of at least four values');
      end
      if ((size(y,2)~=1) || (size(y,1)<4))
	error('nc.fit.gaussian(x,x,opt): y must be a vertical vector of at least four values');
      end

      s2p = sqrt(2*pi);

      import nc.*
      opt.foo=1;
      opt = util.set_field_if_undef(opt, 'maxiter', 20);
      opt = util.set_field_if_undef(opt, 'dbg', 0);
      opt = util.set_field_if_undef(opt, 'weighting', 'n');
      opt = util.set_field_if_undef(opt, 'std', 0);
      opt = util.set_field_if_undef(opt, 'offset', []);
      opt = util.set_field_if_undef(opt, 'm', []);
      dbg = opt.dbg;

      if (isempty(opt.offset))
	ym = median(y);
      else
	ym = opt.offset;
      end

      if (dbg)
        xl=[min(x) max(x)];
	fprintf('WARN: nc.fit.gaussian() called with opt.dbg=1\n');
	h = figure;
	ncplot.init();
	plot(x, y, '.');
	ncplot.title('nc.fit.gausian() DEBUG');
	line(xl, [1 1]*ym);
        xlim(xl);
	uio.pause();
      end
      
      % normalize a little to help numerically
      y = y - ym;
      ysum = sum(y);
      if (ysum==0)
	ysum = 1;
      end
      y = y/ysum; % now gaussian is positive.

      l = length(y);

      a=max(y);
      if (isempty(opt.m))
        idxs=find(y>=a/2);
        sy=sum(y(idxs));
        if (sy~=0)
          m = sum(x(idxs).*y(idxs))/sy;
%     center of all mass did not work well!
%          m = sum(x.*y)/sy); % center of all mass
      	  if (opt.dbg)
            ncplot.subplot();
            plot(x(idxs), x(idxs).*y(idxs),'.');
            line([m m],[-1 1],'Color','green');
	    fprintf('FIT DBG: using center of mass as starting m = %g\n', m);
            xlim(xl);
            uio.pause;
	  end
        else
          m=mean(x);
      	  if (opt.dbg)
	    fprintf('FIT DBG: using mean(x) as starting m = %g\n', m);
	  end
        end
      else
        m=opt.m;
	if (opt.dbg)
	  fprintf('FIT DBG: given starting m of %g\n', m);
	end
      end

      if (opt.std>0)
	s = opt.std;
	if (opt.dbg)
	  fprintf('FIT DBG: given starting std of %g\n', s);
	end
      else % calculated starting estimate of standard deviation
	idxs = find(y>0.5*a);
        sf_l = length(idxs);
        if (sf_l==1)
          m=x(idxs);
          idxs2=max(idxs-1,1):min(idxs+1,length(y));
          s=mean(diff(x(idxs2)))
        elseif (sf_l>1)
  	  sf_x = (x(idxs)-m).^2;
	  sf_y = log(y(idxs));
  	  d = [sf_x repmat(1,sf_l,1)];
  	  if (0)
	    wd2=diag(ones(sf_l,1));
	  else % weighting helps exclude bad points
	    wd2 = diag(1./(sf_x+1)).^2;
	  end
          rc = rcond(d.'*wd2*d);
          if (rc<1e-15)
            'WARN:  singular'
          end
	  p = (d.'*wd2*d)\(d.'*wd2*sf_y); % this is better than polyfit
          % was:  p = polyfit(xf, sf_y, 1);
          s = 1/sqrt(abs(p(1)));
        else
          s=1;
        end

	if (dbg && (sf_l>1))
	  ncplot.init;
	  subplot(2,1,1);
	  plot(x,y,'.');
	  hold('on');
	  plot(x(idxs),y(idxs),'.','Color','green');
          line([1 1]*m,[min(y) max(y)],'Color','green');
          line([min(x) max(x)],[1 1]*a,'Color','green');

	  ncplot.txt(sprintf('a %g', a));
	  ncplot.txt(sprintf('m %g', m));
	  ncplot.txt('upper 75% in green');
	  ncplot.title({'nc.fit.gaussian.m: DEBUG';
			'normalized points above thresh 0.20';
  			'used to determin initial STD estimate'});
	  xlabel('x');
	  xlabel('y (norm)');

	  subplot(2,1,2);
	  plot(sf_x, sf_y, '.');
	  hold('on');
	  xx=[min(sf_x) max(sf_x)];
	  yy=polyval(p, xx);
	  plot(xx,yy,'-', 'Color', 'green');
	  xlabel('(x-m)^2');
	  ylabel('log(y)');
	  ncplot.title({'nc.fit.gaussian.m: DEBUG';
			'initial STD estimate';
			'comes from the slope of this'});
	  uio.pause;
	end
     end



  a=(a)*(s2p*s);

%  a = 1;
%  scale = sum(y);
%  if (g.dbg)
%    m
%  s = 0.8;
%  end


  if (opt.weighting=='n')
    wd2 = diag(ones(l,1)); % none.  if using this and subtracting median, seems to not converge well
  elseif (opt.weighting=='y')
    wd2 = diag(y).^2;
  end

  % fitting to y = a/(sqrt(2pi)*s)*exp(-(x-m).^2/(2*s^2))
  % param matrix is p=[dm ds].'
  for k=1:opt.maxiter
    fit = a/(s2p*s)*exp(-(x-m).^2/(2*s^2));
    % weighting

%    w = fit/a/(s * sqrt(2*pi));

    err = y-fit;
    mse = (err.'*err)/l; % TODO: should be weighted
    rec(k,:)=[mse a m s];
    done = (mse<1e-16);

    if (dbg)
      ncplot.init();
      plot(x, [y fit], '.');
      xlim([min(x) max(x)]); ylim([min(y) max(y)]);
      ncplot.txt(sprintf(' iter %d', k));
      ncplot.txt(sprintf(' a m s [%g %g %g]', a, m, s));
      ncplot.txt(sprintf(' rmse %g', sqrt(mse)));
      if (done)
        ncplot.txt(sprintf(' close enough! done.'));
      end
%      plot_txt(sprintf(' deltas [%g %g %g]', p(1),p(2),p(3)));
      ncplot.title({'nc.fit.gaussian.m: DEBUG';
			'iterative step of fitting'});
      uio.pause;
    end

    if (done)
      break;
    end

% err
%    err2 = (err.'*err*wd2)/scale^2;


    d = [fit/a  (x-m)/s^2.*fit  ((x-m).^2/(s^3)-1/s).*fit];

%    d = [fit/a (x-m)/s^2.*fit];

% I think it conveges better if you allow a to change
%    d = [(x-m)/s^2.*fit ((x-m).^2/(s^3)-1/s).*fit];

    mm = (d.'*wd2*d);

%    % TODO: where did this metric come from?
%    mm_metric = sum(sum(mm.*mm));

    rc = rcond(mm);
    if (rc<1e-15)
      fprintf('WARN: fit_gaussian: matrix close to singular!\n');
      % quit now before we divide by zero
      break;
    end
    p = mm\(d.'*wd2*err);


    if ((k>4)&&(abs(mse-mse_pre)<1e-10))
      if (dbg) fprintf('mse not changing so end\n'); end
      break;
    end
    a = a+p(1);
    m = m+p(2);
    s = s+p(3);
    if (s<0)
      fprintf('ERR: fit_gaussian: instability! negative sigma!\n');
      s = s-p(3);
    end	      
    mse_pre=mse;	      
  end


    idx=find(rec(:,1)==min(rec(:,1)),1);
    rmse = sqrt(rec(idx,1));
    a=rec(idx,2);
    m=rec(idx,3);
    s=rec(idx,4);

    if (dbg)
      [xx idx]=sort(x);
      yy=y(idx);
      fit = a/(s2p*s)*exp(-(xx-m).^2/(2*s^2));
      ncplot.init();
      plot(xx, [yy fit], '.-');
      ncplot.xlim([min(xx) max(xx)]);
      ncplot.ylim([min(yy) max(yy)]);
      ncplot.txt(sprintf(' answer'));
      ncplot.txt(sprintf(' a m s [%g %g %g]', a, m, s));
      ncplot.txt(sprintf(' mse %g', mse));
      uio.pause;

      delete(h);
    end

    a=ysum*a;
    o=ym;
  end

  function [pt n] = plane(m)
% desc
%   finds a plane
%   that has MSE normal distance to a set of unordered points in 3 dimensions.
% inputs
%   m: nx3 matrix of points in 3d
% returns
%   pt : 3x1 point coordinate in the plane (at mean of all points)
%   n  : 3x1 unit vector normal to plane
    pt = mean(m).';
    mm=m-repmat(pt.',size(m,1),1);
    d=mm.'*mm;
    [evs lams] = eig(d);
    [lam idx]=min(diag(lams));
    n = evs(:,idx);
  end

  function p = polyfit(x, y, ord)
    % same as polyfit, but auto-conditions x and y around their mean
    import nc.*
    dbg =0;

    if (~isvector(x)||~isvector(y))
      error('nc.fit.polyfit(x,y): x and y must be vectors');
    end
    if (length(x)~=length(y))
      error('nc.fit.polyfit(x,y): x and y must be same length');
    end
    x_r = max(x)-min(x);
    x_l = length(x);
    if (x_l<2)
      error('nc.fit.polyfit(x,y): x has length less than two');
    end
    if (x_r<=0)
      error(sprintf('nc.fit.polyfit(x,y): x values are all the same\n  note: length(x)=%d', x_l));
    end

    x_m = mean(x);
    y_m = mean(y);
    xx = (x - x_m)/x_r;
    yy = y - y_m;
    p_c = polyfit(xx, yy, ord);

    if (dbg)
      ncplot.init;
      plot(x,y,'.'); hold('on');
      p2 = p_c;
      p2(end)=p2(end)+y_m;
      yy =  polyval(p2, (x-x_m));
      plot(x,yy,'-','Color','green');
    end

    % Now p_c = [p1 p2 p3]
    % is the polyfit to y' ~ f(x').
    % but what we really want is y ~ f(x).
    % y - y_m = f ( (x - x_m)/x_r )
    %         = p1*((x-x_m)/x_r)^2 + p2*((x-x_m)/x_r) + p3
    %     
    %         =    p1/x_r^2 * ( x^2  -2x*x_m + x_m^2 )
    %           +  p2/x_r   * (        x     - x_m   )
    %           +  p3       * (                 1    )
    %
    %  let p_c = [p1/x_r^2  p2/x_r  p3]


    p_c = p_c ./ (ones(1,ord+1)*x_r).^(ord:-1:0);

    %         =   p1*[  1    -2*x_m     x_m^2]   [ x^2]
    %             p2*[         1       -x_m  ] * [ x  ]
    %            +p3*[                   1   ]   [ 1  ]
    
    p = p_c;


    m_p = (-ones(1,ord+1)*x_m).^(1:ord);
    %   = [1    m  m^2 ]

    for k=1:ord
      % binomial coefs for (x + m)^k
      bi_coef = factorial(k)./(factorial(0:k).*factorial(k-(0:k)));

      %    p(ord+1-k)
      %    bi_coef(2:end)
      %    m_p(1:k)

      a = p_c(ord+1-k) * bi_coef(2:end) .* m_p(1:k);
      p(ord+2-k:end) = p(ord+2-k:end) + a;
      
      if (dbg)
        fprintf('k %d  p_c %g\n', k, p_c(ord+1-k));
        fprintf('  bicoef %s\n',sprintf(' %g', bi_coef(2:end)));
        fprintf('  m_p    %s\n',sprintf(' %g', m_p(1:k)));
        fprintf('  p(%d:%d) += %s\n', ord+2-k,length(p), sprintf(' %g', a));
      end
    end
    p(end)=p(end)+y_m;

    if (dbg)
      yy=polyval(p, x);
      plot(x,yy,'-','Color','red');
    end
  end

  function xs = ppinv(pp, y, opt)
    % desc: inverts a spline. may return multiple solns or []
    % inputs: opt.extend: extends pieces on each end out of range
    if (nargin<3)
      opt.extend=0;
    end
    xs=[];
    for k=1:pp.pieces
%      fprintf('x %g .. %g\n', pp.breaks(k),pp.breaks(k+1));
      piece_len = pp.breaks(k+1)-pp.breaks(k);
      coefs=pp.coefs(k,:);
      % coef are local to each piece
      coefs(end)=coefs(end)-y;
      r = roots(coefs);
      for ri=1:length(r)
        if (isreal(r(ri)))
          x=r(ri);
          ext = opt.extend && ...
                ( ((x<0)&&(k==1)) || ((x>piece_len)&&(k==pp.pieces)));
          if (((0<=x)&&(x<=piece_len)) || ext)
            xs=[xs x+pp.breaks(k)];
          end
        end
      end
    end
  end


  function pp = spline(x, y, breaks, opt)
    % desc: Approximates the points x,y by a set of "pieces" defined by polynomials y=f(x).
    %       The "pieces" join together smoothly at the "breaks".
    % inputs:
    %    x: set of x values                nx1
    %    y: set of corresponding y values. nx1
    %    breaks: x values of the endpoints of the segments (or y values if opt.breaks_are_y=1)
    %        A vector of length one more than the number of segments.
    %    opt.order: 2 or 3 (default)
    %    opt.breaks_are_y: 0 (default) or 1
    % oututs:
    %    pp: a piecewise polynomial of the format used by matlab function ppval():
    %      struct with fields:
    %       pp.form: 'pp'
    %       pp.breaks: x coordinates of breaks
    %       pp.coefs: matrix, one row per "peice".  Each row contains polynomial coeficients
    %       pp.pieces: number of pieces.  an integer.
    %       pp.order: 2 or 3
    %       pp.dim: 1
    import nc.*           
    if (~isvector(x) || ~isvector(y))
      error('x and y must be vectors');
    end
    if (size(x)~=size(y))
      error('x and y must be same size');
    end
    dbg=0;
    x=x(:);
    y=y(:);
    opt.foo=1;
    opt = util.set_field_if_undef(opt, 'order', 3);
    opt = util.set_field_if_undef(opt, 'breaks_are_y', 0);
    npieces = length(breaks)-1;
    if (length(x)<npieces*2)
      error(sprintf('not enough points (only %d) for fitting', length(x)));
    end

    for k=1:length(breaks)
      if (opt.breaks_are_y)
        d = abs(y-breaks(k));
      else
        d = abs(x-breaks(k));
      end
      [mn breaks_i(k)] = min(d);
    end
    
    if (~all(diff(breaks_i)~=0))
      fprintf('fit.spline(): NOTE: merging breaks that are too close\n');
      while(1)
        idx = find(diff(breaks_i)==0,1);
        if (isempty(idx)) break; end
        
        breaks(idx)=mean(breaks(idx),breaks(idx+1));
        breaks(idx+1)=[];
        breaks_i(idx+1)=[];
      end
    end
    npieces=length(breaks_i)-1;

    % break x and y values into "pieces"
    xs=cell(npieces,1);
    ys=cell(npieces,1);
    if (dbg)
      breaks
    end
    for k=1:npieces
      if (~opt.breaks_are_y)
        if (k<npieces)
          idxs = find((x>=breaks(k))&(x<breaks(k+1)));
        else
          idxs = find((x>=breaks(k))&(x<=breaks(k+1)));
        end
      else
        if (k<npieces)
          idxs = find((y>=breaks(k))&(y<breaks(k+1)));
        else
          idxs = find((y>=breaks(k))&(y<=breaks(k+1)));
        end
      end
      xs{k}=x(idxs);
      ys{k}=y(idxs);
      if (dbg)
        fprintf('piece %d:  x %g .. %g\n', k, min(xs{k}), max(xs{k}));
      end
    end

    if (opt.breaks_are_y)
      breaks_x(1) = xs{1}(1);
      for k=2:npieces
	p = polyfit([xs{k-1}(end) xs{k}(1)], [ys{k-1}(end) ys{k}(1)], 1);
	breaks_x(k)=(breaks(k)-p(2))/p(1);
      end
      breaks_x(npieces+1) = xs{npieces}(end);
    else
      breaks_x = breaks;
    end
    
    for k=1:npieces
      xs{k}=xs{k}-breaks_x(k);
    end
    
    c=cell(npieces,1);
    d=cell(npieces,1);
    c{1}=eye(opt.order+1);
    ee = [];
    for k=1:npieces
      if (k>1)
	c{k}=calc_cm(breaks_x(k)-breaks_x(k-1), opt.order);
      end
      d{k}=calc_d(xs{k},opt.order);
      ee = [ee; ys{k}];
    end

    dd=[];
    cc = eye(opt.order+npieces);


    for k=1:npieces
      %    d{k} * [c{k} zeros(opt.order+1, npieces-k)] * cc;
      if (k>1)
	%      fprintf('%d: c=%dx%d, ext to %d\n', k, size(c{k},1), size(c{k},2),  opt.order+npieces+2-k);
	cc = eye_extend(c{k}, opt.order+npieces+2-k) * cc;
      end
      %    size(cc)
      dd = [dd; (d{k} * [eye(opt.order+1) zeros(opt.order+1, npieces-k)] * cc)];
    end

    t = (dd.'*dd)\(dd.'*ee);


    coefs=zeros(npieces, opt.order+1);

    c{1}=eye(opt.order+1);
    for k=1:npieces
      if (k>1)
	t = eye_extend(c{k}, opt.order+npieces+2-k) * t;
      end
      coefs(k,:) = t(1:opt.order+1).';
    end


%nc.uio.print_matrix('coefs1', coefs(1,:));
%nc.uio.print_matrix('coefs2', coefs(2,:));
    pp = mkpp(breaks_x, coefs);
    yy = ppval(pp, x);


    % nested
    function mnew = eye_extend(m, w)
    % adds ones diagonally off bottom right
      mnew=m;	     
      for eyext_k=size(m,2)+1:w
	mnew(end+1,end+1)=1;
      end
    end

    %nested
    function cm = calc_cm(k, order)
      % continuity matricies
      if (order==3)
	cm = [ 0      0      0  0   1 ;
               3*k    1      0  0   0 ;
               3*k^2  2*k    1  0   0 ;
               k^3    k^2  k  1   0];
      else
	cm = [0     0 0  1 ;
              2*k   1 0  0 ;
              k^2 k 1  0];
      end
      return;

      if (order==3)
	cm = [ 0      0 0 0  1     ;
               3*k^1  1 0 0 -3*k^1 ;
               -3*k^2  0 1 0  3*k^2 ;
               k^3  0 0 1   -k^3];
      else
	cm = [0     0 0  1     ;
              2*k   1 0 -2*k   ;
              -k^2 0 1    k^2];
      end
      % p2 = cm*[p1; a2]
    end

    %nested
    function d = calc_d(x, order)
      if (order==3)
	d = [x.^3 x.^2 x ones(size(x)) ];
      else
	d = [x.^2 x ones(size(x)) ];
      end
    end

   end
    


  end
end
