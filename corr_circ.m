%-- x: short
%-- y: loonger
function c = corr_circ(pat,y, dbg)
% circular correlation
% Here circular correlation is used because it makes debugging a bit easier in some cases,
% but it's not necessary operationally.  For that we just need a conventional correlation,
% and allow partial correlations at the start and end be attenuated or disregared.
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
