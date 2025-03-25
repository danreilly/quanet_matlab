classdef eps1000_cal_class < nc.eps1000_class
% extends eps1000 class with calibration functions (NuCrypt internal use)
  
  properties (Constant=true)
    JUNK = 0;
  end
  
  properties
    pwd
  end
  
  methods

    % CONSTRUCTOR
    function me = eps1000_cal_class(arg1, arg2)
    % desc: eps1000 constructor
      import nc.*
      args{1}=arg1;
      if (nargin==1)
        arg2.dbg=0;
      end
      me = me@nc.eps1000_class(arg1, arg2);
    end
    
    function set_password(me, pwd)
      me.pwd = pwd;
      % fprintf('eps1000_cal_class dbg: SET PASSWORD\n');
    end
    
    function get_settings(me)
      me.get_settings@nc.eps1000_class(); % superclass get settings
      
      %      rsp = me.ser.do_cmd(['cfg cal set' char(13)]);
      %      nd = me.devinfo.num_chan * me.devinfo.num_dlyrs_per_chan;
      %      for ch=1:nd
      %        me.settings.dlyr_coarse_dac(ch) = me.ser.parse_keyword_val(rsp,sprintf('dlyr %d c', ch),0);
      %n        me.settings.dlyr_fine_dac(ch)   = me.ser.parse_keyword_val(rsp,sprintf('dlyr %d f', ch),0);
      %      end
    end

    function err=goto_cal_menu(me, pwd)
    % The purpose of the password protection of the cal menu
    % is to prevent users from accidentally changing calibration
    % information (stored in the flash) that is required for
    % proper operation.
      err=0;
      if (nargin<2)
	pwd=me.settings.password;
      else
	me.settings.password=pwd;
      end
      rsp=me.ser.do_cmd('c'); % config menu
      if (strfind(rsp,'password'))
	[rsp err] = me.ser.do_cmd([pwd 13]);
        if (~strfind(rsp, 'onfiguration'))
          fprintf('ERR: maybe "%s" is the wrong password\n', pwd);
          return;
        end
      end
    end
    
    function set_selftst_params(me, fname, params)
    % dly_i: 1-based index of delayer.  (ually there are two per spidly board)
      if (me.goto_cal_menu())
	return;
      end
      rsp = me.ser.do_cmd('T');
      n = me.ser.parse_keyword_val(rsp,'n=',0);
      if (n==8)
        me.ser.do_cmd(sprintf('%s\r', fname));
        for k=1:n
          me.ser.do_cmd(sprintf('%d\r', params(k)));
        end
      else
        fprintf('ERR; unrecognized fmt');
      end
      me.ser.do_cmd('e');
      me.ser.do_cmd('s'); % save settings
    end


    function err=set_voa_dB2dac_spline(me, chan, fname, spline)
    % inputs:
    %   spline: hxw matrix.  h = num pieces +1.  spline(1:h,1) are breaks;
    %           spline(2:end,2) are x^3 coef.  spline(2:end,3) are x^2 coef.
      err=1;
      me.ser.set_dbg(1);
      if (me.goto_cal_menu())
	return;
      end
      w=size(spline,2);
      if (any(spline(1,2:end)))
        % compatible with old-format spline matricies that
        % assumed starting break was at zero.
        fprintf('DBG: old fmt spline\n');
        spline = [zeros(1,w); spline];
      end
      rsp = me.ser.do_cmd('v'); % set voa atten dB to dac mapping
      if (~isempty(strfind(rsp,'voa idx')))
        me.ser.do_cmd(sprintf('%d\r',chan));
      end
      rsp=me.ser.do_cmd([fname 13]);
      max_pieces = me.ser.parse_keyword_val(rsp, 'max', 0);
      err=0;
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 4 0]))
        if (strfind(rsp,'xmin')) % think not the case
          rsp = me.ser.do_cmd(sprintf('%g\r', spline(1,1)));
        end
        for r=2:min(size(spline,1),max_pieces)
          cmd = sprintf(' %g', spline(r,:));
          me.ser.do_cmd([cmd char(13)]);
        end
      else % older spline.c spline_ask() took ints*1000
        if (strfind(rsp,'xmin'))
          rsp = me.ser.do_cmd(sprintf('%d\r', round(spline(1,1)*1000)));
        end
        for r=2:min(size(spline,1),max_pieces)
          cmd = sprintf(' %d', round(spline(r,:)*1000));
          me.ser.do_cmd([cmd char(13)]);
        end
      end
      me.ser.do_cmd(char(13));
      me.ser.do_cmd('e'); % return to main menu
      me.ser.do_cmd('s'); % save settings
    end

    function set_voa_attn_dB(me, chan, atten_dB)
    % for use by calibration software.
      me.goto_cal_menu();
      me.ser.do_cmd('V');
      me.ser.do_cmd(sprintf('%d\r', chan));
      me.ser.do_cmd('w');
      [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dB) 13]);
        me.ser.do_cmd('e');
      if (~err && (length(m)==1))
        me.settings.atten_dB(chan) = m;
      end
    end
    
    function set_voa_attn_dac(me, chan, atten_dac)
    % sets output optical attenuation in dac units
    % The relationship to optical power may be inverse or proportional, depending
    % on the type of VOA ("bright" or "dark") inside the eps1000.
    % On newer firmware versions, this function is typically only used during calibration.
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 2]))
        if (me.goto_cal_menu())
          return;
        end
        % fprintf('DBG: set_voa %d %d\n', chan, atten_dac);
        me.ser.do_cmd('7');
        me.ser.do_cmd(sprintf('%d\r', chan));
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dac) 13]);
        me.ser.do_cmd('e');
        if (~err && (length(m)==1))
          me.settings.atten_dac = m;
        end
      elseif (nc.util.ver_is_gte(me.devinfo.fwver, [6 2]))
        if (chan~=1)
          error(sprintf(' cal_set_voa_attn_dac(): chan=%d does not exist in this fw', chan));
        end
        me.ser.do_cmd('v');
        me.ser.do_cmd('w');
        [m err]=me.ser.do_cmd_get_matrix([num2str(atten_dac) 13]);
        if (chan>1)
          me.ser.do_cmd('e');
        end
        if (~err && (length(m)==1))
          me.settings.atten_dac = m;
        end
      else % old versions
        if (chan~=1)
          error(sprintf('cal_set_voa_attn_dac(): chan=%d does not exist in this fw ver', chan));
        end
        me.ser.do_cmd('w'); % ask to change DAC setting
        % Note: eps 6.0.1 has "2" cmd "set optical pwr",
        %       but eps 4.0 has "2" cmd to "adjust pulse"
        % GHz systems use register 11 (b)
        % and MHz systems use register 8
        if (me.devinfo.rate=='g')
          regsel='b';
        else
          regsel='8';
        end
        me.ser.do_cmd(regsel);
        me.ser.do_cmd([num2str(atten_dac) 13]);
        me.settings.atten_dac = atten_dac;
      end
    end

    function err=set_spline(me, fname, m)
    % inputs:
    %   chan: one-based index of spline.
    %   fname: short file name of calibration file
    %   m: matrix representation of a spline.
      err = 0;
      rsp = me.ser.do_cmd([fname 13]);
      max_pieces = me.ser.parse_keyword_val(rsp, 'max', 0);
      if (size(m,1)-1>max_pieces)
        fprintf('\nERR: device accepts splines of no more than %d pieces\n', max_pieces);
        fprintf('     and spline in file has %d pieces\n', size(m,1)-1);
        nc.uio.pause;
        err=1;
      end
      fmt = me.ser.parse_keyword_val(rsp, 'fmt', 'i');
      
      if (strfind(rsp,'xmin'))
        rsp = me.ser.do_cmd(sprintf('%d\r', round(m(1,1)*1000)));
      elseif (m(1,1)~=0)
        fprintf('\nERR: device uses old way of asking for spline\n');
        fprintf('       but spline has non-zero left break of %g\n', m(1,1));
        nc.uio.pause;
        err=1;
      end
      for r=2:min(size(m,1),max_pieces)
        if (fmt=='d')
          cmd = sprintf(' %g', m(r,:));
          if (length(cmd)>256)
            fprintf('\mWARN: line longer than 256\n');
            cmd = sprintf(' %.4e', m(r,:));
            if (length(cmd)>256)
              fprintf('\mWARN: line STILL longer than 256\n');
            end
          end
        else
          cmd = sprintf(' %d', round(m(r,:)*1000));
        end
        me.ser.do_cmd([cmd char(13)]);
      end
      me.ser.do_cmd(char(13));
    end

    
    function err=set_delayer_spline(me, chan, fname, m)
    % desc: Sets the calibration for the "fine" delay,
    %    which is a mapping from delay (typ -15ps .. +15 ps)
    %    to the dac value that drives FTUNE to cause that delay.
    % inputs:
    %   chan: one-based index of spline.
    %   fname: short file name of calibration file
    %   m: matrix representation of a spline.
      err = 0;
      if (me.goto_cal_menu())
        err = 1;
        return;
      end
      me.ser.do_cmd('D');
      % fw always asks the channel number even if there is only one.
      me.ser.do_cmd(sprintf('%d\r', chan));
      err = me.set_spline(fname, m);
      me.ser.do_cmd('e');
    end

    function set_waveplate_dac(me, pc, wp, val, pwd)
     %inputs: wp:1..6
    % introduced for eps fwv 7.2
      if (nargin<5)
        pwd = me.settings.password;
      end
      if ((wp<1)||(wp>me.devinfo.num_wp(pc)))
        error(sprintf('eps1000_class.cal_set_waveplates_dac: waveplate %d of pc %d nonexistant', wp, pc));
      end
      if (me.goto_cal_menu(pwd))
	return;
      end
      rsp = me.ser.do_cmd('f'); % set efpc waveplate (dac units)
      me.ser.do_cmd([num2str(pc) 13]);
      me.ser.do_cmd([num2str(wp-1) 13]);
      me.ser.do_cmd([num2str(val) 13]);
      me.ser.do_cmd('e');
    end

    function set_delayer_coarse_cal(me, ch, m)
    % desc: Sets the calibration for the "coarse" settings,
    %       which is the delay of each of the ten taps (in ps)
    %       and the straight line fitted to this model
      if (nc.util.ver_is_gte(me.devinfo.fwver, [7 3 5]))
        if ((ch<1)||(ch>2))
          error(sprintf('eps1000_class.cal_set_delayer_coarse_cal(%d): bad ch', ch));
        end
        if (me.goto_cal_menu())
          error('eps1000_class.cal_set_delayer_coarse_cal(): cant get to cal menu');
        end
        if (length(m)~=12)
          error('eps1000_class.cal_set_delayer_coarse_cal(m): m must be length 12');
        end
        me.ser.do_cmd('C');
        me.ser.do_cmd(sprintf('%d\r', ch));
        for c=1:12
          rsp = me.ser.do_cmd([num2str(m(c)) 13]);
        end
        me.ser.do_cmd('e');
      else
        fprintf('ERR: eps1000_class.cal_set_delayer_coarse(%d)\n', ch);
        fprintf('     this firmware does not accept delayer calibration\n');
      end
    end
    
    function set_delayer_coarse_dac(me, ch, coarse_dac)
      % desc: Used for calibration only.  Sets digital tap delay directly
      %       to the delayer, if harware has this connected.
      % ch: 1-based delayer index      
      % coarse_dac: digital tap delay
      if (me.devinfo.can_set_pump_phase)
        if (me.goto_cal_menu())
	  return;
        end
        me.ser.do_cmd('c');
        me.ser.do_cmd(sprintf('%d\r', ch));
        [m err]=me.ser.do_cmd_get_matrix([num2str(coarse_dac) 13]);
        if (~err && (length(m)==1))
          me.settings.delayer_coarse_dac(ch) = m;
        end
        me.ser.do_cmd('e');
      else
        fprintf('ERR: eps1000_class.set_delayer_coare_dac(%g)\n', coarse_dac);
        fprintf('     this hardware cant change dly\n');
      end
    end
    
    function set_delayer_tune_dac(me, ch, tune_dac)
    % desc: Used for calibration only.  Makes sub-ps adjustments
    %       to the delayer, if harware has this connected.
    % ch: 1-based delayer index      
    % tune_dac: fine tune setting in dac units
      if (me.devinfo.can_set_pump_phase)
        if (me.goto_cal_menu())
	  return;
        end
        me.ser.do_cmd('d');
        me.ser.do_cmd(sprintf('%d\r', ch));
        [m err]=me.ser.do_cmd_get_matrix([num2str(tune_dac) 13]);
        if (~err && (length(m)==1))
          me.settings.delayer_tune_dac(ch) = m;
        end
        me.ser.do_cmd('e');
      else
        fprintf('ERR: eps1000_class.set_delayer_tune_dac(%g)\n', ph_ps);
        fprintf('     this hardware cant change pump phase\n');
      end
    end
    
    
  end

end
