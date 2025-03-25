classdef teps100_class < handle

  properties (Constant=true)

  end

  % instance members
  properties
    dbg_lvl  % 0=none, 1=debug cpds reads
    ser      % obj of type serclass
    idn      % NuCrypt identity structure
    devinfo  % 
%     can_ctl_align_pwr     
    settings % current settings - read only - updated every device open
%     atten_dB   - optical attenuation applied to output signal
%     wavelen_nm - wavelength to emit.  
%     prob       - probability of a 1 
%     fpc_deg    - retardances of FPC0. 1x4 vector
%
%   settings used during calibration:
%     atten_dac
%
    cal      % device calibration - read only once, by constructor
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function [err msg_rsp cal] = parse_printcal_rsp(devinfo, rsp)
      %   msg_rsp : cell array of user feedback strings
      msg_rsp={};
      err=0;
      cal.voa_calfile  = nc.ser_class.parse_keyword_val(rsp, 'voa_calfile', '');
      cal.calfile      = nc.ser_class.parse_keyword_val(rsp, 'efpc_calfile', '');
      cal.calfile2     = nc.ser_class.parse_keyword_val(rsp, 'efpc1_calfile', '');
      cal.no_wl_interp = nc.ser_class.parse_keyword_val(rsp, 'no_wl_interp', 0);

      fpc0_dac = nc.ser_class.parse_keyword_val(rsp, 'cfg fpc 0', 0);
      fpc1_dac = nc.ser_class.parse_keyword_val(rsp, 'cfg fpc 1', 0);
      me.settings.fpc_dac = [fpc0_dac; fpc1_dac];

      num_pc       = (nc.ser_class.parse_keyword_val(rsp, 'num_pc',0)==1);
      % if num_pc is zero, that means it hasn't been calibrated yet.  Otherwise it's
      % always 1, even though there are two fpcs in this device.  This is because of
      % the use of "common code".  We don't use the OZ fpc in any other device.
      % It's awkward.  Its calibration info is diminutive, different, and handled as
      % a special case.

      if (num_pc)
        pc=1;
        cal.num_wp(pc)=nc.ser_class.parse_keyword_val(rsp, sprintf('pc%d_num_wp', pc-1),0);
        for wp_i=1:cal.num_wp(pc)
          ax = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwp%dax', pc-1, wp_i-1), 0);
          cal.wp_axes(1:3,wp_i)=ax;
        end
        cal.num_wl(pc)=nc.ser_class.parse_keyword_val(rsp, sprintf('pc%d_num_wl', pc-1),0);
