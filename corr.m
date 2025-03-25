%-- x: short
%-- y: loonger
function c = corr(x,y)
  x=x(:);
  y=y(:);
  x_l=length(x);
  y_l=length(y);
  c_l = abs(x_l-y_l)+1;
  c=zeros(c_l,1);
  if (x_l>y_l)
    error('x must be shorter than y');
  end
  for k=1:c_l
    c(k)=sum(x.*y((1:x_l)+k-1));
  end
end
