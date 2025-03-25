classdef fileutils

  % Note: dont forget you can also use these inherent matlab functions:
  %    [pname fname ext] = fileparts(full_fname);
  %    str = fullfile(path, name, ...)
  %    filesep()
  
  methods (Static=true)

    % should call this withoutpath or nopath or something.
    function f_root = rootname(fname)
      [f_path f_name f_ext]=fileparts(fname);
      f_root = [f_name f_ext];
    end

    function f_path = path(fname)
      % desc: returns pathname of a filename
      [f_path, ~, ~]=fileparts(fname);
    end
    function f_root = nopath(fname)
      % desc: returns filenamw with no path
      [~, f_name, f_ext]=fileparts(fname);
      f_root = [f_name f_ext];
    end
    function sext = ext(fname)
      [~, ~, sext]=fileparts(fname);      
    end
    function fname = replext(fname, ext)
    % typically ext should contain a dot as first char
      idxs=strfind(fname,'.');
      if (isempty(idxs))
        fname = [fname ext];
      else
        fname = [fname(1:(idxs(end)-1)) ext];
      end
    end
    
    function p = subpath(fname)
    % desc: returns filename after first slash
      [sidx eidx] = regexpi(fname, '[^\\/]*[\\/]');
      if (~isempty(eidx))
        p = fname(eidx+1:end);
      else
        p = '';
      end
    end
    
    function shorter_fname = fname_relative(fname, omission)
    % desc: shortens fname so only the part including and after "archive" is left.
    %       Typically we know where the "archive" is because
    %       that's a rather special directory where we store calibrations
    %       and characterizations.  Useful for plot titles or
    %       when you need to save space on the display.
      idx = regexpi(fname,[ '[^\\]*' omission]);
      if (~isempty(idx))
        shorter_fname = fname(idx(end):end);
      else
        shorter_fname = fname;
      end
    end

    
    function shorter_fname = archive_relative(fname)
    % desc: shortens fname so only the part including and after "archive" is left.
    %       Typically we know where the "archive" is because
    %       that's a rather special directory where we store calibrations
    %       and characterizations.  Useful for plot titles or
    %       when you need to save space on the display.
      idx = regexp(fname,'[^\\]*archive','ignorecase');
      if (~isempty(idx))
        shorter_fname = fname(idx(end):end);
      else
        shorter_fname = fname;
      end
    end


    function b = get_filesize_bytes(fname)
      d=dir(fname);
      if (isempty(d))
        b=0;
      else
        b=d.bytes;
      end
    end


    function [n is ie] = num_in_fname(fname_in)
    % returns last number that is part of the file name (but not in extention)
    % and indicies of chars that hold that number     .
    % if none, returns 0 for everything.       
      n=0;
      is=0;
      ie=0;
      didx=regexp(fname_in,'\d+');
      if (~isempty(didx))
        eidx=regexp(fname_in, '\d+', 'end');
        is = didx(end);
	ie = eidx(end);
        fname_pre  = fname_in(1:is-1);
        fname_post = fname_in(ie+1:end);
        n = sscanf(fname_in(is:ie),'%d');
      end
    end
    
    function [fname n] = uniquename(path, fname_in)
      import nc.*
    % n = unique number used in name
      if (nargin==1)
        [path f_name f_ext]=fileparts(path);
        fname_in = [f_name f_ext];
      end
      fname = fname_in;
      fn = fullfile(path, fname);

      [n is ie] = num_in_fname(fname_in);
      if (ie>0)
        fname_pre  = fname_in(ie+1:end);
        fname_post = fname_in(1:is-1);
        places = ie-is+1;
      else
        idx=strfind(fname_in,'.');
        if (isempty(idx))
          fname_pre = fname_in;
          fname_post = '';
        else
          idx=idx(end);
          fname_pre=fname_in(1:idx-1);
          fname_post=fname_in(idx:end);
        end
        n = 0;
	places=3;
      end

      if (~exist(fn, 'file') && ~exist(fn, 'dir'))
        return;
      end
      fmt = ['%s%0' num2str(places) 'd%s'];
      while (n<1000)
        fname = sprintf(fmt, fname_pre, n, fname_post);
        fn = fullfile(path, fname);
        if (~exist(fn, 'file') && ~exist(fn, 'dir'))
          return;
        end
        n=n+1;
      end
    end


    function ensure_dir(path)
      import nc.*
      % path: if empty, assume current dir.
      if (~isempty(path)&&~exist(path,'dir'))
        mkdir(path);
      end
    end


    function ca=wrap_at_slashes(fn, maxw)
      fn_l = length(fn);
      r_e = ceil(fn_l/maxw);
      ca=cell(r_e,1);
      idxs = strfind(fn,'\');
      is=1;
      r=1;
      while(is <= fn_l)
        if (r < r_e)
	  g = round(is+(fn_l - (is-1)) / (r_e - (r-1)));
          ii = find(abs(idxs-g)==min(abs(idxs-g)),1);
  	  ie = idxs(ii);
          while ((ie > is+maxw-1)&&(ii>1))
  	    ie = idxs(ii-1);
          end
        else
          ie = min(fn_l, is+maxw-1);
	  if (ie < fn_l)
            ii = find(idxs <= ie, 1, 'last');
	    ie = idxs(ii);
	    if (ie < is)
              ie = max(fn_l, is+maxw-1);         
            end
          end
        end
        ca{r}=fn(is:ie);
	r=r+1;
        is=ie+1;
      end
    end


    function add_to_path(dirname, silent)
      p = path();
      r = regexp(p, '[^;]*', 'match');
      if (nargin<2) silent=0; end
      if (dirname(end)==filesep)
        dirname=dirname(1:end-1);
      end
      for k=1:length(r)
        if (strcmpi(r{k}, dirname)) 
          if (~silent)
            fprintf('WARN: using path %s\n', dirname');
          end
          return;
        end;
      end
      fprintf('WARN: %s added to path\n', dirname');
      path(path, dirname);
    end


    function [root fnames] = common_root(fnames)
    % fnames: a cell array of strings
      root=fnames{1};
      idxs=union(strfind(root,'/'), strfind(root,'\'));
      root_i=length(root);
      for k=2:length(fnames)
	fname=fnames{k};
	for i=1:root_i
	  if (fname(i)~=root(i))
            root_i=i-1;
            break;
	  end
	end
      end
      tmp=find(idxs<=root_i,1,'last');
      if (isempty(tmp))
	root_i=0;
      else
	root_i=idxs(tmp(end));
      end
      root=root(1:root_i);
      for k=1:length(fnames)
	fnames{k}=fnames{k}(root_i+1:end);
      end
    end

    function subst(src, dst, exp, repstr)
      f1 = fopen(src,'r');
      if (f1<0)
        fprintf('ERR: cant open src %s\n', src);
      end	
      f2 = fopen(dst,'w');
      if (f2<0)
        fprintf('ERR: cant open dst %s\n', dst);
      end	
      while (1)
        l = fgetl(f1);
        if (~ischar(l))
          break;
        end
        l2 = strrep(l, exp, repstr);
        fprintf(f2, '%s\n', l2);
      end
      fclose(f1);
      fclose(f2);
    end

    
  end % static methods
  
end  
