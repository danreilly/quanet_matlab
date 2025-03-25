classdef util
  methods (Static=true)

    function r=ifelse(test,a,b)
      if (test) r=a; else r=b; end
    end

    function n=bitpos(v)
      % desc: returns bit position of least-significant non-zero bit.
      %       The bit-position is matlab style, one-based. So for example,
      %       bitpos(1) returns 1.	     
      n=-1;
      for k=1:32
	if (bitget(v,k))
	  n=k;
	  return;
	end
      end
    end

    function n=bitcnt(v)
      n=0;
      for k=1:32
	if (bitget(v,k))
	  n=n+1;
	end
      end
    end
    
    function n=bitxor(v)
    % reductive xor        
      n=0;
      for k=1:32
	if (bitget(v,k))
	  n=bitxor(n,1);
	end
      end
    end

    function s = set_field_if_undef(s, fieldname, val)
      if (~isfield(s, fieldname))
	s = setfield(s, fieldname, val);
      end
    end

    function v = getfield_or_dflt(s, fieldname, dflt)
      if (~isfield(s, fieldname))
	v = dflt;
      else
        v=getfield(s, fieldname);
      end
    end

    function idx = find_closest(v, val)
      idx=find(abs(v-val)==min(abs(v-val)),1);
    end

    function v = mod_unwrap(v, m)
      if (isempty(v))
        return;
      end	     
      if (size(v,1)==1)
        v = cumsum([v(1) mod(diff(v)+m/2,m)-m/2]);
      else
        v = cumsum([v(1); mod(diff(v)+m/2,m)-m/2]);
      end
    end

    function b = ver_is(ver1, ver2)
      b=0;
      if (length(ver1)~=length(ver2))
	    return;
      end
      b = all(ver1==ver2);
    end

    function s = ver_vect2str(ver)
      % desc: converts version from vector format to a string
      s=sprintf('%d.', round(ver));
      s=s(1:end-1);
    end
    
    function gte = ver_is_gte(ver1, ver2)
      % desc:
      %   ver1, ver2: vectors of version and subversion numbers.  Most significant first.
      % Note: This function could works with either software or hardware version numbers.
      %   Version & subversion info ought not be treated as floating point values
      %   because doing so fails to account for trailing zeros.  For example,
      %   if the info response was "HW1.10", that's subversion ten.  If it was
      %   "HW1.1", that's subversion 1.  If the program read it as a float,
      %   it wouldn't be able to tell the two apart.
      % inputs:
      %   ver1, ver2: vectors of version & subversion numbers
      gte = 0;
      l = min(length(ver1), length(ver2));
      for k=1:l
	if (ver1(k)<ver2(k))
	  return;
	elseif (ver1(k)>ver2(k))
	  gte = 1;
	  return;
	end
      end
      gte = 1;
    end

    function gt = ver_is_gt(ver1, ver2)
      % desc:
      %   ver1, ver2: vectors of version and subversion numbers.  Most significant first.
      % Note: This function could works with either software or hardware version numbers.
      %   Version & subversion info ought not be treated as floating point values
      %   because doing so fails to account for trailing zeros.  For example,
      %   if the info response was "HW1.10", that's subversion ten.  If it was
      %   "HW1.1", that's subversion 1.  If the program read it as a float,
      %   it wouldn't be able to tell the two apart.
      % inputs:
      %   ver1, ver2: vectors of version & subversion numbers
      gt = 0;
      l = min(length(ver1), length(ver2));
      for k=1:l
	if (ver1(k)<ver2(k))
	  return;
	elseif (ver1(k)>ver2(k))
	  gt = 1;
	  return;
	end
      end
      gt = length(ver1) > length(ver2);
    end

    
    function [ca idxs] = lowcase_sort(ca)
      ca2 = ca;
      for k=1:length(ca2)
	ca2{k}=lower(ca2{k});
      end
      [ca2 idxs] = sort(ca2);
      ca=ca(idxs);
    end

    function d = strcmp(s1, s2)
      % This is like the C strcmp.  -1=s1<s2, 0=(s1==s2), 1=(s1>s2);
      % For example:
      %    strcmp('aaa','bbb') == 1
      %    strcmp('bbb','aaa') == -1
      %    strcmp('aaa','aaa') == 0
      %    strcmp('aaa','aaaaa') == 1
      if (strcmp(s1,s2))
        d=0;
        return;
      end
      ca={s1; s2};
      [~, idxs]=sort(ca);
      if (idxs(1)==2) d=-1;
      else d=1; end
    end

    function t=triang(n)
      % The triangle of an integer             
      t=(n+1)*n/2;
    end

    function str=substr_after(str, key)
    % if substr not found, returns str
      idxs=strfind(str, key);
      if (~isempty(idxs))
        str=str((idxs(end)+length(key)):end);
      end
    end


    function ch = optfreq_nm2ch(wl_nm)
      c_mps = 299792458;
      f_Hz = c_mps / (wl_nm * 1e-9);
      ch = round((f_Hz - 190e12)/1e11);
      if ((ch<0)||(ch>80))
        ch = 0;
      end
    end
    
  end
end
