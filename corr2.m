%-- x: short
%-- y: loonger
function c = corr2(x,y)
  x=x(:);
  y=y(:);
  x_l=length(x);
  y_l=length(y);
  c_l = abs(x_l-y_l)+1;
  c=zeros(y_l,1);
  for k=1:y_l
    s_l=min(x_l,y_l-k+1);
    c(k)=sum(x(1:s_l).*y((1:s_l)+k-1));
  end
end
