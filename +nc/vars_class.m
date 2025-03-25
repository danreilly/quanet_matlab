classdef vars_class < handle

% 11/6/2017 Dan Reilly
%
% An object of vars_class contains set of variable names and values in memory.
% You can save all the variables and values into a text file using matlab
% m-code syntax using the store() method.  And you can load that file back into
% memory using the vars_class() constructor.  You can access and change any
% variable in the set of variables.  The purpose of the class is to
% create an auxiliary variable space that is easily "serialialized", that is,
% stored to or loaded from a file.
%
% Matlab already provides the functions load() and store() that do something
% similar.  But when you do a load(), that brings those variables into the
% "workspace" of your program.  This could overwrite your program's variables,
% This is highly error prone, because sometimes you never know what might be in
% a file.  The vars_class keeps them all separate from your program.  And the
% files made by vars_class are not cryptic like a ".mat" file... you can
% double-click on them and edit them in notepad.
%
%  
% summary of main methods:
%
%   vars = vars_class(fname)
%         desc: constructor. optionally reads the specified file into memory structure vars
%         inputs: fname: string. name of file.
%         returns: the new vars_class object
%  
%   v = vars.get(name);
%   v = vars.get(name, dflt);
%         desc: looks up and returns the value of a variable  
%         inputs: name: string. name of variable.
%                 dflt: optional. default value.
%         returns: v: value of variable named name, if name is defined.
%                     If name is not defined, function returns dflt.
%                     if name is not defined and dflt not specified, function returns [].
%  
%   vars.set(name, val);
%         desc: sets the value of a variable.  If this changes the value of the
%               variable, the set of variables is marked as "dirty" (needs to be saved).
%         inputs: name: string. name of variable.
%                 val: the new value for the variable. May be string, scalar, matrix, or cell array.
%
%   vars.store(name, val);
%         desc: similar to set.  sets the value of a variable and immediatly writes
%               all variables to the file.  Intended for "non-volatile" behavior when
%               you don't want to loose the value due to an unexpected program crash
%              (or break) later on.
%         inputs: name: string. name of variable.
%                 val: the new value for the variable. May be string, scalar, matrix, or cell array.
%
%    val = vars.ask(prompt, name, dflt)
%         desc: prints prompt, followed by default value in square brackets, followed by
%               a question mark and a '>' prompt.  Gets a value from the user, which it
%               assigns to variable named name.  If user enters an empty line, it assigns
%               dflt to variable name.  
%         returns: val : value entered (or default value)
%
%   vars.save;
%   vars.save(force);
%         desc: saves values all variables the file only if any variables have been changed
%         inputs: force: optional. 1=force writing even if no variables have changed
  
  properties (Constant=true)

  end

  % instance members
  properties
    name
    list
    dirty
    dbg_lvl  % 0=none, 1=readfile, 2=get
    opt
  end

  methods (Static=true)