%        cal.num_wl(pc)
        wls_nm = zeros(1,cal.num_wl(pc));
        for wl_i=1:cal.num_wl(pc)
          wl_nm = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%d', pc-1, wl_i-1), 0);
          wls_nm(wl_i)=wl_nm;
          iv = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%div', pc-1, wl_i-1), 0);
          for wp_i=1:cal.num_wp(pc)
            co = nc.ser_class.parse_keyword_val(rsp, sprintf('pc%dwl%dwp%dco', pc-1, wl_i-1, wp_i-1), 0);
          end
        end
        cal.pc_wavelens{pc}=wls_nm;
      else
        cal.wp_axes=[1 0 0; 0 1 0; 1 0 0; 0 1 0].';
      end
    end


    function cal = read_calfile(fname)
    % desc
    %   parses a pa calibration file, returns a structure
    % inputs
    %   fname : calibration file to read
    % returns
    %   cal : a structure containing calibration info
    
      % default calibration
      cal.int_align=[0 0; 0 0];
      cal.dac2ph_coef=[];
      cal.tomo_ph=zeros(6,3);
      cal.wavelens = []; % no longer used
      cal.pc_wavelens = {};
      cal.hw_ver_major=1;
      cal.hw_ver_minor=0;
      cal.samp_pd_us=1000; % what is this?
      cal.fname = nc.fileutils.rootname(fname);
      cal.no_wl_interp=0;
    
      cal_f = fopen(fname, 'r');
      st=1;
      if (cal_f<=0)
        fprintf('ERR: read_cal(): cant open %s\n', fname);
      else
        while(1) 
          [a ct]=fscanf(cal_f, '%[^\n\r]',256);
          if (ct<=0)
            if (st>1)
              handle_matrix(name, m);
              st=1;
            end
          else
            idx = strfind(a, '=');
            if (~isempty(idx) && (st==2))
              handle_matrix(name, m);
              st=1;
            end
            if (st==1)
              if (ct && (a(1)=='%'))
                [name ct] = sscanf(a(2:end), '%s', 1);
                if (~isempty(idx))
                  idx=idx(1)+1;
                  while((idx<=length(a)) && (a(idx)==' ')) idx=idx+1; end
                  val = a(idx:end);
                  handle_str(name, val);
                end
              elseif (ct && (a(1)~='%'))
                [name ct] = sscanf(a, '%s', 1);
                idx = strfind(a, '=');
                if (isempty(idx))
                  fprintf('ERR: missing =\n');
                else
                  idx2=strfind(a(idx+1:end),'[');
                  if (~isempty(idx2))
                    idx=idx+1+idx2-1;
                  end
                  [row cols]=sscanf(a(idx+1:end),'%f',inf);
                  m = row.';
                  st=2;
                end
              end
            else % st==2
              if (ct && (a(1)~='%'))
               [row ct]=sscanf(a,'%f',inf);
                if (~ct)
                  handle_matrix(name, m);
                  st=1;
                else
                  if (ct ~=cols)
                    fprintf('ERR: non-uniform matrix\n'); 
                  else
                    m = [m; row.'];
                  end
                end
              else
                handle_matrix(name, m);
                st=1;
              end
            end
          end
          [j ct_cr]=fscanf(cal_f, '%[\r]', 8); % skip
          [j ct_nl]=fscanf(cal_f, '%[\n]', 1);
          if (ct_nl<=0)
            break;
          end
    
        end
      end
      fclose(cal_f);
    
      cal.num_wp=size(cal.wp_axes,2);
      cal.num_pc=size(cal.wp_axes,1)/3;
      if (isempty(cal.pc_wavelens))
        for pc=1:cal.num_pc
          cal.pc_wavelens{pc}=cal.wavelens;
        end
      end
      cal.wavelens=[];
      
      if (~isfield(cal, 'pol_type'))
        fprintf('WARN: calibration file lacks pol_type.  Assuming L or P based on num_wp.\n');
        if (cal.num_wp==6)
         cal.pol_type = 'p';
        else
         cal.pol_type = 'l';
        end
      end
      % nested function
      function handle_matrix(name, m)
        if (strcmp(name,'iv'))
          cal.iv=m; % DEPRECATED
        elseif (strcmp(name,'hw_ver_major'))
          cal.hw_ver_major=m;
        elseif (strcmp(name,'hw_ver_minor'))
          cal.hw_ver_minor=m;
        elseif (strcmp(name,'int_align'))
          cal.int_align=m;
        elseif (strcmp(name,'wp_axes'))
          cal.wp_axes=m;
        elseif (strcmp(name,'dac2ph_coef'))
          cal.dac2ph_coef=m;
        elseif (strcmp(name,'wavelens'))
          cal.wavelens=m;
          cal.num_wl=length(cal.wavelens);
        elseif (strcmp(name,'wavelens1'))
          cal.pc_wavelens{1}=m;
        elseif (strcmp(name,'wavelens2'))
          cal.pc_wavelens{2}=m;
        elseif (strcmp(name,'tomo_ph'))
          cal.tomo_ph=m;
        end
      end
    
      % nested function
      function handle_str(name, val)
        if (strcmp(name,'date'))
          cal.date=val;
        elseif (strcmp(name,'src1'))
          cal.src1=val;
        elseif (strcmp(name,'sernum'))
          cal.sernum=val;
        elseif (strcmp(name,'pol_type'))
          cal.pol_type=val;
        elseif (strcmp(name,'no_wl_interp'))
          cal.no_wl_interp=val;
        end
      end
    
    end % function read_calfile

  end

  methods

    % CONSTRUCTOR
    function me = teps100_class(arg1, opt)
    % desc: constructor
      if (nargin<2)
	opt.dbg=0;
      end
      opt=nc.util.set_field_if_undef(opt,'baud',115200);
%     me.dbg = opt.dbg;
      me.ser = []; % nc.ser_class('', opt.baud, opt);
      me.settings.samp_pd_ns=0;
      me.cal = [];
      if (strcmp(class(arg1),'nc.ser_class'))
        me.ser = arg1;
      elseif (ischar(arg1))
        me.ser = nc.ser_class(arg1, opt.baud, opt);
        me.ser.get_idn_rsp();
      else
        error('first param must be portname or ser_class');
      end
      me.idn = me.ser.idn;
      me.devinfo = me.parse_idn(me.idn);
      me.get_cal();
      me.get_settings();
      me.open();
    end

    % DESTRUCTOR
    function delete(me)
      me.close;
    end

    function bool = isopen(me)
      bool = me.ser.isopen();
    end

    function close(me)
      if (me.ser.isopen())
	me.ser.close;
      end
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    function err = open(me, portname, opt)
    % desc:
    %   opens device and gets identity and current settings
    % inputs:
    %   portname: string. if omitted or '', uses prior
    %   opt: optional structure of options
    %     opt.portname: optional string.  If omitted, or '', uses prior
    %     opt.baud
    %     opt.dbg
      import nc.*
      err = 0;
      if (nargin==1)
        portname='';
        opt.dbg = 0;
      elseif (nargin==2)
        if (isstruct(portname))
          opt = util.set_field_if_undef(portname, 'dbg', 0);
          portname=util.getfield_or_dflt(opt,'portname','');
        else
          opt.dbg=0;
        end
      end
      if (isempty(me.ser))
        me.ser = ser_class(portname, opt);
      elseif (~me.ser.isopen())
        me.ser.open(portname, opt);
      end
      if (~me.ser.isopen())
        return;
      end
      me.idn     = me.ser.get_idn_rsp();
      me.devinfo = me.parse_idn(me.idn);
      me.ser.set_timo_ms(5000);
      if (isempty(me.cal))
        me.get_cal();      % read only once, for efficiency
      end
      me.get_settings();   % updated with every open
    end

    function devinfo = parse_idn(me, idn)
% returns a structure with these fields:
%      devinfo.ser = 's'; % std
      devinfo=idn;
      devinfo.num_chan = 1; % because there's only one output
% But perhaps cal_pa.m should look at devinfo.num_pc instead of num_chan.
      devinfo.pol_type = 'n';
      devinfo.ser = 'x';
      devinfo.num_wp = 4;
      devinfo.supports_flash_write = 1;
      devinfo.is_timebin = 0;
      devinfo.opt_pwr_ctl = 'd';
      devinfo.can_ctl_align_pwr = 1;
      devinfo.can_change_wavelen = 1;
      devinfo.atten_is_dB=1; % WRONG for old ones!

      flds   = regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);

      while(1)

        % C1
        k=3;
        if (k>num_flds)
	  break;
        end
        % devinfo.num_chan = parse_word(flds{k}, '%d', 1);
	k = k + 1;
	if(k>num_flds)
	  return;
	end

        % C2
        devinfo.pol_ctl = flds{k}(1);
	k = k + 1;
	if(k>num_flds)
	  return;
	end

        % C3
        devinfo.ser = flds{k}(1);
  
        break;
      end

      me.devinfo=devinfo;

      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
         v = default;
        end
      end

    end

    function [err msg]=get_cal(me)
    % desc: reads calibration information from device, saves in me.cal
      [rsp, err] = me.ser.do_cmd(['cfg set' char(13)]);
      [err msg cal] = me.parse_printcal_rsp(me.devinfo, rsp);
      me.cal = cal;
    end

    function status = get_status(me)
    % desc: reads settings from device, saves in me.settings
      rsp = me.ser.do_cmd(['status' char(13)]);
      status.all_pll_locked = me.ser.parse_keyword_val(rsp, 'all_pll_locked', 0);
      status.any_plls_were_unlocked = me.ser.parse_keyword_val(rsp, 'any_plls_were_unlocked', 0);
      status.extref_los = me.ser.parse_keyword_val(rsp, 'extref_los', 0);
      status.out_pwr = me.ser.parse_keyword_val(rsp, 'out_pwr', 0);
    end

    function get_settings(me)
    % desc: reads settings from device, saves in me.settings
      rsp = me.ser.do_cmd(['set' char(13)]);
      me.settings.refin_Hz = me.ser.parse_keyword_val(rsp, 'refin', 0);
      me.settings.freq_Hz = me.ser.parse_keyword_val(rsp, 'freq', 0);
      me.settings.clkdiv = me.ser.parse_keyword_val(rsp, 'clkdiv', 0);
      me.settings.prob = me.ser.parse_keyword_val(rsp, 'prob', 0);
      me.settings.wavelen_nm = me.ser.parse_keyword_val(rsp, 'wl', 0);
      me.settings.atten_dB = me.ser.parse_keyword_val(rsp, 'attn', 0);
      me.settings.fpc_deg=me.ser.parse_keyword_val(rsp, 'fpc',[0 0 0 0]);

      p = nc.pol.muel_wp(me.cal.wp_axes, me.settings.fpc_deg)*[1 1 0 0].';
      me.settings.pol_stokes = p(2:4);
      me.settings.pol_name = ' ';
    end

    function set_nomenu(me, en)
      % does not apply.  For compat with cal_pa.m
    end

    function set_optical_atten_dB(me, atten_dB)
      % fprintf('DBG: TEPS set_atten %.3f dB\n', atten_dB)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('attn %.2f\r', atten_dB));
      if (~err && (length(m)==1))
        me.settings.atten_dB = m;
      end
    end

    function set_wavelen_nm(me, wl_nm)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('wl %d\r', round(wl_nm)));
      if (~err && (length(m)==1))
        me.settings.wavelen_nm = m;
      end
    end

    function set_clkdiv(me, n)
      [m err] = me.ser.do_cmd_get_matrix(sprintf('clkdiv %d\r', n));
      if (~err && (length(m)==1))
        me.settings.clkdiv = m;
      end
    end

    function set_prob(me, p)
      p = min(1,max(0,p));
      [m err] = me.ser.do_cmd_get_matrix(sprintf('prob %d\r', p));
      if (~err && (length(m)==1))
        me.settings.prob = m;
      end
    end

    function set_waveplates_deg(me, chan, wp, retardances_deg)
      % desc:
      %   sets angles of one or more waveplates
      % inputs:  
      %   chan: specifies channel (base one). MUST BE 1
      %         NOTE: other multi-channel device classes also have this method
      %     wp: 1..4 : specifies starting waveplate   (base one)
      %    retardances_deg: vector of angles (in deg) to set the waveplate to
      %                 range is limited in a device-calibration-specific manner.
      % changes:
      %    me.settings.waveplates_deg(chan,wp)
      if (chan~=1)
        error('teps100_class.set_waveplates_deg(chan, wp, degs): chan must be 1');
      end
      for k=1:length(retardances_deg)
        if (wp > me.devinfo.num_wp)
          error('teps1000_class.set_waveplates_deg(chan, wp, degs): len of degs exceeds num wp');
        end
        [m err] = me.ser.do_cmd_get_matrix(sprintf('fpc %d %g\r', wp-1, retardances_deg(k)));
        if (~err && (length(m)==1))
          me.settings.fpc_deg(1,wp)=m;
        end
        wp=wp+1;
      end
      p = nc.pol.muel_wp(me.cal.wp_axes, me.settings.fpc_deg*pi/180).'*[1 1 0 0].';
      me.settings.pol_stokes = p(2:4);
      me.settings.pol_name = ' ';
    end

    function [errmsgs] = set_polarization(me, v)
      % inputs:
      %   v: 3x1 stokes vector [S1 S2 S3] - desired output polarization.
      %              (need not be a unit vector... will be normalized automatically)
      %      or a char, one of: HVLRDA.
      %   Note: for [1 0 0].', all retardances are set to zero.
      import nc.*
      if (ischar(v)&&(length(v)==1))
        switch (lower(v(1)))
          case 'h'
            s=[1 0 0];
          case 'v'
            s=[-1 0 0];
          case 'd'
            s=[0 1 0];
          case 'a'
            s=[0 -1 0];
          case 'r'
            s=[0 0 1];
          case 'l'
            s=[0 0 -1];
          otherwise
            error('teps100.set_polarization(v): v must be one of HVLRDA');
        end
        me.settings.pol_name=lower(v(1));
      elseif isnumeric(v)
        if ((~isvector(v))||(length(v)~=3))
          error('teps100.set_polarization(v): v must be 3x1 matrix');
        end
        s = v;
        me.settings.pol_name=' ';
      else
        error('teps100.set_polarization(v): v must be 3x1 matrix or a char');
      end
      errmsgs='';
      if (isempty(me.cal))
        errmsgs='did not read waveplate calibration info from flash';
        return;
      end

      % In the teps100, light passes through FPC0 backwards, like:
      %    polarizer -> wp4(D) -> wp3(H) -> wp2(D) -> wp1(H) ->
      % If we don't vary wp4, wp3 is useless.  So we vary wp4, 3 & 2.

      % goal = pol.rot_tox(v);
      s=pol.unitize(s(:));
