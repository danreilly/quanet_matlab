% pol class
% routines dealing with the polarization of light
% and that model FPCs

% all static
classdef pol

  methods (Static=true)

  function deg = angdiff_deg(a, b)
  % input: two vectors a and b
  % returns: angular difference between a & b in units of degrees
    import nc.*
    if (~isvector(a)||~isvector(b))
      error('pol.angdiff_deg(a,b): a and b must be vectors');
    end
    if (length(a)~=length(b))
      error('pol.angdiff_deg(a,b): a and b must be same length');
    end
    a=pol.unitize(a(:));
    b=pol.unitize(b(:));
    deg = abs(atan2(pol.mag(cross(a,b)),dot(a,b))*180/pi);
  end

  function diff_rad = rot_diff_rad(a, b)
    if ((ndims(a)~=2) || (ndims(b)~=2) ...
        || any(size(a)~=size(b)) || (size(a,1)~=size(a,2)))
      error('pol.rot_matrix_diff_rad(a, b): a and b must be rotation matricies of same size');
    end
    diff_rad = acos((trace(a'*b)-1)/2);
  end


  function m=mag(v)
    % NOTE: it's better to use built-in function norm()
    % which by default takes the "2" norm
    m=sqrt(sum(v.^2));
  end

  function m=rot_tox(v)
    % pol.ROT_TOX(v)
    % inputs
    %   v : 3x1 vector
    % returns
    %   m : 3x3 rotation matrix that will rotate v to x axis
    %       In other words, m*v = [1 0 0].'
    import nc.*

    if (~isvector(v))
      error('ERR: pol.rot_tox(v): v must be a vector');
    end
    v = pol.unitize(v);
    if (pol.mag(v(1:2))<pol.mag(v([1 3])))
      % not all vectors project into xy plane significantly.

      vp = pol.unitize([v(1); 0; v(3)]); % project v to xz plane
      m = [  vp(1)    0   vp(3)
               0      1    0
            -vp(3)    0   vp(1)];  % this rotates vp around y to x
      vr = m*v; % rotate v to xy plane
      vr(3)=0;
      vr = pol.unitize(vr);
      m2=[  vr(1)  vr(2)    0;
           -vr(2)  vr(1)    0
             0      0       1];
      m = m2*m;
    else
      vp = pol.unitize([v(1:2); 0]); % project v to xy plane
      m = [  vp(1)  vp(2)  0
            -vp(2)  vp(1)  0
               0      0    1 ];  % this rotates vp around z to x
      vr = m*v; % rotate v to xz plane
      vr(2)=0;
      vr=pol.unitize(vr);      
      % vr = vr/pol.mag(vr);
      m2=[  vr(1)   0   vr(3)
              0      1     0
            -vr(3)   0   vr(1)];
      m = m2*m; % rot around y to x
    end
  end

  function m = rot_around_x(rad)
    m = [1    0       0
	 0 cos(rad) -sin(rad)
	 0 sin(rad)  cos(rad)];
  end
  function m = rot_around_y(rad)
    m = [ cos(rad)    0   sin(rad);
              0       1      0;
	 -sin(rad)    0   cos(rad)];
  end
  function m = rot_around_z(rad)
    m = [cos(rad)  -sin(rad)  0;
	 sin(rad)   cos(rad)  0;
	  0           0       1];
  end

  function m = rot_around(axis, rad)
    import nc.*
    r = pol.rot_tox(pol.unitize(axis(:)));
    m = inv(r)*pol.rot_around_x(rad)*r;
  end

  function [ axis, rad ]= axis_of_rot(m)
    % returns axis of rotation and amount of rotation around that axis
    % such that m =  rot_around(axis, rad)
    import nc.*
    [v d]=eig(m);
    [mn mi]=min(abs(diag(d)-1));
    rad = acos((trace(m)-1)/2);
    v=v(:,mi); % axis of rotation

    n=cross(v,[1;0;0]);
    if (norm(n)<.1)
      n=cross(v,[0;1;0]);
    end % pick abitrary n normal to axis
    s=1;
    n=pol.unitize(n);
    nr = m * n; % rotate n using m
    if (dot(cross(n,nr),v)<0)
      s=-1;
    end
    axis = s * v;
  end
  
  function m=muel_rot_to_h(sv)
    % inputs
    %   sv : a 3x1 subset of a stokes vector, indicating true axis of rotation
    % returns
    %   m : a 4x4 mueler matrix that would rotate sv to H, no attenuation.
    m = zeros(4,4);
    m(1,1)=1;
    m(2:4,2:4)=nc.pol.rot_tox(sv);
  end

  function m = muel_polarizer()
    m = [1 1 0 0; 1 1 0 0; 0 0 0 0; 0 0 0 0]*0.5;
  end

  function m = stokes_det()
    m = [1 0 0 0];
  end
  function m = muel_det()
    fprintf('WARN: muel_det deprecated.  use stokes_det\n');
    m = stokes_det;
  end

  function m=muel_zrot(a)
    % a = angle in rad
    % rotation around z (in xy plane)
    m = [1     0         0     0 ; ...
         0  cos(2*a) -sin(2*a) 0 ; ...
         0  sin(2*a)  cos(2*a) 0 ; ...
         0     0         0     1];
  end

  function m=muel_hwp(p)
    % returns mueler matrix for horizontal waveplate
    %  p = phase of waveplate, in rad
    m = [1 0   0      0     ;
         0 1   0      0     ;
         0 0 cos(p) -sin(p) ;
         0 0 sin(p)  cos(p)];
  end

  function v=unitize(v)
    n = sum(v.^2);
    if (n>0)
      v=v/sqrt(n);
    end
  end

  function m=muel_wp(a, p)
    % desc: returns mueler matrix for a set of waveplates
    % inputs:
    %   a : 3xn matrix of waveplate axis
    %   p : vector of retardances of waveplates, in rad
    if (length(p)>size(a,2))
      error('pol.muel_wp(ax, p): p is wider than ax');
    end
    m = diag(ones(4,1));
    for k=length(p):-1:1
      mr = nc.pol.muel_rot_to_h(a(:,k));
      %    m = m * (mr \ nc.pol.muel_hwp(p(k)) * mr);
      m = m * mr.' * nc.pol.muel_hwp(p(k)) * mr;
    end
  end

  function [m ret_rad] =muel_fit(rotm, wp_axes)
    % desc:
    %   finds the true mueler rotation matrix
    %   that is MSE closest to given 3x3 matrix m
    % inputs:
    %   wp_axes  : 3xn set of non-ideal waveplate axes.  MUST BE approx H-D-H
    %   rotm: approximately a 3x3 rotation matrix. May have error added to it.
    % returns:
    %   ret_rad: nx1 vector of retardances in units of rad
    %   m: mueler matrix of wavplates when set to red_rad.
    import nc.*
    r1 = pol.unitize(rotm(1,:)); % top row
    c1 = pol.unitize(rotm(:,1)); % left col

    num_wp = size(wp_axes,2);

    for k=1:num_wp
      v=zeros(3,1);
      v(mod(k-1,2)+1)=1;
      if (dot(v,wp_axes(:,k))<0.9)
        fprintf('wp_axes(:,%d)=[%g %g %g]\n', k, wp_axes(:,k));
        fprintf('different from [%g %g %g]\n', v);
        error('pol.muel_fit: wp_axes must be approx HDH waveplates');
      end
    end

    sb = sqrt(r1(2)^2+r1(3)^2);
    b = atan2(sb, r1(1));
    if (sb > 1e-4)  % see pa_cal_and_align_doc sec 2.2
      a = atan2(r1(2), r1(3));
      c=atan2(c1(2)/sb, -c1(3)/sb);
    else
      c=0;
      a=atan2(rotm(2,3)/rotm(1,1), rotm(3,3));
    end
    dbg=0;
    ph = zeros(num_wp,1);
    ph(1:3) = [a b c].';
    if (dbg)
      uio.print_matrix('rotm', rotm);
      uio.print_matrix('ph', ph*180/pi);
    end

    wp_msk=[0 1 1 1].';

    dp_change_lim_hi = 1;     % above this, we consider it divergence
    dp_change_lim_lo = 1e-20; % below this, phase isn't really changing
    rms_err_done_thresh = 1e-6;

    % a=[1 0 1; 0 1 0; 0 0 0];
    % n=pol.muel_wp(wp_axes,ph);
%    ca=cos(ph(1)); sa=sin(ph(1));
%    cb=cos(ph(2)); sb=sin(ph(2));
%    cc=cos(ph(3)); sc=sin(ph(3));

    p_idxs = find(wp_msk);


    mf = reshape(rotm, [], 1);
    for k=1:20
      n  = pol.muel_wp(wp_axes,ph);
      nf = reshape(n(2:4,2:4),[],1); % flat
      dm = mf-nf;
      rms_err = dm.'*dm;
      if (dbg)
        fprintf('DBG: itr %d: angs %d %d %d   rms_err %g\n', k, ...
		round(ph(1)*180/pi),round(ph(2)*180/pi),round(ph(3)*180/pi), ...
		rms_err);
      end
      if ((k==1)||(rms_err < best_rms_err))
        best_rms_err = rms_err;
	best_ph      = ph;
      end
      if (rms_err < rms_err_done_thresh)
	if (dbg)
          fprintf('DBG: ok\n');
	end
	break;
      end

      if (0)
	ca=cos(ph(1)); sa=sin(ph(1));
	cb=cos(ph(2)); sb=sin(ph(2));
	cc=cos(ph(3)); sc=sin(ph(3));
	dda = [0 0 0 ca*sb -ca*cb*sc-cc*sa ca*cb*cc-sa*sc -sa*sb cb*sa*sc-ca*cc -ca*sc-cb*cc*sa].';
	ddb = [-sb cb*sc -cb*cc cb*sa sa*sb*sc -cc*sa*sb ca*cb ca*sb*sc -ca*cc*sb].';
	ddc = [0 cc*sb sb*sc 0 -ca*sc-cb*cc*sa ca*cc-cb*sa*sc 0 sa*sc-ca*cb*cc -ca*cb*sc-cc*sa].';
	jac=[dda ddb ddc]; % Jacobean
      end

      ji=zeros(9,sum(wp_msk));

      for c=1:length(p_idxs)
	wp_o = p_idxs(c);
        dda = diag(ones(4,1));
        for wp=1:num_wp;
          if (wp==wp_o)
            dda=pol.muel_diff_wp(wp_axes(:,wp),ph(wp))*dda;
          else
            dda=pol.muel_wp(wp_axes(:,wp),ph(wp))* dda;
          end
        end
        ji(:,c) = reshape(dda(2:4,2:4),[],1);
      end

      if (0)
	fprintf('\n');
        uio.print_matrix('jac', jac);
      end
      if (dbg)
	fprintf('\n');
        uio.print_matrix('ji', ji);
	fprintf('\n');
      end
      if (0)
        uio.print_matrix('ji-jac', ji-jac);
	fprintf('\n');
      end

      jac = ji;
      % because dm ~= jac * dph
      dph = (jac.'*jac)\(jac.'*dm);

      if (dbg)
        uio.print_matrix('dp_deg', dph*180/pi);
	uio.pause;
      end

      ph(p_idxs) = ph(p_idxs) + dph;

      dp_change = dph.'*dph;
      if (dbg)
	fprintf('dp_change %g\n', dp_change);
      end

      if (dp_change > dp_change_lim_hi)
	if (dbg)
          fprintf('DBG: stop because dp change big\n');
        end
        break;
      end
      if (dp_change < dp_change_lim_lo)
	if (dbg)
          fprintf('DBG: stop because dp not changing\n');
        end
        break;
      end
    end

    ret_rad = best_ph;
    rms_err = best_rms_err;				  
    m  = pol.muel_wp(wp_axes,ret_rad);

    if (dbg) %
      uio.print_matrix('final_ret_deg', round(ret_rad*180/pi*100)/100);
      fprintf('final err %g rms\n', rms_err);
    end

  end

  function m=muel_diff_wp(wp_axis, p)
    % returns differential of mueler matrix for arbitrary waveplate
    % with respect to phase, evaluated at that point.
    %  wp_axis : axis of waveplate (3x1)
    %  p : retardance of waveplate, in rad
    mr = nc.pol.muel_rot_to_h(wp_axis);

    diff_muel_hwp = [ 0 0    0      0     ;
                      0 0    0      0     ;
                      0 0 -sin(p) -cos(p) ;
                      0 0  cos(p) -sin(p)];
    m = mr.' * diff_muel_hwp * mr; % eq13
  end



  function [ret_rad, err_ms] = muel_solve_for_xform(wp_axes, ideal_ret)
    % desc
    %   figures out the retardances to use on a set of real (non-ideal) waveplates
    %   that result in the same transformation
    %   that some ideal retardances would on ideal waveplates.
    % given
    %   ideal_ret : vector of ideal retardances, in rad
    %   wp_axes  : 3xn set of non-ideal waveplate axes
    % returns
    %   ret_rad : nx1 (vertical) set of retardances (rad)
    import nc.*

    num_wp = length(ideal_ret);
    if (~isvector(ideal_ret))
       error('ideal_ret must be a vertical vector');
    end

    dbg=0;
    iter_lim=20;
    err_done_thresh_ms = 1e-10;
    dp_change_lim = .8;
    dp_change_lim_lo = 1e-15; % below this, retardance isn't really changing

    wp_axes_ideal = round(wp_axes);

    % we'd like this transform
    goal = pol.muel_wp(wp_axes_ideal, ideal_ret);

    g = reshape(goal(2:4,2:4),[],1);
    p = ideal_ret(:); % ensure vertical

    best_err_ms = 1e9;
    div_ctr=0; % divergence counter
    dp_change_max=0;

    ji = zeros(9,num_wp);

    for k=1:iter_lim
      % calc Iv(P)
      iw = pol.muel_wp(wp_axes, p);
      gv=reshape(iw(2:4,2:4),[],1);

      dg = g - gv;
      err_ms = dg.'*dg;
      if (dbg)
        fprintf('itr %d    err %.9g\n', k, err_ms);
        fprintf('   %10.6f', p); fprintf('\n');
      end
      if ((k==1)||(err_ms <= best_err_ms))
        best_err_ms = err_ms;
        best_p = p;
        div_ctr=0;
      else
        div_ctr=div_ctr+1;
      end

      if (err_ms < err_done_thresh_ms)
        if (dbg)
          fprintf('exit because low err\n');
        end
        break;
      end

      % calc I'(P)
      ji=zeros(9,num_wp);
      for wp_o=1:num_wp
        dd = diag(ones(4,1));
        for wp=1:num_wp;
          if (wp==wp_o)
            dd=pol.muel_diff_wp(wp_axes(:,wp),p(wp))*dd;
          else
            dd=pol.muel_wp(wp_axes(:,wp),p(wp))* dd;
          end
        end
        ji(:,wp_o) = reshape(dd(2:4,2:4),[],1);
      end

if (0)
% sort of a gram-schmidt thing:
jiu = zeros(9,num_wp);
for k=1:num_wp
  jiu(:,k) = pol.unitize(ji(:,k));
end
jiu
dp = dg.'*jiu;
dp
[dpm dpi]=max(abs(dp));
fprintf('subtracting col %d:\n', dpi);
dp(dpi)*jiu(:,dpi)
dg2 = dg - dp(dpi)*jiu(:,dpi);
'now'
dg2
err_ms = dg2.'*dg2;
  fprintf('itr %d    err %.9g\n', k, err_ms);
dg2.'*jiu
ret_rad=0;
end


      % because dg ~= ji*dp
      ji2 = ji.'*ji;
      ji2_cond = rcond(ji2);
      elimi = 0;
      if (isnan(ji2_cond)||(ji2_cond < 1e-20))
%        fprintf('ERR: ji2 not invertable (cond %g)', ji2_cond);
        elimi=2; % num_wp;
        ji(:,elimi)=[];
        ji2 = ji.'*ji;
        ji2_cond = rcond(ji2);
      end
      if (isnan(ji2_cond)||(ji2_cond < 1e-20))
        fprintf('WARN: JI2 not invertable');
        break;
      end
      
      dp = ji2\(ji.'*dg); % eq23
      if (elimi)
        dp = [dp(1:elimi-1); 0; dp(elimi:end)];
      end
      dp_change = dp.'*dp;
      if (dp_change > dp_change_max)
        dp_change_max = dp_change;
      end
      if (dp_change > dp_change_lim)
        % Experimenting to see which is the best policy:
        if (0) % abort, in fear of divergence
          if (dbg)
            fprintf('exit because dp change=%g too big\n', dp_change);
          end
          break;
        else % just limit the max change per iter
          dp = dp*sqrt(dp_change_lim)/sqrt(dp_change);
        end
      end
      if (dp_change < dp_change_lim_lo)
        if (dbg)
          fprintf('exit because dp not changing enough (%g)', dp_change);
        end
        break;
      end
      p = p + dp;
    end
    ret_rad = best_p;
    err_ms  = best_err_ms;
  end


  function p = newf(ideal_wp_axes, m)
   p = [1 2];
  end

  function [p_rad muel err_ms] = muel_ph_for_ideal_wp(ideal_wp_axes, m)
    % inputs
    %   wp_axes: 3xn matrix of n waveplate axes.
    %   m: muel matrix
    % outputs
    %   p_rad: phases
    %   muel: resulting mueler matrix. ideally is identical to m.
    %   err_ms: mean square difference of (muel-m).  should be tiny!
    import nc.*	   
    if ((size(ideal_wp_axes,1)~=3)||(size(ideal_wp_axes,2)~=3))
      error('pol.muel_ph_for_ideal_wp: ideal_wp_axes must be 3x3\n');
    end
    wp_axes=round(ideal_wp_axes);
    zero_thresh = 1e-10;    
    if (all(all(wp_axes==[1 0 0; 0 1 0; 1 0 0].')))
      s2s = m(3,2)^2+m(4,2)^2;
      if (s2s < zero_thresh)
        a2 = acos(round(m(2,2)));
        a3 = 0;
        a1 = atan2(-m(3,4), m(3,3));
      else
        a3 = atan2(m(3,2),-m(4,2));
        m2 = pol.muel_wp([1 0 0].', -a3)*m;
        a2 = atan2(-m2(4,2), m2(2,2));
        m3 = pol.muel_wp([0 1 0].', -a2)*m2;  
        a1 = atan2(m3(4,3), m3(4,4));
      end
    elseif (all(all(wp_axes==[0 1 0; 1 0 0; 0 1 0].')))
      s22 = m(3,2)^2+m(3,4)^2;
      if (s22 < zero_thresh)
        a2 = acos(round(m(3,3)));
        a1 = atan2(m(2,4),m(2,2));
        a3 = 0;
      else
        a2 = atan2(sqrt(s22), m(3,3));
%        fprintf('a2 = atan2(%g,%g)=%g\n', sqrt(s22), m(3,3), a2);
        a1 = atan2(m(3,2),-m(3,4));
%        fprintf('a1 = atan2(%g,%g)=%g\n', m(3,2),-m(3,4), a1);
        a3 = atan2(m(2,3),m(4,3));
%        fprintf('a2 = atan2(%g,%g)=%g\n', m(2,3),m(4,3), a3);
      end
    elseif (all(all(wp_axes==[1 0 0; 0 1 0; 0 0 1].')))
      if (m(2,2)^2+m(3,2)^2 < zero_thresh)
        m42 = round(m(4,2));
	a2 = -asin(m42);
        a3 = 0;
	a1 = atan2(-m42*m(2,3), m(2,4));
      else
	a2 = -asin(m(4,2));
	a1 = atan2(m(4,3),m(4,4));
	a3 = atan2(m(3,2),m(2,2));
      end
    else
      uio.print_matrix('axes', wp_axes);
      error('pol.muel_solve_for_arb_xform not implemented for those wp axes!');
    end
    p_rad = [a1 a2 a3].';
    muel = pol.muel_wp(wp_axes, p_rad);
    err_ms = sum(sum((muel(2:4,2:4)- m(2:4,2:4)).^2));
    if (err_ms > 1e-16)
      fprintf('\n\nBUG in nc.pol.muel_ph_for_ideal_wp():\n');
      uio.print_matrix('axes', wp_axes);
      uio.print_matrix('m', round(m*1000)/1000);
      uio.print_matrix('p_rad', p_rad);
      uio.print_matrix('err_rms', sqrt(err_ms));
      error('BUG: nc.pol.muel_ph_for_ideal_wp failed\n');
    end
  end

  function mrot = cleanup_rotation_matrix(mrot)
  % desc: uses gram-schmidt.  Will not divide by zero.
    d = size(mrot,1);
    for c=1:d
      x=mrot(:,c);
      n=norm(x);
      if (n>1e-10)
        x=x/n;
      elseif (c==1) % pick anyhing
        x=zeros(size(x));
        x(c)=1;
      elseif (c==2) % pick anything orthogonal to first col
        x=mrot(:,1);
        if (all(abs(diff(x))<1e-3)) % x is too uniform
          x(1)=0;
          x=x/norm(x);
        else
          x=circshift(x,1);
        end
        x=cross(mrot(:,1),x);
        x=x/norm(x);        
      else % pick anything orthogonal to established cols
        x=mrot(:,1);
        for c2=2:(c-1)
          x=cross(mrot(:,c2),x);
          x=x/norm(x);
        end
      end
      mrot(:,c)=x;
      for c2=c+1:d
        dp=dot(mrot(:,c2),x);
        mrot(:,c2) = mrot(:,c2) - dp*x;
      end
    end
  end
  
  function [ret_rad rms_err] = muel_solve_for_arb_xform(wp_axes, m)
  % inputs
  %   wp_axes: 3xn matrix of n waveplate axes.
  %   m: mueller matrix
    import nc.*
    if ((size(m,1)~=4)||(size(m,2)~=4))
      error('BUG: m must be a 4x4 muler matrix');
    end
    xform=pol.rot_tox(wp_axes(:,1));
    d_axs = xform * wp_axes(:,2); % pick out a D axis
    d_axs = pol.unitize([0; d_axs(2); d_axs(3)]); % project onto yz plane  
                                % rot around x so d_axs is D
                                %  cth=x, sth=z
    xf2 = [ 1       0         0;
            0   d_axs(2)  d_axs(3);
            0  -d_axs(3)  d_axs(2)];
    xform = xf2*xform;

    ax2 = xform * wp_axes;

    m2=eye(4);
    rotm = pol.cleanup_rotation_matrix(m(2:4,2:4));
    m2(2:4,2:4) = xform * rotm * xform';

    ret_rad = pol.muel_solve_for_arb_xform_ll(ax2, m2);

    g = reshape(rotm,[],1);
    ma = pol.muel_wp(wp_axes, ret_rad);
    ma=reshape(ma(2:4,2:4),[],1);
    dg = g - ma;
    rms_err = dg.'*dg;
  end

    function p = muel_solve_for_arb_xform_ll(wp_axes, m)
      global DBG;
      % desc
      %   figures out the hases to use on non-ideal H D H waveplates
      %   that result in the same transformation as m
      % inputs
      %   wp_axes: 3xn matrix of n waveplate axes.

      % returns
      %   p : nx1 set of phases (rad)
      import nc.*

      zero_thresh = 1e-24;    

      num_wp = size(wp_axes, 2);
      if(num_wp~=3)
        error('BUG: muel_solve_for_arb_xform only works for 3 waveplates');
      end

      % initial guess
      [p_rad muel err_ms] = pol.muel_ph_for_ideal_wp(round(wp_axes), m);

if (0)
      if (all(round(wp_axes(:,1)*1000)/1000==[1 0 0].'))
        s2s=m(2,3)^2 +m(2,4)^2;
        if (s2s < zero_thresh)
          a2 = acos(round(m(2,2)));
          a3 = 0;
%         a1 = atan2(round(-m(2,2))*m(3,4), m(3,3));
          a1 = atan2(-m(3,4), m(3,3));
        else
          a3 = atan2(m(3,2),-m(4,2));
          m2 = pol.muel_wp([1 0 0].', -a3)*m;
          a2 = atan2(-m2(4,2), m2(2,2));
          m3 = pol.muel_wp([0 1 0].', -a2)*m2;  
          a1 = atan2(m3(4,3), m3(4,4));
        end
      elseif (all(round(wp_axes(:,1))==[0 1 0].'))
        if (m(3,2)^2+m(3,4)^2 < zero_thresh)
          a2 = acos(round(m(2,2)));
          a1 = atan2(m(2,4),m(2,2));
        else
          a2 = acos(m(2,2));
          a1 = atan2(m(3,2),-m(3,4));
          a3 = atan2(m(2,3),m(4,3));
        end
      else
        error('BUG: muel_solve_for_arb_xform only works for HDH or DHD waveplates');
      end
      p = [a1 a2 a3].';  
end
   p = p_rad(:);

      iter_lim=20;
      rms_err_done_thresh = 1e-10;
      small_dp_lim = 1e-5; % if we're not really changing the phases, terminate.
      dp_change_lim = 2;   % above this, we consider it divergence

  
      g = reshape(m(2:4,2:4),[],1);

      best_err = 1e9;
      div_ctr=0; % divergence counter
      dp_change_max=0;

      ji = zeros(9,num_wp);

      for k=1:iter_lim
        % calc Iv(P)
        iw = pol.muel_wp(wp_axes, p);
        gv=reshape(iw(2:4,2:4),[],1);

        dg = g - gv;
        rms_err = dg.'*dg;
        if ((k==1)||(rms_err <= best_err))
          best_err = rms_err;
          best_p = p;
          div_ctr=0;
        else
          div_ctr=div_ctr+1;
        end
        if (rms_err < rms_err_done_thresh)
          break;
        end
        if ((k>1)&&(abs(rms_err-rms_err_prev)<1e-10)) % no progress
          break;
        end
        rms_err_prev = rms_err;
        % calc I'(P)
        for wp_o=1:num_wp
          dd = diag(ones(4,1));
          for wp=1:num_wp;
            if (wp==wp_o)
              dd=pol.muel_diff_wp(wp_axes(:,wp),p(wp))*dd;
            else
              dd=pol.muel_wp(wp_axes(:,wp),p(wp))* dd;
            end
          end
          ji(:,wp_o) = reshape(dd(2:4,2:4),[],1);
        end
        %   d1 = muel_wp(wp_angs(2),p(2))*diff_muel_wp(wp_angs(1),p(1));
        %   d1v = reshape(d1(2:4,2:4),[],1);
        %   d2 = diff_muel_wp(wp_angs(2),p(2))*muel_wp(wp_angs(1),p(1));
        %   d2v = reshape(d2(2:4,2:4),[],1);
        %   ji = [d1v d2v];

        % because dg ~= ji*dp
        ji2 = ji.'*ji;
        if (rcond(ji2)<1e-24)
          fprintf('ERR: I not invertable\n');
          break;
        end
        dp = ji2\(ji.'*dg); % eq23
        dp_change = dp.'*dp;
        if (dp_change > dp_change_max)
          dp_change_max = dp_change;
        end
        if (dp_change > dp_change_lim)
          break;
        end
        p = p + dp;
      end
      p=best_p;
    end


  function [ret_rad, err_ms] = muel_solve_for_basis(wp_axes, basis)
    % desc
    %   Suppose waveplates are followed by an H polarizer.
    %   This figures out the retardances to use on a set of real (non-ideal) waveplates
    %   that result in a measurement in the specified basis.
    %   That is, they rotate basis to H.
    % given
    %   wp_axes  : 3xn set of non-ideal waveplate axes
    %   basis: 3x1 stokes vector
    % returns
    %   ret_rad : nx1 (vertical) set of retardances (rad)
    import nc.*
    num_wp = size(wp_axes,2);
    if (~isvector(basis) || (length(basis)~=3))
      error('basis must be a 3x1 vertical vector');
    end

    % of the first two axes, which is closer to H?
    [mx idx]=max([1 0 0]*wp_axes(:,1:2));
    p=zeros(num_wp,1);

    % goal:  M * B = H
    % so         B = M.' * H    so first col of M.' is B.
    % initial conditions:
    % first we find M.'.  Suppose M.' is an ideal D (ret p(2)) then H (ret p(1))
    % muel(H,2)*muel(D,1)=[c1 0 s1; s1s2 c2 -c1s2; -s1c2 s2 c1s2]
    if (pol.mag(basis(2:3))<1e-6)
      p(idx+1)=acos(round(basis(1)));
      p(idx)=0;
    else
      p(idx+1)=acos(basis(1));
      p(idx)=atan2(basis(2),-basis(3));
    end
    %'is first col B?'
    %m = pol.muel_wp([0 1 0; 1 0 0].',[p(idx+1); p(idx)])

    p = -p;
    %'is first col H?'
    %pol.muel_wp([1 0 0; 0 1 0].',[p(idx); p(idx+1)])*[1; basis]

    dbg=0;
    iter_lim=20;
    err_done_thresh_ms = 1e-10;
    dp_change_lim = 20*pi/180; % in rad
    dp_change_lim_lo = 1e-15; % below this, retardance isn't really changing
    dp_change_max=0;
    elimi_sav =0;

    for k=1:iter_lim
      m = pol.muel_wp(wp_axes, p) * [1; basis];
      err = [1 0 0].'-m(2:4);
      err_ms = err.'*err;

      if (dbg)
        fprintf('itr %d    err %.9g\n', k, err_ms);
        fprintf('   %10.6f', m(2:4)); fprintf('\n');
        fprintf('   %10.6f', p*180/pi); fprintf('\n');
      end
      if ((k==1)||(err_ms <= best_err_ms))
        best_err_ms = err_ms;
        best_p = p;
        div_ctr=0;
      else
        div_ctr=div_ctr+1;
      end
      if (err_ms < err_done_thresh_ms)
        if (dbg)
          fprintf('exit because low err\n');
        end
        break;
      end

      % calc I'(P)
      ji=zeros(3,num_wp);
      for wp_o=1:num_wp
        dd = [1; basis];
        for wp=1:num_wp;
          if (wp==wp_o)
            dd=pol.muel_diff_wp(wp_axes(:,wp),p(wp))*dd;
          else
            dd=pol.muel_wp(wp_axes(:,wp),p(wp))* dd;
          end
        end
        ji(:,wp_o) = dd(2:4);
      end


      % because err ~= ji*dp
      ji2 = ji.'*ji;
      ji2_cond = rcond(ji2);
      elimi = 0;
      if (isnan(ji2_cond)||(ji2_cond < 1e-15))
        if (~elimi_sav)
          rcs=zeros(num_wp,1);
          for wp_o=1:num_wp
            jio=ji;
            jio(:,wp_o)=[];
            rcs(wp_o)=rcond(jio.'*jio);
          end
          [mx elimi_sav]=max(rcs);
        end
        elimi=elimi_sav;
        if (dbg)
          fprintf('ERR: ji2 not invertable (cond %g), will elim %d\n', ji2_cond, elimi);
        end
        ji(:,elimi)=[];
        ji2 = ji.'*ji;
        ji2_cond = rcond(ji2);
      end
      if (ji2_cond < 1e-15)
        if (dbg)
          fprintf('exit because JI2 not invertable\n');
        end
        break;
      end
      
      dp = ji2\(ji.'*err);
      if (elimi)
        dp = [dp(1:elimi-1); 0; dp(elimi:end)];
      end

      dp_change = dp.'*dp;
      if (dp_change > dp_change_max)
        dp_change_max = dp_change;
      end
      if (dp_change > dp_change_lim)
        % just limit the max change per iter
        dp = dp*sqrt(dp_change_lim)/sqrt(dp_change);
      end
      if (dp_change < dp_change_lim_lo)
        if (dbg)
          fprintf('exit because dp not changing enough (%g)', dp_change);
        end
        break;
      end
      p = p + dp;
    end
    ret_rad = mod(best_p,2*pi);
    err_ms  = best_err_ms;
  end



    function m = eul2rotm(angs_rad, axes)
    % desc: To be like the matlab eul2rotm, third axes rotates first!
    %       rotm(angs(rad(1),axes(1))*rotm(angs(rad(2),axes(2))*...
    %       (Introduced 2015a)
    % inputs:
    %   angs_rad: vector of length 3.  angles in radians.
    %   axes: string of length 3.  The names of axes.
      import nc.*
      if (nargin<2)
	axes='zyx';
      end
      if ((length(axes)~=3)||(length(angs_rad)~=3))
	error('eul2rotm(angs_rad, axes): angs_rad and axes must be length 3');
      end
      m=eye(3);
      for d=1:3
	switch(lower(axes(d)))
	  case 'x'
	    m = m*pol.rot_around_x(angs_rad(d));
	  case 'y'
	    m = m*pol.rot_around_y(angs_rad(d));
	  case 'z'
	    m = m*pol.rot_around_z(angs_rad(d));
	  otherwise
	    error('eul2rotm(eul, axes): axes string may only contain members of "xyz"');
	end
      end
    end

    function angs_rad = rotm2eul(rotm, axes)
      if (nargin<2)
	axes='zyx';
      end
      if (length(axes)~=3)
	error('rotm2eul(rotm, axes): axes must be length 3');
      end
      if (~strcmp(axes,'zyx'))
        error('TODO: axes not implememted');
      end
      z_thresh=1e-10;
      if (abs(abs(rotm(3,1))-1)<z_thresh)
        angs_rad(2)=asin(-sign(rotm(3,1)));
        angs_rad(1)=atan2(-rotm(1,2),rotm(2,2));
        angs_rad(3)=0;
      else
        angs_rad(1)=atan2(rotm(2,1),rotm(1,1));        
        angs_rad(2)=asin(-rotm(3,1));
        angs_rad(3)=atan2(rotm(3,2),rotm(3,3));
      end
    end
  
  end % static methods




end
