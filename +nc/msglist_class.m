classdef msglist_class < handle

  properties
    l
    prefix
    msgs
  end
  
  methods

    % constructor
    function me = msglist_class(prefix)
      if (nargin>0)
        me.prefix = prefix;
      else
        me.prefix = '';
      end
      me.clr();
    end
    
    function add_no_nl(me, str)
      l = length(str);
      str_s=1;
      for k=1:l
        if ((str(k)==char(10))||(str(k)==char(13)))


          me.msgs{me.l}=[me.msgs{me.l} str(str_s:(k-1))];
          me.l=me.l+1;
          
          me.msgs{me.l}=me.prefix;
          
          if ((k<l)&&((str(k+1)==char(13))||(str(k+1)==char(10))))
            k=k+1; % one CR for even improperly ordered CR LF pairs
          end
          str_s = k+1;
        end
      end
      me.msgs{me.l}=[me.msgs{me.l} str(str_s:end)];
    end
    
    function add(me, str)
      if (iscell(str))
        error('msglist oops');
        a = length(str);
        % WARN: m-code is a wierd language sometimes: here use paren not brackets.
        me.msgs(me.l+(1:a))=str;
      else
        me.add_no_nl(str);
        me.l = me.l + 1;
        me.msgs{me.l}=[me.prefix];
      end
    end
    
    function clr(me)
    %      me.l=0;
    %      me.msgs=cell(0,1);
        me.l=1;
        me.msgs={me.prefix};
    end
    
  end
  
end