%      fprintf('DBG: set polarization %s\n',sprintf(' %g', s));
%      fprintf('     2:3 = %g\n',pol.mag(s(2:3)));
      %  me.settings.pol_stokes = s.'; % will be changed by set_wp
      if (pol.mag(s(2:3))<1e-3)
        mgoal = pol.muel_rot_to_h(s);
      else
        vp=pol.unitize([0; s(2); s(3)]); % project onto yz plane
        m = [1   0      0;
             0  vp(3) -vp(2);
             0  vp(2)  vp(3)];
        vr = m*s; % rotate around h to xz plane
        vr(2)=0;
        vr=pol.unitize(vr);
        m2 = [ vr(1) 0 vr(3);
               0    1  0
               -vr(3) 0 vr(1)];
        m = m2*m;
        mgoal=eye(4);
        mgoal(2:4,2:4)=m;
      end

      wp0 = 2;

      wp_axes = me.cal.wp_axes(1:3,wp0+(0:2));

      [ret_rad muel err_ms] =pol.muel_ph_for_ideal_wp(round(wp_axes), mgoal);
      [ret_rad, err_ms]= pol.muel_solve_for_xform(wp_axes, ret_rad);

% vo = pol.muel_wp(wp_axes, ret_rad)*[1 1 0 0].';
%      fprintf('diff is: %g deg\n', pol.angdiff_deg(v, vo(2:4)));

      ret_deg=zeros(1,4);
      ret_deg(wp0+(0:2)) = mod(ret_rad*180/pi,360);
      me.set_waveplates_deg(1,1,ret_deg);

      % fprintf('DBG: wps %s deg\n', sprintf(' %6.2f', me.settings.fpc_deg));

    end








    function set_optical_atten_dac(me, atten_dac)
      % used during calibration. typically not used by end-users.
      [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg voa %d\r', round(atten_dac)));
      if (~err && (length(m)==1))
        me.settings.atten_dac = m;
      end
    end

    function cal_set_waveplate_dac(me, pc, wp, dac)
      % desc
      %   This sets the dac value of the DAC that drives a waveplates 
      %   of a polarization controller.
      % inputs
      %   pc : 1 or 2. specifies polarization ctlr
      %   wp : 1..4    specifies the waveplate to change
      %   dacval : a scalar (in DAC units)
      if ((pc<1)||(pc>2))
	error(sprintf('BUG: teps100_class.cal_set_waveplate_dac() called with pc=%d\n', pc));
      end
      if ((wp<1)||(wp>me.devinfo.num_wp))
	error(sprintf('BUG: teps100_class.cal_set_waveplate_dac() called with wp=%d\n', wp));
      end
      cmd = sprintf('cfg fpc %d %d %d\r', pc-1, wp-1, round(dac));
      % fprintf('DBG: %s\n', cmd);
      [m err] = me.ser.do_cmd_get_matrix(cmd);
      if (~err && (length(m)==1))
        me.settings.fpc_dac(pc,wp)=m;
      end
    end
 
    function cal_save_flash(me, password)
      rsp = me.ser.do_cmd(['cfg write' char(13)]); 
      if (strfind(rsp,'pass'))
        rsp = me.ser.do_cmd([password 13]);
      end
      % it asks for sn.  here we dont change it.
      me.ser.do_cmd(char(13));
      % it asks for hwver major.  here we dont change it.
      me.ser.do_cmd(char(13));
      % it asks for hwver minor.  here we dont change it.
      me.ser.do_cmd(char(13));
    end

    function err=cal_set_efpc_cal(me, cal)
% NOTE: This code expects a sequence of prompts as supplied by
%       efpc_ask_cal() in "common code" efpc.c (which uses zero-base indexing)
      import nc.*             
      err=0;
      me.ser.set_dbg(1)
      k = size(cal.dac2ph_coef,1)/3;
      coef_per_wp = util.ifelse(k==round(k),3,2);
      for pc_i=1:cal.num_pc
        if (any(any(cal.wp_axes(1:3+(pc_i-1)*3,:))))
          pc_i
          me.ser.do_cmd(sprintf('cfg fpccal %d\r', pc_i-1)); % zero-indexed
          me.ser.do_cmd([cal.fname char(13)]);
          if (pc_i==1)
            me.ser.do_cmd(sprintf('1\r')); % num_pc. artificial.
            me.ser.do_cmd(sprintf('%d\r', cal.no_wl_interp));

            [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', cal.num_wp(pc_i)));
            if (~err && (m~= cal.num_wp(pc_i)))
              fprintf('ERR: not as many physical waveplates as in calibration\n');
            end
            for wp_i=1:cal.num_wp(pc_i);
              for a_i=1:3
                me.ser.do_cmd(sprintf('%g\r', cal.wp_axes((pc_i-1)*3+a_i,wp_i)));
              end
            end

            rsp = me.ser.do_cmd(sprintf('%d\r', length(cal.pc_wavelens{pc_i})));
            for wl_i=1:length(cal.pc_wavelens{pc_i})
              if (~strfind(lower(rsp), sprintf('wl%d ',wl_i)))
                 fprintf('ERR: not being prompted for wl at expected time\n');
                 fprintf('     instead prompt was: ');
                 uio.print_all(rsp);
              end
              me.ser.do_cmd(sprintf('%f\r', cal.pc_wavelens{pc_i}(wl_i)));
              k=(wl_i-1)*cal.num_pc
              for a_i=1:3
                me.ser.do_cmd(sprintf('%.5g\r', cal.int_align(k+pc_i, a_i)));
              end
              k=(wl_i-1)*cal.num_pc*coef_per_wp + (pc_i-1)*coef_per_wp;
              for wp_i=1:cal.num_wp
                for co_i=1:2 % in teps, pc_i=1 is BATi, and only two coef used
                  rsp = me.ser.do_cmd(sprintf('%g\r', cal.dac2ph_coef(k+co_i, wp_i)));
                end
              end
            end
          else % pc_i==2
            if (coef_per_wp~=3)
              error('ERR: teps needs three coef for pc2 dac2ph map\n');
            end
            for wl_i=1:2
              k=(wl_i-1)*cal.num_pc*coef_per_wp + (pc_i-1)*coef_per_wp;
              for wp_i=1:cal.num_wp
                for co_i=1:coef_per_wp
                  me.ser.do_cmd(sprintf('%g\r', cal.dac2ph_coef(k+co_i, wp_i)));
                end
              end
            end
          end
        end % if any non-zero wp axes
      end % for pc
    end

    function err=cal_set_voa_dB2dac_map(me, fname, maps)
      if (~iscell(maps) || (length(maps)~=2))
        error('teps100_class: cal_set_voa_dB2dac_map(me, fname, maps): maps must be 2x1 cell array');
      end
      err=1;
      me.ser.do_cmd(['cfg voacal' char(13)]);
      rsp = me.ser.do_cmd([nc.fileutils.rootname(fname) char(13)]);
      max_pieces = me.ser.parse_keyword_val(rsp, 'max', 0);
      for m_i=1:2
        map = maps{m_i};
        if (size(map,1)>max_pieces)
  	  fprintf('\nERR: device accepts splines of no more than %d pieces\n', max_pieces);
	  fprintf('     and spline in file has %d pieces\n', size(map,1));
          nc.uio.pause;
          err=1;
        end
        for k=1:min(size(map,1),max_pieces)
          cmd = sprintf(' %e', map(k,:));
          me.ser.do_cmd([cmd char(13)]);
        end
        me.ser.do_cmd(char(13));
      end
      err=0;
    end

  end
  
end
