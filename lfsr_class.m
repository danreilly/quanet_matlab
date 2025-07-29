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
    % CP: note: MUST include MSB of cp. (changed 6/15/25)
       me.w = floor(log2(cp)); % state width
       me.cp = bitset(cp,me.w+1,0);
       me.rst_st = rst_st;
       me.st = rst_st;
       % fprintf('lfsr class w=%d  cp=x%s\n', me.w, dec2hex(me.cp));
    end
    
    function reset(me, rst_st)
       if (nargin>1)
         me.rst_st=rst_st;
       end
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
