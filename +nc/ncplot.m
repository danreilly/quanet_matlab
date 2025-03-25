classdef ncplot
% NC.NCPLOT
% desc: a class (containing only static methods) to help with plotting
% 
%   See also NC.NCPLOT.INIT,  NC.NCPLOT.TXT, NC.NCPLOT.TITLE, NC.NCPLOT.XLIM, NC.NCPLOT.YLIM.

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class


    function cdata = fill(cdata,x,y,newcolor)
                           % does a "fill" on colordata from point x,y
      w=size(cdata,1);
      h=size(cdata,2);
      oldcolor=cdata(y,x,:);
      if (squeeze(oldcolor)==newcolor(:))
        % fprintf('WARN: oldcolor=newcolor\n');
        return;
      end
      pending=zeros(0,2);
      while(1)
        if (cdata(y,x,:)==oldcolor)
          while((x>1)&&all(cdata(y,x-1,:)==oldcolor))
            x=x-1; % backup
          end
%          fprintf('x %d   y %d\n', x, y);
          d_st=0;
          u_st=0;
          while((x<=w)&&all(cdata(y,x,:)==oldcolor))
            cdata(y,x,:)=newcolor;
            if (y>1)
              if (~u_st)
                if (cdata(y-1,x,:)==oldcolor)
                  pending(end+1,1:2)=[x y-1];
                  u_st=1;
                end
              else
                u_st = u_st && all(cdata(y-1,x,:)==oldcolor);
              end
            end
            if (y<h)
             if (~d_st)
               if (cdata(y+1,x,:)==oldcolor)
                 pending(end+1,1:2)=[x y+1];
                 d_st=1;
               end
             else
               d_st = d_st && all(cdata(y+1,x,:)==oldcolor);
             end
            end
            x=x+1;
          end % inner while
        end
        if (size(pending,1)==0)
          break;
        end
%        nc.uio.pause('nxt');
        x=pending(1,1);
        y=pending(1,2);
        pending(1,:)=[];
      end
    end
    
    function set_fig_size_in(fig, size_in)
    % size_in is [w h]
      un = get(fig,'Units');
      set(fig,'Units','inches');
      pos = get(fig,'Position');
      pos(3:4)=size_in;
      set(fig, 'Position', pos);
      set(fig,'Units',un);
    end

    
    function init_axes(ax)
      import nc.*
      if (nargin<1)
        ax = gca();
      end
      cla(ax);
      title('');
      legend('hide');
      set(ax, 'Fontsize', 8);
      ncplot.txt(.05,.9,.1);
      % this does not work in new matlab:
      % in the new matlab, plot() resets axes label fontsize.
      set(get(ax,'XLabel'),'FontSize', 8);
      set(get(ax,'YLabel'),'FontSize', 8);
      hold(ax, 'on'); % prevents plot from changing label fontsize
