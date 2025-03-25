classdef report_class < handle
% used for making pdf reports via LaTeX
% You must have LaTeX installed.  (Install MikTeX)

  properties (Constant=true)
    JUNK = 0;
  end
  
  % instance members
  properties
    latex
    fname
    tmp_dir
    tmp_fname
    tmp_fid
    img_ctr
    table_width
    table_col
  end

  methods

    % CONSTRUCTOR
    function me = report_class(fname, title)
      import nc.*
%      me.latex = 'C:\Users\reilly\AppData\Local\Programs\MiKTeX\miktex\bin\x64\pdflatex.exe';
      me.latex = 'pdflatex';
      [st rsp] = dos([me.latex ' -version']);
      if (st)
        fprintf('Install MikTeX from: https://miktex.org\n');
        error('pdflatex not in path.  Did you install MikTex (from https://miktex.org)');
      end
      me.fname = fname; % final name of report
      % temporary files for the report go into the report directory
      report_fname = fileutils.uniquename('C:\Temp\report0');
      me.tmp_dir = ['C:\Temp\' report_fname];
      fileutils.ensure_dir(me.tmp_dir);

      me.tmp_fname = [me.tmp_dir '\report.tex'];
      me.tmp_fid = fopen(me.tmp_fname, 'w+');
      me.img_ctr = 0;

      if (me.tmp_fid<=0)
        error(sprintf('ERR: cant write file\n  %s', me.tmp_fname));
        sum_f=1;
      else
        % 8.5 - .75*2 = 7" wide usable space,
        fprintf('writing %s\n', me.tmp_fname);
        me.write_nl('\documentclass{report}');
        me.write_nl('\author{}');
        me.write_nl('\usepackage[margin=0.75in]{geometry}');
        me.write_nl('\usepackage{graphicx}');
        me.write_nl('\usepackage{tcolorbox}');
        me.title(title);
        me.write_nl('\begin{document}');
      end
    end

    % DESTRUCTOR
    function delete(me)
      me.close();
    end

    function title(me, str)
      me.write_nl(sprintf('\\title{%s}', str));
    end
    
    function bold(me, str)
      if (nargin<2)
        me.write_nl('\ttfamily');
      else
        me.write(sprintf('\\textbf{%s}', str));
      end
    end

    function verbatum(me, str)
      me.write(sprintf('\\verb"%s"', str));
    end
    
    function font_monospace(me, str)
      if (nargin<2)
        me.write_nl('\ttfamily');
      else
        me.write(sprintf('\\texttt{%s}', str));
      end
    end

    function font_serif(me, str)
      if (nargin<2)
        me.write_nl('\sffamily');
      else
        me.write(sprintf('\\textsf{%s}', str));
      end
    end
    
    function ctr_start(me)
      me.write_nl('\begin{center}');
    end
    
    function ctr_end(me)
      me.write_nl('\end{center}');
    end
    
    function hdr_start(me)
      me.write(sprintf('\\begin{center} \\Large\n'));
    end
    
    function hdr_end(me)
      me.write(sprintf('\\end{center}\n'));      
    end
    
    function write(me, str)
    % inserts string into report... this is latex
      if (me.tmp_fid>0)
        % latex interprets percent as begin of comment
        % dont know why I need extra slash below:
        str = regexprep(str, '%', '\\%');
        fprintf(me.tmp_fid, '%s', str);
      end
    end

    function writeln(me, str)
      if (nargin<2)
        str='';
      end
      me.write(str);
      me.write_nl('\\');
    end
    
    function write_nl(me, str)
      if (nargin<2)
        str='';
      end
      me.write([str char(10)]);
    end
    
    function minipage_start(me)
      me.write_nl('\begin{minipage}{\textwidth}');
    end
    
    function minipage_end(me)
      me.write_nl('\end{minipage}');
    end

    function box_start(me, col)
      if (nargin<2)
        col='white';
      end
      me.write_nl(sprintf('\\begin{tcolorbox}[colback=%s]', col));
    end
    
    function box_end(me)
      me.write_nl('\end{tcolorbox}');
    end
    
    function table_start(me, label, title, hdr)
% desc: starts a table      
% label: I forget. maybe some latex thing. Maybe For hyperlinks?
% title: string to display above the table      
% hdr: cell array of strings, one for each column.      
      me.write_nl('\begin{table}[ht!]');
      me.write_nl('  \begin{center}');
      me.write_nl(sprintf('    \\caption{%s}', title));
      me.write_nl(sprintf('    \\label{%s}', label));

      me.table_width = length(hdr);

      fmt = repmat('c ', 1,me.table_width);
      
      me.write_nl(sprintf('    \\begin{tabular}{%s}', fmt));

      for k=1:length(hdr)
        me.bold(hdr{k});
        if (k<length(hdr))
          me.write(' & ');
        end
      end
      me.writeln();
      me.write_nl('      \hline');
      me.table_col = 1;
    end
    
    function table_cell(me, str)
      if (me.table_col==1)
        me.write('      ');
      end
      me.write(str);
      if (me.table_col==me.table_width)
        me.write_nl('\\');
        me.table_col = 1;
      else
        me.write(' & ');
        me.table_col = me.table_col+1;
      end
    end
    
    function table_end(me)
      me.write_nl('    \end{tabular}');
      me.write_nl('  \end{center}');
      me.write_nl('\end{table}');
      me.write_nl();
    end
    
    function insert_plot(me, fig, size_in, wid_in)
    % desc: inserts current plot into report
    % usage:
    %   report.insert_plot(fig) - inserts plot
    %   report.insert_plot(fig, size_in) -- sets fig size, then inserts plot.
    %   report.insert_plot(fig, size_in, wid_in) -- sets fig size,
    %                             then scales it to specified width and inserts it
    %
    % size_in: [wid height] - size to set figure before insertion
    %                         If emtpty, figure is not changed.
    % wid_in: width to use in pdf doc ( can be different).
      import nc.*
      
      if (me.tmp_fid>0)
        if (nargin<4)
          wid_in = [];
        end
        set(fig,'units','inches');
        p=get(fig,'Position');

        % change figure if that is specified
        if (nargin<3)
          size_in=p(3:4);
        elseif (~isempty(size_in))
          %      size_cm = size_in * 2.54;
          p(3:4)=size_in;
          set(fig,'Position',p);
        end
        
        if (isempty(wid_in))
          wid_in = size_in(1);
        end
        wid_cm = wid_in * 2.54;
        me.img_ctr = me.img_ctr+1;
        img_fname = sprintf('img%03d.png', me.img_ctr);
        me.write(sprintf('\\includegraphics[width=%fcm,keepaspectratio]{%s}\n', wid_cm, img_fname));
        ncplot.save(fig, [me.tmp_dir '\' img_fname]);
      end
    end

    function close(me)
      if (me.tmp_fid>0)
        me.write_nl('\end{document}');
        fclose(me.tmp_fid);
      end
      me.tmp_fid=0;
    end
    
    function finish(me, dont_del)
      import nc.*
      if (nargin<2)
        dont_del=0;
      end
      if (me.tmp_fid>0)
        me.close();
        fprintf('running LaTeX to make pdf\n');
        [f_path f_root f_ext] = fileparts(me.fname);
        cmd = sprintf('%s -quiet -include-directory="%s" -output-directory="%s" report.tex', ...
                      me.latex, me.tmp_dir, me.tmp_dir);
        if (dont_del)
          uio.print_all(cmd);
        end
        status = system(cmd);
        if (status)
          fprintf('ERR: pdflatex returned error code %d\n', status);
        end
        copyfile([me.tmp_dir '\report.pdf'], me.fname);
        fprintf('wrote %s\n', [f_root f_ext]);
        if ((nargin<2)||(~dont_del))
          delete([me.tmp_dir '\*']);
          [status msg]=rmdir(me.tmp_dir);
          if (~status)
            fprintf('ERR: could not delete temp files\n%s\n', msg);
            uio.pause();
          end
        end
      end
    end
 
  end

end
