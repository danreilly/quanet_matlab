classdef uio
% functions to do simple io with user in the course of conducting a test

  properties (Constant=true)
    SPIN = '-\|/';
  end
  properties
    spin_i
    progress_l
  end

  methods (Static=true)

    function set_always_use_default(en)
      global UIO_ALWAYS_USE_DEFAULT
      UIO_ALWAYS_USE_DEFAULT=en;
    end

    function use_dflt = always_use_default
      global UIO_ALWAYS_USE_DEFAULT
      if (exist('UIO_ALWAYS_USE_DEFAULT','var') && ~isempty(UIO_ALWAYS_USE_DEFAULT))
        use_dflt = UIO_ALWAYS_USE_DEFAULT;
      else
        use_dflt=0;
      end
    end


    function pause(msg)
      if (nargin<1)
	msg='hit enter';
      end
      fprintf('%s >', msg);
      pause;
      fprintf('\n');
    end

    function str = dur(n,prec)
% dur converts a number in seconds
% to a string with "commensurate" units.
      if (nargin<2)
        prec=1;
      end             
      f=sprintf('%%.%df%%s', prec);

      if (abs(n)<1e-12)
	str = sprintf(f, n*1e15,'fs');
      elseif (abs(n)<1e-9)
	str = sprintf(f, n*1e12,'ps');
      elseif (abs(n)<1e-6)
	str = sprintf(f, n*1e9, 'ns');
      elseif (abs(n)<1e-3)
	str = sprintf(f, n*1e6, 'us');
      elseif (abs(n)<1)
	str = sprintf(f, n*1e3, 'ms');
      elseif (abs(n)<60)
	str = sprintf(f, n, 's');
      elseif (abs(n)<60*60)
	str = sprintf(f, n/60, 'min');
      else
	str = sprintf(f, n/(60*60), 'hr');
      end
    end

    function s2=short_exp(s1)
    % The matlab sprintf('%e', n) function puts leading zeros
    % in front of the exponent. This deletes those leading zeros.
    % Also deletes unnecesary + after the E.  If entire exponent is
    % zero, this deletes the e also.
    % returns: s2 : string
      st=0;
      s2=s1;
      sgn=0;
      k2=1; % write index
      for k1=1:length(s1)
        c=s1(k1);
        s2(k2)=c;
        k2=k2+1;
        switch(st)
          case 0
	    if (c=='e') st=1; end
          case 1
            sgn=1;
            if (c=='+')
	      k2=k2-1;
	      st=2;
            elseif (c=='0')
	      k2=k2-1;
	      st=3;
            elseif (c=='-')
              sgn=-1;
              st=2;
            else
              st=0;
            end
          case 2
            if (c=='0')
	      k2=k2-1;
	      st=3;
            else
              st=0;
            end
          case 3 % eliminating zeros
            if (c=='0')
	      k2=k2-1;
            elseif ((c>='1')&&(c<='9'))
	      st=0;
            else % exponent was all zeros.  Delete the 'E' also!
	      k2=k2-1-(sgn<0);
              s2(k2-1)=c;
              st=0;
            end
        end
      end

      if (st==3) % exponent was all zeros.  Delete the 'E' also!
        k2=k2-1-(sgn<0);        
        st=0;
      end

      s2=s2(1:k2-1);
    end

    function s=signed_str(n)
    % converts to string and always show sign + or -
      if (n<0)
        s=sprintf('%d',n);
      else
        s=sprintf('+%d',n);
      end
    end
                   
    function t = sci(n, prec)
    % sci converts a number to string in scientific notation
    %  sci(n, prec) exactly prec digits (zero pad) after the decimal point
    %  sci(n)       about 6 digits overall
      if (~isscalar(n))
	error(sprintf('n must be scalar but instead has numel %d', numel(n)));
      end
      if ((nargin>1) && ~isscalar(prec))
	error('prec must be scalar.');
      end
      if (n==0)
	e=0;
      else
	e = floor(log10(abs(n)));
      end
      e2 = floor(e/3);
      rs = {'f', 'p', 'n', 'u', 'm', '', 'k', 'M', 'G', 'T'};
      n2 = n / 10^(e2*3);
      if ((e2+6 >=1) && (e2+6 <= length(rs)))
	if (nargin==2)
	  fmt = sprintf('%%.%df%s', prec, rs{e2+6});
	else
	  fmt = sprintf('%%g%s', rs{e2+6});
	end
	t = sprintf(fmt, n2);
      else
	if (nargin==2)
	  fmt = sprintf('%%.%dg', prec);
	else
	  fmt = sprintf('%%g');
	end
	t = sprintf(fmt, n);
      end
    end
    
    function r=ask_yn(p1, p2)
      % use: ask_yn(prompt, def)
      %      ask_yn(prompt)
      %      ask_yn(def)
      % inputs:
      %     prompt: char string
      %     def: -1 = answer required, 0=default n, 1=default y  
      import nc.*
      if (nargin<2)
  	if (ischar(p1))
          prompt=p1;
          def=-1;
        else
	  def=p1; % default
	  prompt=''; % prompt
        end
      else
        prompt=p1;
        def = p2;
      end
      if (isempty(def))
        def=-1;
      end

      while(1)
        if (~isempty(prompt))
          fprintf('%s ', prompt);
        end
        fprintf(' (y|n)');
        if (def==1)
          fprintf(' [y]');
        elseif (def==0)
          fprintf(' [n]');
        end
        fprintf(' > ');
        if ((def>=0) && nc.uio.always_use_default)
          if (def==1)
            fprintf('y\n');
          else
            fprintf('n\n');
          end
          r = def;
  	      return;
        end
        str = lower(input('','s'));
        if (strcmp(str,'y'))
          r=1;
          return;
        elseif (strcmp(str,'n'))
          r=0;
          return;
        elseif ((def>=0)&&isempty(str))
          r = def;
          return;
        end
      end
    end
    
    function v=ask(p1, p2)
      % ask(def)
      % ask('prompt', dflt) dflt may be num or string
      if ((nargin==2)&&ischar(p1))
	fprintf('%s', p1);
	def = p2;
      else
	def = p1;
      end

      if (~isempty(def))
        if (ischar(def))
          fprintf(' [%s]', def);
        elseif (length(def)>1)
          fprintf(' [%s]', sprintf(' %g', def));
        else
          fprintf(' [%g]', def);
        end
      end
      fprintf(' > ');

      if (~isempty(def) && nc.uio.always_use_default)
        if (ischar(def))		
          fprintf('%s\n', def);
        elseif (length(def)>1)
          fprintf(' %g', def);
	  fprintf('\n');
        else
          fprintf('%g\n', def);
        end
        v=def;
        return;
      end

      str = input('', 's');
      if (ischar(def)&&~isempty(str))
        v=str;
      else
        [v ct]= sscanf(str,'%g');
        if (~ct)
          v = def;
        end
      end
    end

    function v_s=ask_dur_s(p1, p2)
    % asks for a time or duration.  User may use a suffix to indicate time units.
      if ((nargin==2)&&ischar(p1))
	fprintf('%s', p1);
	def_s = p2;
      else
	def_s = p1;
      end
      fprintf(' (use suffix h,m,s,ms,us,ns,etc)');

      if (~isempty(def_s) && nc.uio.always_use_default)
        fprintf(' > %s\n', nc.uio.dur(def_s));
        v_s = def_s;
	return;
      end

      if (~isempty(def_s))
        fprintf(' [%s]', nc.uio.dur(def_s));
      end
      fprintf(' > ');


      str = input('', 's');
      if (~isempty(str))
	ca = regexp(str,'([\d.eE+-]+|[a-zA-Z]+)','match');
	m=1;
	if (length(ca)>1)
	  if (strcmp(ca{2},'s'))
            m=1;
          elseif (strcmp(ca{2},'m')||strcmp(ca{2},'min'))
            m=60;
          elseif (strcmp(ca{2},'h') || strcmp(ca{2},'hr'))
            m=60*60;
          elseif (strcmp(ca{2},'ms'))
            m=1e-3;
          elseif (strcmp(ca{2},'us'))
            m=1e-6;
          end
        end
	if (length(ca)>0)
          [v ct]= sscanf(ca{1},'%g');
          if (length(v)==1)
            v_s = v * m;
  	    return;
	  end
        end
      end
      v_s = def_s;
    end

    function v=ask_choice(prompt, choices, def)
    % def : optional default. if not spec, is first choice.
      if ((nargin<3)||isempty(strfind(choices, def)))
        def = choices(1);
      end
      if (~isempty(def) && nc.uio.always_use_default)
        fprintf(' > %s\n', def);
        v = def;
	return;
      end
      while (1)
        fprintf('%s (%s) [%s] > ', prompt, choices, def);
        v = input('', 's');
        if (isempty(v) && ~isempty(def))
          v = def;
  	  return;
        end
	if ((length(v)==1)&&~isempty(strfind(choices, v)))
  	  return;
        end
      end
    end

    function fn_full = ask_fname(pname, desc, multi)
      if (nargin<2)
        desc='';
      end                               
      if (nargin<3)
        multi=0;
      end
      multi_ca={'off','on'};
      fn_full='';
      [fname, pname, fidx] = uigetfile([pname '/*.*'], ...
                                       ['  ' sprintf('... select %s file', desc)], ...
                                       'MultiSelect', multi_ca{logical(multi)+1});
      if (fidx==0)
        return;
      end % nothing selected
      if (iscell(fname))
        fn_full = cell(size(fname));
        for k=1:length(fname)
          fn_full{k}=[name fname{k}];
        end
      else
        fn_full = [pname fname];
        fprintf('you chose:\n %s\n', fn_full);
      end
    end


    function [port idn baud_Hz] = ask_port(names, port, bauds_Hz)
    % desc:      
    %   closes the port before returning
    % inputs:
    %    names: string or cell array of strings.  list of device
    %           names or <func> parts of NuCrypt identify response.
    %    port: default port
    %    bauds_Hz: vector of baud rates to try in Hz
    % returns:
    %     port: port chosen. empty if "skipped"
    %     idn: NuCrypt response structure to "i" command.
    %     baud_Hz: baud actually used
      import nc.*
      % fprintf('dev ask open %s %s\n', name, port);
      baud_Hz=0;
      if (~iscell(names))
        names = {names};
      end
      names_str = names{1};
      if (length(names)>1)
	for k=2:length(names)-1
  	  names_str = [names_str ', ' names{k}];
        end
  	names_str = [names_str ' or ' names{end}];
      end
      while(1)
        irsp='';
        if (~isempty(port)&&~strcmp(port,'skip'))
          fprintf('attempting to contact device at %s\n', port);
	  for k=1:length(bauds_Hz)
	    baud_Hz = bauds_Hz(k);
	    ser = ser_class(port, baud_Hz);
	    ok=0;
	    if (ser.isopen)
	      idn = ser.get_idn_rsp;
	      ser.close;
              if (~isempty(idn.irsp))
		fprintf('device on %s identifies as ', port);
		uio.print_all(idn.irsp);
		for k=1:length(names)
		  name = names{k};
                  if (strcmpi(idn.name, name))
                    ok=1;
		    break;
                  end
		end % for names
                ok = uio.ask_yn(sprintf('  use this as a %s?', names_str), ok);
	      end % if idn rsp
  	    end % if open
	    ser=[];
    	    if (ok)
    	      return;
    	    end
	  end % for k bauds
  	  port='';
        end % if port not mt
        fprintf('  enter serial port of %s [skip]> ', names_str);
        port = input('', 's');
        if (isempty(port))
          idn=[];
          baud_Hz=0;
          break;
        end
      end
    end


    function str = range_m2str(m)
      if (length(m)>=3)
        str=sprintf('%g:%g:%g', m(1:3));
      elseif (length(m)==2)
        str=sprintf('%g:%g', m);
      elseif (length(m)==1)
        str=sprintf('%g', m);
      else
        str='';
      end
    end

    function [v e]=ask_range(def, dflt2)
     % def: default. User hits enter and this is selected.  Displayed at prompt.
     % dflt2: secondary default, selected by "d".  Optional.      
      import nc.*
      e=0;
      if (nargin<2)
        dflt2=[];
      end
      pr = uio.range_m2str(def);
      while(1)
        v=[];
        fprintf(' [%s] > ', pr);
        str = input('', 's');
        if (isempty(str))
          v=def;
          return;
        end
        str_l = length(str);
        j=1;
        if (strcmpi(str,'e'))
          v=[];
          e=1;
          return;
        elseif (~isempty(dflt2) && strcmpi(str,'d'))
          v = dflt2; % secondary default
          e = 1;
          return;
        end
        for k=1:4
          if (j>str_l)
            return;
          end
          [va ct msg nj]= sscanf(str(j:end),' ');
          if (ct>0)
            j=j+nj-1;
          end
          if (j>str_l)
            return;
          end
          
          [va ct msg nj]= sscanf(str(j:end),'%g',1);
          if (ct<1)
            [va ct msg nj]= sscanf(str(j:end),'%c',1);
            if (ct<1) 
              fprintf('ERR: failed to parse: %s\n', msg);
              break;
            end
            fprintf('ERR: syntax. expected a number, but got a %c\n', va);
            break;
          end
      
          v(k)=va;
          j=j+nj-1;
          if (j>str_l)
            return;
          end
          [va ct msg nj]= sscanf(str(j:end),' %c',1);
          if (ct==0)
            return;
          end
          if (ct<0) 
            fprintf('ERR: failed to parse: %s\n', msg);
            break;
          end
          if (va~=':')
            fprintf('ERR: syntax. bad char %c\n', va);
            break;
          end
          if (k==3)
            fprintf('ERR: syntax. too many colons\n');
            break;
          end 
          j=j+nj-1;
        end
      end
    end
    
    function v=ask_str(p1, p2)
      if (nargin==2)
     	fprintf('%s', p1);
    	p1 = p2; % p1 is default
      end
      fprintf(' [%s] > ', p1); 
      v = input('', 's');
      if (isempty(v))
        v = p1; % default
      end
    end

    function print_matrix(name, m)
    % usage: print_matrix(name, m)
    % desc: Prints a 2 dimensional matrix as multiple rows of numbers separated
    %   by spaces. Each number is printed concisely to a sensible precision using
    %   %g. This is different from the way Matlab does it, which is to sometimes
    %   print a scaling factor, which be hard to read if the elements differ by
    %   orders of magnitude.
    % inputs: name: a string to print out in front
    %         m: the matrix to print
      if (~ischar(name)) error('nc.uio.print_matrix(): name must be string'); end
      fprintf('%s = ', name);
      if (ndims(m)>2) error('nc.uio.print_matrix(): m must be 2 dimensional'); end
      for r=1:size(m,1)
    	fprintf(' %g', m(r,:));
	    fprintf('\n');
      end
    end

    function print_wrap(str, w)
      if (nargin<2)
	    w = 80;
      end
      str = regexprep(str,'\\n', char(10));
      str = regexprep(str,'\\t', char(9));
      str_l = length(str);
      idxs = strfind(str,' ');
      l=1;
      is=1;
      while(is<=str_l)
	iei=find(idxs<is+w, 1, 'last');
	if ((is+w-1 >= str_l) || isempty(iei) || (idxs(iei)<=is))
	  ie = min(str_l, is+w-1);
        else
	  ie = idxs(iei)-1;
        end
	fprintf('%s\n', str(is:ie));
	is=ie+1;
	if ((is <= str_l) && (str(is)==' '))
          is=is+1;
        end
      end
    end


    function print_all(str)
      fprintf('"');
      for k=1:length(str)
	c = str(k);
%	if (c==10)
%	  fprintf('\n');
%      elseif (c==13)
%      fprintf('\\r');
 	if ((c<' ')||(c>char(126)))
          fprintf('<%d>', c);
        else
	  fprintf('%c', c);
	end
      end
      fprintf('"\n');
    end

  end
  
  methods

    % constructor
    function me = uio()
      me.set_always_use_default(0);
      me.spin_i=1;
      me.progress_l=0;
    end

    function me = delete()
      me.set_always_use_default(0);
    end

    function me = progress_clr(me);
%      fprintf('\nDBG: clr %d\n', me.progress_l);
      for k=1:me.progress_l
        fprintf('\b');
      end
      me.progress_l=0;
    end

    function me=progress_print(me, pct)
      me = me.progress_clr;
      if (pct==100)
        fprintf('  progress %5.2f%%\n', 100);
      else
        prog_txt = sprintf('%s progress %5.2f%%', me.SPIN(me.spin_i), pct);
        fprintf('%s', prog_txt);
        me.progress_l = length(prog_txt);
        me.spin_i= mod(me.spin_i,4) + 1;
      end
    end
  end

end  
      