%      colormap(ax, ncplot.old_colormap);
    end
    
    function init
    % NC.NCPLOT.INIT
    % desc: open a new figure window for plotting with a few defaults,
    %       such as a white backround and a smaller default axis font.	     
      import nc.*
      % scope: static
      hold('off');
      fig = gcf();
      clf(fig); 
      set(fig, 'Color', 'white');
				%  axs=get(gcf,'Children');
				%  if (length(axs)>1) 
				%    set(fig,'Children',axs(1));
				%  end
      ncplot.init_axes;

    end

    function cm=old_colormap
      % in Matlab R2017a, those punks changed the default colormap.
     cm = [0         0    1.0000
         0    0.5000         0
    1.0000         0         0
         0    0.7500    0.7500
    0.7500         0    0.7500
    0.7500    0.7500         0
    0.2500    0.2500    0.2500];
    end

    function cm=colors_half
      cm=0.5 + nc.ncplot.old_colormap*0.5;
    end
    function cm=colors_qtr
      cm=0.75 + nc.ncplot.old_colormap*0.25;
    end

    function [co,ch,cq]=colors
      co=nc.ncplot.old_colormap();
      ch=nc.ncplot.colors_half();
      cq=nc.ncplot.colors_qtr();
    end

    function h = txt(p1, p2, p3, p4, p5)
      % NC.NCPLOT.TXT
      % desc: adds a line of text onto current plot. wraps if too long.
      %    simplifies exponential notaion such as 3.14e+002 to 3.14e2
      % scope: static
      % usage:
      %   txt(n) - sets "current line" to be n.  0 is top, 1 is bottom
      %   txt(x, y) - sets "current line" to be x & "start col" to y
      %   txt(x, y, dy) - also sets height increment (line spacing)
      %   txt(x, y, dy, color) - also sets color
      %   txt(<str>) - adds string and advances "current line"
      %   txt(<str>,<color>) - adds string of that color, advances "current line"
      import nc.*
      persistent p;
      if (~isfield(p, 'x'))
	p.x=.1;
	p.y=.9;
	p.d=.05;
	p.color='black';
      end


      h = p.y;

      if (ischar(p1))
        str=ncplot.esc_ubar(uio.short_exp(p1));

      if (nargin==1)
	p2=p.color;
      end
      hascolor = strfind(str,'\color');

      ss=1;
      while(1)
	if (hascolor)
          se=length(str);
          text(p.x, p.y, str, 'Units', 'normalized', 'FontSize', 9, ...
               'FontName', 'FixedWidth', 'HitTest', 'off');
	else
          se=min(ss+59, length(str));
          text(p.x, p.y, str(ss:se), 'Units', 'normalized', 'FontSize', 9, ...
               'FontName', 'FixedWidth', 'Color', p2, 'HitTest', 'off');
	end
	p.y = p.y-p.d;
	ss = se+1;
	if (ss > length(str))
	  break;
	end
      end
      return;
    end % if ischar(p1)

    if (nargin==1)
      if (isnumeric(p1))
	p.y=p1;
      end
      return;
    end

    if (isnumeric(p1) && isnumeric(p2))
      p.x=p1;
      p.y=p2;
    else
      error('plot_txt: for >2 params, first two must be numeric');
    end
    if (nargin==4)
      p.color=p4;
    elseif(nargin>1)
      p.color='black';
    end
    if (nargin>=3)
      p.d=p3;
    end
  end

    
  function title(s)
    % desc:
    %   Adds a title to an axes, just like the matlab title() function,
    %   but it reformats the strings so you can print underscores.
    %   Helps avoids the rather annoying error that matlab throws
    %   "Character vector must have valid interpreter syntax".
    %   Rather like title(s,'Interpreter','none') now that I think about it.
      import nc.*
      if (iscell(s))
	for k=1:length(s)
	  s{k}=ncplot.esc_ubar(s{k});
        end
        title(s);
      else
        title(ncplot.esc_ubar(s));
      end
    end

    function xlim(xl)
    % NC.NCPLOT.XLIM
    % desc: Matlab's xlim function has the annoying behavior of crashing
    %       if the high and low limits are the same.  This function just
    %       extends the limits by one in that case, to avoid a crash.
      if (xl(1)==xl(2)) % matlab would crash!
        xl = [-1 1]+xl(1);
      elseif (xl(1)>xl(2))
	xl = [xl(2) xl(1)];
      end
      xlim(xl);
    end
    
    function ylim(yl)
    % NC.NCPLOT.YLIM
    % desc: Matlab's ylim function has the annoying behavior of crashing
    %       if the high and low limits are the same.  This function just
    %       extends the limits by one in that case, to avoid a crash.
      if (yl(1)==yl(2)) % matlab would crash!
        yl = [-1 1]+yl(1);
      elseif (yl(1)>yl(2))
	yl = [yl(2) yl(1)];
      end
      ylim(yl);
    end
    
    function s2=esc_ubar(s)
    % NC.NCPLOT.ESC_UBAR
    % replace each underscore with backslash-underscore
    % so it appears properly in a plot title.
      import nc.*
      s2=s;
      k=1;
      for j=1:length(s)
        if ((s(j)=='_') || (s(j)=='\') || (s(j)=='^'))
          s2(k)='\';
          s2(k+1)=s(j);
          k=k+2;
        else
          s2(k)=s(j);
          k=k+1;
        end
      end
    end

    function ax = subplot(h,w)
% usage:
%   subplot(h,w) - declares height and width of subplot grid
%   subplot()    - moves on to the next subplot.  Must be called for first subplot.
      persistent sp_i sp_h sp_w
      if (nargin==2)
	nc.ncplot.init;
	sp_i = 1;
	sp_h = h;
	sp_w = w;
        ax=[];
      else
	if (sp_i > sp_h*sp_w)
	  fprintf('ERR: wrapping the subplots!\n')
          sp_i=1;
        end
        subplot(sp_h, sp_w, sp_i);
        sp_i=sp_i+1;
        nc.ncplot.init_axes;
        ax = gca();
      end
    end

    function save(arg1, arg2)
      % desc: saves current figure as jpg or png
      % fnf: filename.  extension determines format. Must be .png or .jpg
      if (nargin==2)
        f=arg1;
        filename = arg2;
      else
        f = gcf();
        filename = arg1;
      end
      [~, ~, ext] = fileparts(filename);
      if (isempty(ext))
        fmt='jpeg';
        filename=[filename '.jpg'];
      elseif (strcmp(ext,'.jpg'))
        fmt='jpeg';
      elseif (strcmp(ext,'.png'))
        fmt='png';
      else
  	error(sprintf('plot.save(%s): filename must end in jpg or png', filename));
      end

      set(f,'units', 'centimeters','PaperPositionMode','auto');
      %    p = get(f,'position');
      %    p(3)=4; % width
      %    p(4)=3; % height
      %    set(f,'position', p);
      % To print or save figures that are the same size as the figure on
      % the screen, ensure that the PaperPositionMode property of the
      % figure is set to 'auto' before printing.  To generate output that
      % matches the  on-screen size in pixels, include the '-r0' resolution
      % option when using the print function.
      [path, ~, ~]=fileparts(filename);
      nc.fileutils.ensure_dir(path);
      fprintf('saving %s\n', filename);
      % print(f, ['-d' fmt], '-r0', filename);
      print(f, ['-d' fmt], '', filename);
    end

    function invisible_axes()
      set(gca(),'Color','none','Position',get(gca,'OuterPosition'),...
          'XColor','white','YColor','white');
    end
        
    
    function res = fft(sig, tsamp, opt)
    % opt
    %   .nowindow: 1=no window, 0=hann window (default 1)
    %   .noplot: 1=no plot,  0=plot (default 0)
    %   .color:
      import nc.*
      if (~isvector(sig))
        error('nc.ncplot.fft(sig, tsamp): sig must be a vector');
      end
      if (nargin<3)
        opt.no_window=1;
      elseif (~isstruct(opt))
        error('nc.ncplot.fft(sig, tsamp, opt): opt must be a structure');
      end
      opt = util.set_field_if_undef(opt, 'no_window', 1);
      opt = util.set_field_if_undef(opt, 'color', 'blue');
      opt = util.set_field_if_undef(opt, 'no_plot', 0);
      opt = util.set_field_if_undef(opt, 'dBm', 0);
      opt = util.set_field_if_undef(opt, 'plot_y', 0);
      opt = util.set_field_if_undef(opt, 'plot_y2', 0);
      
      sig = sig(:);
      % fprintf('sig pwr %g\n', mean(sig.^2));

      l = length(sig);
%      l2 = floor(l/2)+1;
      l2 = ceil(l/2);


      if (~opt.no_window)
        % Hann window to reduce "leakage" (see IEEE 1057 4.1.6)
        % Then dan added sqrt(8/3) so power is consistent after windowing
          sig = sig .* (.5-.5*cos(2*pi*(0:l-1).'/l)) * sqrt(8/3);
      end

      f_n=fft(sig-mean(sig));

      %  fprintf('sig pwr %g\n', mean(f_n'*f_n/(l*l)));
      f_r=abs(f_n(1:l2));  % only look at magnitude of half of it
      [fmax idx] = max(f_r(2:end));
      if (~mod(l,2) && (idx==l2))
        res.peak_pwr_ms = fmax^2/(l*l); % power units
      else
        res.peak_pwr_ms = (fmax^2 + abs(f_n(l+1-idx))^2)/(l*l); % power units
      end

      %  fprintf('max pwr %g\n', res.ymax2);
      if (opt.dBm)
        xf=20*log10(f_r);
      else
        xf=20*log10(f_r/fmax);
      end
      
      fft_i = (0:l2-1).'/(l*tsamp);
      if (~opt.no_plot)
        if (opt.plot_y2)
          semilogy(fft_i(2:end), f_r(2:end).^2, 'Color', opt.color);
          ylabel('fft ');
        elseif (opt.plot_y)
          % plot y on a semilogy plot
          semilogy(fft_i(2:end), f_r(2:end), 'Color', opt.color);
          ylabel('fft ');
        else
          plot(fft_i(2:end), xf(2:end),'Color', opt.color);
          if (opt.dBm)        
              ylabel('power (dBc)');
          else
              ylabel('power (dBrel)');
          end
        end
        xlim([fft_i(2) fft_i(end)]);
        xlabel('freq (Hz)');
      end
      
%      nc.uio.print_matrix('freq',fft_i(2:end).');
%      nc.uio.print_matrix('pwr_dBc',xf(2:end).');

      m=max(xf(2:end));
      idx=find(m==xf(2:end))+1;

      res.x_Hz  = fft_i(2:end);
      res.y_dBc = xf(2:end);    
      res.main_freq_idx = idx-1;
      
      res.main_freq_Hz = fft_i(idx);
      res.main_ph_rad = angle(f_n(idx));
      res.rbw_Hz = 1/(l*tsamp); % resolution bandwidth
        
    end

  end % static methods
  
end  