%  methods (Static)

    function col = datahdr2col(data_hdr, name)
    % case insensitive	     
      col = 0;
      sidx = [0 strfind(data_hdr, ' ') length(data_hdr)+1];
      for k=1:length(sidx)-1
        if (strcmpi(data_hdr(sidx(k)+1:sidx(k+1)-1), name))
          col = k;
          return;
        end
      end
      return;
    end
    

    function fprintf_val(f, val, quote_str)
    % inputs:
    %   quote_str: 0=don't quote string, 1=print single quotes around string
      import nc.*
      if (ischar(val))
        if (quote_str)
          fprintf(f,'''%s''', val);
        else
          fprintf(f,'%s', val);
        end
      elseif (iscell(val))
        vars_class.fprintf_cellarray(f, val);
      else
        vars_class.fprintf_matrix(f, val);
      end
    end
    
    function err=fprintf_matrix(f, m, opt)
      err=0;	    
      if (nargin<3)
        opt.err_for_inf_and_nan=1;
        opt.autoconvert_inf_and_nan=1;
      end            
      [h w]=size(m);
      if (any(~isfinite(m)))
        if (opt.err_for_inf_and_nan)
          fprintf('ERR: attempt to write Inf or Nan\n');
          err=1;
        end
        if (opt.autoconvert_inf_and_nan)
           m(~isfinite(m))=0;
        end
      end
      if ((h==0)||(w==0))
        fprintf(f,' []');
      elseif ((h==1)&&(w==1))
        if (isstruct(m))
          error('BUG: attempt to write struct\n');
        end
        fprintf(f,' %.9g', m);
      else
        for r=1:h
          if(r==1)
            fprintf(f,' [ ');
          else
            fprintf(f,'     ');
          end
          fprintf(f,' %.9g', m(r,:));
          if (r==h)
            fprintf(f,' ]');
          else
            fprintf(f,'\r\n');
          end
        end % loop
      end
    end

    function fprintf_cellarray(f, ca, opt)
      import nc.*
      if (nargin<3)
        opt.err_for_inf_and_nan=1;
        opt.autoconvert_inf_and_nan=1;
      end
      [h w]=size(ca);
      fprintf(f,' {');
      for r=1:h
        if(r>1)
          fprintf(f,'    ');
        end
        for c=1:w
          v = ca{r,c};
          if (ischar(v))
            fprintf(f,' ''%s''', v);
          else
            fprintf(f,' ');
            vars_class.fprintf_matrix(f, v, opt);
          end
        end
        if (r<h)
          fprintf(f,'\r\n');
        end
      end
      fprintf(f,' }');
    end
    
  end
  
  methods
    
    % CONSTRUCTOR
    function me = vars_class(name, opt)
      import nc.*
      me.name = name;
      me.list = {};
      me.dirty = 0;

      if ((nargin<2)||~isstruct(opt))
        clear opt;
        opt.foo = 0;
      end
      opt = set_if_undef(opt, 'dbg_lvl', 0);
      opt = set_if_undef(opt, 'err_for_inf_and_nan', 0);
      opt = set_if_undef(opt, 'autoconvert_inf_and_nan', 1);
      me.opt = opt;
      [f errmsg] = fopen(name, 'r');
      if (f<0)
        if (opt.dbg_lvl)
          fprintf('DBG: vars_class(): cant open file\n');
          fprintf('     %s\n', name);
        end
        return;
      end
      me.list = me.read(f);
      fclose(f);

      % nested
      function s = set_if_undef(s, fldname, val)
        if (~isfield(s, fldname))
          s = setfield(s, fldname, val);
        end
      end
    end
    
    % DESTRUCTOR
    function delete(me)
      if (me.dirty)
        fprintf('WARN: not saving changes to modified vars_class variables.\n');
        fprintf('      associated fname: %s\n', me.name);
        fprintf('      To prevent this warning, call X.save or X.undirtify\n');
        fprintf('      where X is your vars_class object\n');
      end       
    end

    function undirtify(me)
      me.dirty = 0;      
    end

    function clear_vars(me)
      me.dirty=1;
      list={};
    end

    function print_err(me, str)
      if (~isempty(me.name))
        fprintf('ERR: vars_class.read(%s): ', me.name);
      else
        fprintf('ERR: ');
      end                 
      fprintf('%s\n', str);
    end

    
    function list = read(me, f)
      me.dirty=0;
      list={};
      st=0;
      
      s_eol=0;
      s='';
      s_l=0;
      idx=1;
      ln=0;
      
      parse_init();
