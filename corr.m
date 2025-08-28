%-- pat: short
%-- y: loonger
%-- qual: 
function c = corr(pat, y, qual)
  pat=pat(:);
  y=y(:);
  p_l=length(pat);
  y_l=length(y);
  c_l = abs(p_l-y_l)+1;
  c=zeros(c_l,1);
  if (p_l>y_l)
    error('pat must be shorter than y');
  end
  if (nargin<3)
    qual='same';
  end
  p_l=length(pat);
  % correlation is backwards convolution
  if (strcmp(qual,'valid'))
    c = conv(y, flipud(pat),'valid');
  else
    c = conv([y; zeros(p_l-1,1)], flipud(pat),'valid');
  end
  %  for k=1:c_l
  %    c(k)=sum(pat.*y((1:x_l)+k-1));
  %  end
end
