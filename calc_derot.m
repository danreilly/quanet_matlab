% instead of using hdr phase,
% just use iq data itself.
function ph_deg =calc_derot(ii, qq, hdr_ph_deg)
  import nc.*
  v = calc_min_inertia(ii-mean(ii),qq-mean(qq));

  ph_deg=atan2(v(2),v(1))*180/pi;

  if (0)
    d = mod(ph_deg - hdr_ph_deg+180,360)-180;
    if (abs(d)>90)
      ph_deg = -ph_deg;
    end
  else
    c=cos(-ph_deg*pi/180);
    s=sin(-ph_deg*pi/180);
    mmm = [c -s; s c];
    iiqq = mmm*[ii.';qq.'];
    ii = iiqq(1,:).';
    qq = iiqq(2,:).';

    
    idxs = find(ii>=0);
    rc = [mean(ii(idxs)) mean(qq(idxs))];
    vr = calc_min_inertia(ii(idxs)-rc(1),qq(idxs)-rc(2))*2000;

    
    %  ncplot.subplot();
    %  ncplot.iq(ii, qq);
    %  plot(rc(1),rc(2),'.','Color','black');
    % line(rc(1)+[0 vr(1)],rc(2)+[0 vr(2)],'Color','red');
    psr = sign(vr(1))*sign(vr(2));  

    idxs = find(ii<0);
    lc = [mean(ii(idxs)) mean(qq(idxs))];
    % plot(lc(1),lc(2),'.','Color','black');
    vl = calc_min_inertia(ii(idxs)-mean(ii(idxs)),qq(idxs)-mean(qq(idxs)))*2000;
    % line(lc(1)+[0 vl(1)],lc(2)+[0 vl(2)],'Color','red');
    psl = sign(vl(1))*sign(vl(2));

    if ((psl>0) && (psr<0))
      v = -v;
    end
    ph_deg=atan2(v(2),v(1))*180/pi;
  end
  
  
end
