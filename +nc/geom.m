classdef geom
% geometric functions
  methods (Static=true)
  
    function m = rot_rad2m(ang_rad)
    % Desc: 2x2 rotation matrix.
      c = cos(ang_rad);
      s = sin(ang_rad);
      m = [c -s; s c];
    end

    function pts = rotate(ang_rad, pts)
      pts = nc.geom.rot_rad2m(ang_rad)*pts;
    end
    
  end  
end
