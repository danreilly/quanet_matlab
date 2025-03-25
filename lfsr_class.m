classdef lfsr_class < handle
    
  properties
    cp
    w
    rst_st
    st
  end

  methods
    % CONSTRUCTOR
    function me = lfsr_class(cp, rst_st)
       me.cp = cp;
       me.rst_st = rst_st;
       me.st = rst_st;
       me.w = floor(log2(cp)); % state width
    end
    
    function reset(me)
       me.st = me.rst_st;       
    end
    
    function v = gen(me, n)
    % returns v = nx1 vector
      v=zeros(n,1);
      for k=1:n
        v(k)=bitget(me.st,1);
        b = nc.util.bitxor(bitand(me.st,me.cp));
        % fprintf('x%03x  %d\n', me.st, b);
        me.st = bitor(bitshift(me.st, -1) ...
                      , bitshift(b, me.w-1));
      end
    end
    
  end
end    
