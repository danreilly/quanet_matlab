function ph_deg = calc_derot2(ii, qq, hdr_ph_deg)
  import nc.*
  v = calc_min_inertia(ii-mean(ii),qq-mean(qq));
  hdr_ph_rad = hdr_ph_deg*pi/180;
  dp = [cos(hdr_ph_rad) sin(hdr_ph_rad)]*v;
  if (dp<0)
    v=-v;
  end
  ph_deg=atan2(v(2),v(1))*180/pi;
end