%      me.opt.dbg_lvl = 1;
      
      while (1)
        c = parse_skipspace();
        if (c==-1)
          break;
        elseif (c==0)
          continue;
        elseif ((c=='%')||(c==char(10)))
          parse_line();
          continue;
        else
          [name ct errmsg nidx] = sscanf(s(idx:end),'%[^ =;]');

          if (ct~=1)
            me.print_err(sprintf('expected varname at col %d', idx));
            parse_line();
            continue;
          end
          idx = idx+nidx-1;
          if (me.opt.dbg_lvl==1)
            fprintf('%d: %s =', ln, name);
          end
          var.name=name;
            
          c=parse_skipspace();
          if (c~='=')
            me.print_err(sprintf('expect =, but got %d=''%c''', c, c));
            parse_line();
            continue;
          end
          parse_get();

          var.type='m';
          var.m=[];
             
          [val ok] = parse_atom();
          if (ok)
            var.type = val.type;
            var.m = val.m;
            list{end+1}=var;
          else
            me.print_err('bad atom');
          end
          c = parse_skipspace();
          if (c<0)
            me.print_err('missing cr at eof');
            break;
          end
          if ((c~='%')&&(c~=';'))
            me.print_err(sprintf('expect end, but got %d=%c\n', c, c));
          end
          parse_line();
          if (me.opt.dbg_lvl==1)
            fprintf(';\n');
          end
        end % if
      end % while


      % NESTED
      function [val ok] = parse_matrix()
        parse_get();
        if (me.opt.dbg_lvl==1)
          fprintf(' [');
        end
        val.type = 'm';
        val.m =[];
        ok=0;
        row=1;
        while(1) % rows
          col=1;
          while(1) % cols
            c = parse_skipspace();
            if (~ischar(c) || (c==']') || (c==';') || (c==char(10)))
              parse_get();
              break;
            end
            [nval aok] = parse_atom();
            if (~aok || (nval.type~='m'))
              print_syntax_err('bad atom in matrix');
              return;
            end
            val.m(row, col)=nval.m(1,1);
            col = col + 1;
            if (parse_peek()==',')
              parse_get();
            end
          end % cols
          if (0) % me.opt.dbg_lvl==1)
            fprintf('  line %d: %s\n', ln, s(idx:end));
            fprintf('      : ');
            fprintf(' %g', val.m(row,:));
            fprintf('\n');
          end
          if (c==']')
            ok=1;
            break;
          end
          if (c==-1)
            me.print_err('expect close bracket but got EOF');
            break;
          end
          if (me.opt.dbg_lvl==1)
            fprintf('\n    ');
          end
          row=row+1;
        end % rows
        if (me.opt.dbg_lvl==1)
          fprintf(']');
        end
      end

      % NESTED
      function [val ok] = parse_cell()
        parse_get();                                    
        if (me.opt.dbg_lvl==1)
          fprintf(' {');
        end
        val.type = 'c';
        val.m=[];
        ok=0;
        row=1;
        ca={};
        while(1) % cols
          col=1;
          while(1) % row
            c = parse_skipspace();
            if (~ischar(c) || (c==';') || (c=='}')||(c==char(10)))
              parse_get();
              break;
            end
            [nval aok] = parse_atom();
            if (~aok)
              me.print_err('bad atom in cell array');
              return;
            end
            ca{row, col} = nval.m;
            col = col + 1;
            if (parse_peek()==',')
              parse_get();
            end
          end % row
          if (c=='}')
            ok=1;
            break;
          end
          if (c==-1)
            me.print_err('expect close brace, but got EOF\n');
            break;
          end
          if (me.opt.dbg_lvl==1)
            fprintf('\n    ');
          end
          row=row+1;
        end % rows
        if (me.opt.dbg_lvl==1)
          fprintf('}');
        end
        val.m = ca;
      end
          

      function skip_char()
        idx=idx+1;        
      end                          
      
      % NESTED
      function r = parse_skipspace()
        while(1)
          r=parse_peek();
          if ((r~=' ')&&(r~=char(9)))
            break;
          end
          parse_get();
        end
      end
      
      % NESTED
      function parse_init()
        ln=0;                         
        s_eol=0;
        parse_line();
      end
      
      % NESTED            
      function parse_line()
        if (s_eol)
          return;
        end
        s = fgetl(f); % removes newline chars
        if (~ischar(s))
          s_eol=1;
        else
          ln=ln+1;
          s_l=length(s);
          idx=1;
        end
      end
      
      % NESTED      
      function r = parse_get()
        r = parse_peek();
        if (s_eol)
          return;
        end
        if (idx > s_l)
          parse_line();
        else
          idx = idx+1;
        end
      end
      
      % NESTED
      function r = parse_peek()
        % uses:
        %   s   : string
        %   s_l : length of s
        %   idx : parse position
        % returns: next char or -1 (meaning eof)
        if (s_eol)
          r = -1;
        elseif (idx <= s_l)
          r = s(idx);
        else
          r = char(10);
        end
      end
    
      % NESTED
      function [val ok]=parse_atom()
        % desc: does not add to list                      
        % uses:
        % s   : string
        % s_l : length of s                       
        % idx : parse position
        ok=1;
        c = parse_skipspace();
        if (~ischar(c))
          ok = 0;
          return;
        end
        val.type='m';
        val.m=[];
        if (c=='''')
          val.type='s';
          idx=idx+1;
          idx_s=idx;
          idx_e=idx;
          while(idx<=s_l)
            c=s(idx);
            if (c=='''') 
              idx=idx+1;
              if (idx>s_l)
                break;
              end
              if (s(idx)~='''')
                break;
              end
            end
            s(idx_e)=c;
            idx_e = idx_e+1;
            idx=idx+1;
          end
          val.m = s(idx_s:idx_e-1);
          if (me.opt.dbg_lvl==1)
            fprintf(' ''%s''', val.m);
          end
           
        elseif (((c>='0')&&(c<='9'))||(c=='-')||(c=='.')||(c=='+'))
          val.type='m';
          [v ct errmsg nidx] = sscanf(s(idx:end),'%g',1);
          idx = idx+nidx-1;
          if (ct==1)
            val.m=v;
            if (me.opt.dbg_lvl==1)
              fprintf(' %g', v);
            end
          end
        elseif (c=='I')
          if ((idx+2<=s_l) && all(s(idx:idx+2)=='Inf'))
            val.type='m';
            if (me.opt.autoconvert_inf_and_nan)
              val.m=0;
            else
              val.m=Inf;
            end
            if (me.opt.dbg_lvl==1)
              fprintf(' Inf');
            end
            idx=idx+3;
            if (me.opt.err_for_inf_and_nan)
              print_syntax_err('read Inf');
            end
          else
            ok=0;
          end
        elseif (c=='N')
          if ((idx+2<=s_l) && all(s(idx:idx+2)=='NaN'))
            val.type='m';
            if (me.opt.autoconvert_inf_and_nan)
              val.m=0;
            else
              val.m=NaN;
            end
            idx=idx+3;
            if (me.opt.err_for_inf_and_nan)
              print_syntax_err('read NaN');
            end
          else
            ok=0;
          end
        elseif (c=='[')
          [val ok] = parse_matrix();
        elseif (c=='{')
          [val ok] = parse_cell();
        else
          ok=0;
          % fprintf('ERR: line %d: unrecognized char %d = %c\n', ln, c, c,);
        end
                     
      end % nested parse_atom func

      % nested
      function print_syntax_err(str)
        if (~isempty(me.name))
          fprintf('SYNTAX ERR in %s line %d char %d:\n  %s\n  ', me.name, ln, idx, s);
        else
          fprintf('SYNTAX ERR: char %d:\n  %s\n  ', idx, s);
        end
        fprintf('%s\n', str);
      end

    end % read function



    function m = get(me, name, dflt)
      if (~ischar(name) || any(strfind(name,' ')))
        fprintf('name="%s"\n', name);
        error('BUG: vars_class.get() called with bad name');
      end                         
      if (me.opt.dbg_lvl==2)
        fprintf('DBG: get(%s)\n', name);
      end
      for k=1:length(me.list)
        var=me.list{k};
        if (me.opt.dbg_lvl==2)
          var
        end
        if (strcmp(name, var.name))
          m=var.m;
          return;
        end
      end
      if (nargin==3)
        m=dflt;
      else
        m=[];
      end
    end

    function set(me, name, val)
    % inputs:
      if (~ischar(name) || any(strfind(name,' ')))
        fprintf('name="%s"\n', name);
        error('BUG: vars_class.set() called with bad name');
      end
      l = length(me.list);
      for k=1:l
        if (strcmp(me.list{k}.name, name))
          % me.list{k}.type = ty;
          if (   any(size(me.list{k}.m) ~= size(val)) ...
              || iscell(val) ... % matlab can't compare cells using equals. stupid.
              || any(any(me.list{k}.m ~= val)))
            me.list{k}.m = val;
            me.dirty=1;
          end
          return;
        end
      end
      var.name=name;
      % var.type=ty;
      var.m=val;
      me.list{l+1}=var;
      me.dirty=1;      
    end

    function copy(me, src, varslist)
    % src: vars class object to copy from
    % varslist: cell array of strings, which are names of variables
      if (~strcmp(class(src),'nc.vars_class'))
        error('src must be vars_class');
      end
      if (~iscell(varslist))
        varslist = {varslist};
      end
      for k=1:length(varslist)
        me.set(varslist{k}, src.get(varslist{k}));
      end
    end

    function set_context(me, dev)
      me.set('date', datestr(now));
      me.set('date_concise', datestr(now,'yymmdd'));
      [~, rsp] = system('hostname');
      me.set('host', regexprep(rsp,['[' 10 13 ']+'],''));
      if (nargin>1)
        me.set('dev_name', dev.devinfo.name);
        me.set('serialnum', dev.devinfo.sn);
        me.set('hwver', dev.devinfo.hwver);
        me.set('fwver', dev.devinfo.fwver);
      end
    end

    function store(me, name, val)
      if (~ischar(name) || any(strfind(name,' ')))
        fprintf('name="%s"\n', name);
        error('BUG: vars_class.store() called with bad name');
      end
      me.set(name, val);
      me.save(0);
    end

    function val = ask_yn(me, prompt, varname, dflt)
      if (nargin<4)
        dflt=1;
      end
      val = me.get(varname, dflt);
      val=nc.uio.ask_yn(prompt, val);
      me.set(varname, val);
    end


    function v_MHz = ask_MHz_or_nm(me, prompt, varname, dflt_MHz, range_MHz)
    % desc: asks for freq of light in units of either MHz or nm.
      C_mps = 299792485.0; % speed of light m/s
      if (nargin<5)
        range_MHz=[];
      end
      dflt_MHz = me.get(varname, dflt_MHz);
      while(1)
        v = dflt_MHz;
        fprintf('%s freq (MHz) or wl (nm) [%dMHz = %.3fnm] > ', ...
                prompt, round(v), C_mps/(v*1e6)*1e9);
        str = input('','s');
        [t ct]= sscanf(str, '%g');
        if (ct)
          v = t(1);
        end
        if (v<9999) % it's nm, so convert to MHz
          v_MHz = C_mps/(v*1e-9)/1e6;
        else
          v_MHz = v;
        end
        if (isempty(range_MHz) || ((v_MHz >= range_MHz(1))&&(v_MHz <= range_MHz(2))))
          break;
        end
        fprintf('ERR: freq %dMHz out of range\n', v_MHz);
      end
      me.set(varname, v_MHz);
    end


    function val = ask_dur_s(me, prompt, varname, dflt)
      if (nargin<4)
        dflt=1;
      end
      val = me.get(varname, dflt);
      val=nc.uio.ask_dur_s(prompt, val);
      me.set(varname, val);
    end

    
    function val = ask(me, prompt, name, dflt)
      import nc.*
      if (~ischar(name) || any(strfind(name,' ')))
        fprintf('name="%s"\n', name);
        error('BUG: vars_class.ask() called with bad name');
      end
      if (nargin<4)
        dflt=0;
      end
      dflt=me.get(name,dflt);
      val=uio.ask(prompt, dflt);
      me.set(name, val);
    end            


    function v=ask_choice(me, prompt, choices, varname)
      v = nc.uio.ask_choice(prompt, choices, me.get(varname, choices(1)));
      me.set(varname, v);
    end

    function [port idn baud_Hz] = ask_port(me, devnames, port_varname, bauds_Hz)
      import nc.*                                          
      port = me.get(port_varname,'');
      [port idn baud_Hz] = nc.uio.ask_port(devnames, port, bauds_Hz);
      if (~isempty(port))
        me.set(port_varname,port);
      end
    end



    function dirname = ask_dir(me, desc, varname)
% desc: description of directry, used in visual prompt to user.
% varname: name of variable used for default directory
% returns: dirname: has no trailing slash unless its the root slash
      if (nargin<3)
        desc='';
      end
      dirname = me.get(varname,'');
      if (~isempty(dirname))
        fprintf('prior %s dir:\n  %s\n', desc, dirname);
        if (~nc.uio.ask_yn('use it?', 1))
          dirname='';
        end
      end
      if (isempty(dirname))
        dirname = uigetdir('\', sprintf('... select %s directory', desc));
        if (isempty(dirname))
          fprintf('you chose nothing\n');
        else
          fprintf('you chose:\n %s\n', dirname);
        end
      end
      if (~isempty(dirname))
        idx = strfind(dirname,':');
        if (isempty(idx))
          idx=1;
        else
          idx = idx(1)+1;
        end
        if ((length(dirname(idx:end))>1)&&(dirname(end)=='\'))
          dirname=dirname(1:end-1);
        end
      end
      me.set(varname, dirname);
    end

    function fn_full = ask_fname(me, desc, dflt_fname_var, multi)
      if (nargin<3)
        desc='';
      end                               
      if (nargin<4)
        multi=0;
      end
      multi_ca={'off','on'};
      fn_full = me.get(dflt_fname_var,'');
      pname='';
      if (~isempty(fn_full))
        if (~iscell(fn_full) || (length(fn_full)==1))
          if (iscell(fn_full))
            str = fn_full{1};
          else
            str = fn_full;
          end
          [pname fname ext] = fileparts(str);
          fprintf('prior %s file:\n  %s\n', desc, str);
          fprintf('use it?');
        else
          fprintf('prior %s files:\n', desc);
          [pname f e] = fileparts(fn_full{1});
          for(k=1:length(fn_full))
            fprintf('  %s\n', fn_full{k});
          end
          fprintf('use them?');
        end
        if (~nc.uio.ask_yn(1))
          fn_full='';
        end
      end
      if (isempty(fn_full))
        if (isempty(pname))
          pname = me.get('pname');
        end
        [fname, pname, fidx] = uigetfile([pname '/*.*'], ...
                                         ['  ' sprintf('... select %s file', desc)], ...
                                         'MultiSelect', multi_ca{logical(multi)+1});
        if (fidx==0)
          return;
        end % nothing selected
        if (iscell(fname))
          fn_full = cell(size(fname));
          for k=1:length(fname)
            fn_full{k}=[pname fname{k}];
          end
        else
          fn_full = [pname fname];
          fprintf('you chose:\n %s\n', fn_full);
        end
        me.set(dflt_fname_var, fn_full);
      end
    end

    
    function save(me, force)
      import nc.*
      if (nargin<2)
        force=0; % optional param
      end
      if (~force && ~me.dirty)
        return;
      end
%      tic
      me.dirty = 0;
      % fprintf('DBG: vars_class.save(%s)\n', me.name);
      [path name ext] = fileparts(me.name);
      nc.fileutils.ensure_dir(path);
      [f errmsg] = fopen(me.name, 'w');
      if (f<0)
        fprintf('WARN: cant open %s\n', me.name);
        fprintf('      %s\n', errmsg);
        return;
      end
      me.printout(f);
      fclose(f);
      me.dirty = 0;
%      fprintf('DBG: vars_class.store time: ');
%      toc
    end

    function printout(me, f)
      import nc.*
      dbg=0;
      if (nargin<2) f=0; end
      for k=1:length(me.list)
        var = me.list{k};
        if (~ischar(var.name))
          fprintf('BUG: var.name not a char');
          var
          continue;
        end
        if (dbg)
          fprintf('DBG: %s\n', var.name);
        end
        fprintf(f, '%s =', var.name);
        if (ischar(var.m))
          fprintf(f,' ''%s'';\r\n', var.m);
          % fprintf('DBG: sav %s\r\n', var.m);
        elseif (iscell(var.m))
          vars_class.fprintf_cellarray(f, var.m, me.opt);
          fprintf(f,';\r\n');
        else
          if (vars_class.fprintf_matrix(f, var.m, me.opt))
	    fprintf('ERR: vars_class variable %s\n', var.name);
          end	       
          fprintf(f,';\r\n');
        end

      end %loop
    end


        
                                        
    function ch_wavelens = ask_wavelens_nm(me, rngs_var_name, ch_name, chans, dflt)
% desc: prompts user to specify one or more sets of ranges of wavelengths
%       for one or more "channels" (as appropriate).
%       Different channels might get the same or different sets of wavelengths.
% inputs:
%   rngs_var_name: name of variable containing a default specification of
%         multiple sets of ranges.  This is an nx3 matrix.
%         Each row of three numbers is one of three kinds of specifiers.
%           single wavelength     :  [wl_nm           0         0]
%           range stepping by one :  [wl_start_nm  wl_end_nm    0]
%           range step by incr    :  [wl_start_nm  incr_nm  wl_end_nm 0]
%   chans: vector of channel indicies on which to ask for wavelengths.
%   dflt: a default range specified by calling function that user can
%         choose using the 'd' option.
% sets:
%   rngs_var_name: set to what user just entered
% returns:
%   ch_wavelens: cell array of vectors of wavelengths in nm
      import nc.*
      rngs = me.get(rngs_var_name);
      if (isempty(ch_name))
        ch_name='chan';
      end
      if(nargin<5)
        dflt=[];
      end

      fprintf('\n      When entering wavelength ranges below, on each line enter ONE of these formats:\n');
      fprintf('          <wavelen>             = one wavelength in nm.  you may use floating point\n');
      fprintf('          <start>:<step>:<end>  = range of wavelengths\n');
      fprintf('          <start>:<end>         = range of wavelenghs stepping by one nm\n');
      fprintf('          0                     = 0 indicates the end\n');
      if (~isempty(dflt))
        fprintf('          d                     = use default range %s\n', uio.range_m2str(dflt));
      end                   
      fprintf('          e                     = e indicates the end also\n');
                   
      ch_wavelens=cell(max(chans),1);

      rngs_o=[];
      chans_l = length(chans);
      for c_i=1:chans_l
        ch = chans(c_i);
        rngs_l = size(rngs,1);
        if (size(rngs,2)<6)
          rng_c = 1:3;
        else
          rng_c = (ch-1)*3+(1:3);
        end

        rngs_o_l=0;
        if (c_i>1)
          fprintf('      Are the wavelengths for %s %d the same as for %s %d?', ...
                     ch_name, ch, ch_name, chans(c_i-1));
          if (uio.ask_yn(1))
            ch_wavelens{c_i}=ch_wavelens{c_i-1};
            continue;
          end
        end
        wlns=[];
        rng_i=0;
        fprintf('\n      Enter ranges (nm) for %s %d, if any\n', ch_name, ch);
        while (1)
          if (rng_i+1>rngs_l)
            r=[];
          else
            idx=find(rngs(rng_i+1,rng_c)==0,1)-1+rng_c(1); % first zero
            if (isempty(idx))
              r=rngs(rng_i+1,rng_c);
            else
              r=rngs(rng_i+1,rng_c(1):(idx-1));
            end
          end
          [r e] = uio.ask_range(r, dflt);
          if (isempty(r) || ~r(1))
            break;
          end
          rngs_o_l=rngs_o_l+1;
          rngs_o(rngs_o_l,(ch-1)*3+(1:3))=0;
          rngs_o(rngs_o_l,(ch-1)*3+(1:length(r)))=r;
          rng_i=rng_i+1;
          if (length(r)==1)
            wl = r(1);
            wlns=[wlns r(1)];
          elseif (length(r)==2)
            wl=r(1);
            while(wl<=r(2)+1e-8)
              wlns=[wlns wl];
              wl=wl + 1;
            end
          elseif (length(r)==3)
            wl=r(1);
            while(wl<=r(3)+1e-8)
              wlns=[wlns wl];
              wl=wl + r(2);
            end
          end
          if (e)
            break;
          end
        end
        wlns = unique(wlns);
        ch_wavelens{ch}=wlns;
      end
      me.set(rngs_var_name, rngs_o);
    end

    function val = ask_col_choice_in_cell_per_key(me, prompt, cellvarname, key_str, col, choices, dflt)
      import nc.*
      v = me.get(cellvarname,{});
      h = size(v,1);
      r = 0;
      if (~iscell(v))
        fprintf('WARN: var %s is not a cell!\n', cellvarname);
        uio.pause();
      end
      if (~isempty(v))
        for r2=1:h
          if (strcmp(v{r2,1},key_str))
            r=r2;
            break;
          end
        end
      end
      if (r==0)
        r=h+1;
        v{r,1}=key_str;
      end
      val = dflt;
      if (size(v,2)>=col)
        val = v{r,col};
      end
      if (ischar(dflt) && isempty(val))
        val = '';
      end
      val = uio.ask_choice(prompt, choices, val);
      v{r,col} = val;
      me.set(cellvarname, v);
    end
      
    function val = ask_col_in_cell_per_key(me, prompt, cellvarname, key_str, col, dflt)
      % inputs:                                          
      %   varname: name of variable that is an Nx2 cell array of strings
      % see also: set_cell_per_key
      import nc.*
      v = me.get(cellvarname,{});
      h = size(v,1);
      r = 0;
      if (~iscell(v))
        fprintf('WARN: var %s is not a cell!\n', cellvarname);
        uio.pause();
      end
      if (~isempty(v))
        for r2=1:h
          if (strcmp(v{r2,1},key_str))
            r=r2;
            break;
          end
        end
      end
      if (r==0)
        r=h+1;
        v{r,1}=key_str;
      end
      val = dflt;
      if (size(v,2)>=col)
        val = v{r,col};
      end
      if (ischar(dflt) && isempty(val))
        val = '';
      end
      val = uio.ask(prompt, val);
      v{r,col} = val;
      me.set(cellvarname, v);
    end
    
    function val = get_in_cell_per_key(me, varname, key_str, dflt)
    % inputs:                                          
    %   varname: name of variable that is an Nx2 cell array of strings
    % see also: set_cell_per_key
      v = me.get(varname,[]);
      if (isempty(v))
        val = dflt;
      elseif (iscell(v))
        for r=1:size(v,1)
          if (strcmp(v{r,1},key_str))
            val = v{r,2};
            return;
          end
        end
        val = dflt;
      else
        val = v;
      end
    end

    function set_in_cell_per_key(me, varname, key_str, val)
    % inputs:
    %   varname: name of variable that is an Nx2 cell array of strings
    %   val: could be a string or matrix
    % see also: lookup_cell_per_key
      % fprintf('ser per key %s: %s = %s\n', key_str, varname, val_str);
      v = me.get(varname);
      if (~isempty(v)&&iscell(v))
        for r=1:size(v,1)
          if (strcmp(v{r,1},key_str))
            v{r,2} = val;
            me.set(varname, v);
            return;
          end
        end
        v{end+1,1}=key_str;
        v{end,2}=val;
        me.set(varname, v);
        return;
      end
      v = {key_str, val};
      me.set(varname, v);
    end


      
  end % instance methods
  
end  
