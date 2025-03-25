%-- x: short
%-- y: loonger
function c = corr_circ(pat,y, dbg)
% circular correlation

  if (nargin<3)
    dbg=0;
  end
    
  if (size(y,2)~=1)
    error('y must be vert vect');
  end
  if (size(pat,2)~=1)
    error('pat must be vert vect');
  end
       
  p_l=length(pat);
  % correlation is backwards convolution
  c = conv([y; y(1:(p_l-1))], flipud(pat),'valid');


end
