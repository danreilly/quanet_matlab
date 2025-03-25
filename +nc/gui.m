classdef gui
% helper utilities related to matlab guis

  methods (Static=true)
    
    function s=onoff(b)
      import nc.*
      s = util.ifelse(b,'on','off');
    end
     
    function v=get_num(hObject, dflt)
      [v n] = sscanf(get(hObject, 'string'),'%g');
      if (n<1)
        v=dflt;
      else
        v=v(1);
      end
      set(hObject, 'string', sprintf('%g', v));
    end
    
  end
end
