classdef dfpg1000_class < nc.pa1000_class
% NC.DFPG1000_CLASS
%
%  See also NC.DFPG1000_CLASS, NC.DFPG1000_CLASS.GET_SETTINGS, NC.DFPG1000_CLASS.SET_LASER_EN,
%   NC.DFPG1000_CLASS.SET_LASER_FREQ_MHZ
%

% in general:
%   set_* - change a setting on device
%   meas_* - measure something using device
%   cal_* - function intended for calibration only, not for general use

  properties
     % inhereted properties are:
  %     dbg  % 0=none, 1=debug cpds reads
  %     port
  %     ser
  %     idn
  %     devinfo
  % %     devinfo.num_chan - number of channels (FPCs) in chassis
  % %     devinfo.num_wp - number of waveplates per channel (assume all same)
  %     settings
  % %     settings.wavelens_nm(chan) - current wavlenths in nm
  % %     settings.waveplates_deg(chan, 1..6) - current waveplate settings in deg
  % %     settings.freq_MHz - optical frequency in MHz
     samp_hdr
     samp_hdr_len
     cols
   end

   properties (Constant=true)
     % ctr wl column from NIST SRM 2517a page 2
     % third column of pressure shift of center lines
     % from  Gilbert table 2, which does not list all lines
     %       line    wl(nm)   shft_slp(pm/kPa)  signif_dig  norm_xmit
     nist_acetlyne = [      5  1528.01432  .017            9  .15;
	             6  1528.59390  .016            9   .5;
		     7  1529.1799   .016            8   .1;
		     8  1529.7723   .015            8   .4;
		     9  1530.3711   .015            8   .1;
		     10  1530.97627  .015           9   .4;
		     11  1531.5879   .015           8   .1;
		     12  1532.2060   .015           8   .4;
		     13  1532.83045  .015           9   .1;
		     14  1533.46136  .016           9   .5; %
		     15  1534.0987   .016           8   .15;
		     16  1534.7425   .01675         8   .5;
		     17  1535.3928   .0175          8   .2;
		     18  1536.0495   .01825         8   .6;
		     19  1536.7126   .019           8   .3;
		     20  1537.3822   .01975         8   .7;
		     21  1538.0583   .0205          8   .4;
		     22  1538.7409   .02125         8   .8;
		     23  1539.42992  .022           9   .6; %
		     24  1540.12544  .0235          9   .85;
		     25  1540.82744  .025           9   .7; %
		     26  1541.5359   .025           8   .9;
		     27  1542.2508   .025           8   .8;
                     28  1542.9496   .025           7   .95; % DAN'S GUESS
                     29  1543.6483   .025           7   .85]; % DAN'S GUESS
     % pressure of gas that NIST used
     nist_p_Pa = 6.7e3;
     % pressure of gas in our acetlyne cells
     our_p_Pa = 0.798e3;
   end

   methods (Static=true)

     function str = acetlyne_MHz2str(f_MHz)
       import nc.*	      
       c_mps = 299792485.0; % speed of light m/s
       our_gas_wls_nm = dfpg1000_class.nist_acetlyne(:,2) - (dfpg1000_class.nist_p_Pa - dfpg1000_class.our_p_Pa)/1000*dfpg1000_class.nist_acetlyne(:,3) / 1000;
       our_gas_freqs_MHz = c_mps./(our_gas_wls_nm*1e-9)/1e6;
       idx = find(abs(our_gas_freqs_MHz - f_MHz)==min(abs(our_gas_freqs_MHz - f_MHz)),1);
       ref_gl_MHz = our_gas_freqs_MHz(idx);
       ref_gl_num = dfpg1000_class.nist_acetlyne(idx,1);
       ref_gl_off_MHz = round(f_MHz - ref_gl_MHz);
       if (ref_gl_off_MHz>0)
	 str = sprintf('P%02d+%dMHz', ref_gl_num, round(ref_gl_off_MHz));
       else
	 str = sprintf('P%02d-%dMHz', ref_gl_num, -round(ref_gl_off_MHz));
       end
     end

     function [gas_freqs_Hz norm_xmit] = acetlyne_lookup(lines)
       % inputs:
       %   lines: vector of NIST gasline numbers in "P" region
       %          if a string, will print to screen (for interactive use)
       % returns:
       %   gas_freqs_Hz: center frequency of gas dip, or 0 if not found
       %   norm_xmit: normalized transmittance(range 0..1)
       %             based on NIST figure 1, then scaled for our gas cell
       % reference:
       %   NIST SRM 2517a
       import nc.*
       t = ischar(lines);
       if (t)
	 lines = sscanf(lines,'%d');
       end


       c_mps = 299792485.0; % speed of light m/s

       lines_l = length(lines);
       gas_freqs_Hz = zeros(lines_l,1);
       norm_xmit = zeros(lines_l,1);
       for li=1:lines_l
	 for k=1:size(dfpg1000_class.nist_acetlyne,1)
	   if (dfpg1000_class.nist_acetlyne(k,1)==lines(li))
	     nist=dfpg1000_class.nist_acetlyne(k,:);
	     %fprintf(' nm %10.5f nm\n', nist(k,2));
	     %fprintf('-sh %10.5f nm\n', (nist_p_Pa - out_p_Pa)/1000*nist(k,3)/1000);
	     gas_wl_nm = nist(2) - (dfpg1000_class.nist_p_Pa - dfpg1000_class.our_p_Pa)/1000*nist(3) / 1000;
	     %fprintf('nm %10.5f nm\n', gas_wl_nm);
	     gas_freqs_Hz(li) = c_mps./(gas_wl_nm*1e-9);
             norm_xmit(li) = 1-(1-nist(5))* .4/.9; % scale for our system
	     if (t)
	       nm_fmt = sprintf(' = %%.%df nm\n', nist(4)-4);
  	       fprintf('P%02d = %d MHz', lines(li), round(gas_freqs_Hz(li)/1e6));
  	       fprintf(nm_fmt, c_mps/gas_freqs_Hz(li)*1e9);
	     end
	     break;
	   end
	 end
       end
     end
   end

   methods

    % CONSTRUCTOR
    function me = dfpg1000_class(port, opt)
    % NC.DFPG1000_CLASS	     
    % desc: constructor
    % inputs: 
    %     opt.dbg: 0=normal, 1=print all io to device
      import nc.*
      if (nargin<2)
	opt.dbg=0;
      end
      me@nc.pa1000_class(port, opt); % funny syntax to call superclass constructor
      if (me.ser.isopen())
        me.get_settings;
	me.get_sample_hdr;

        [err msg]=me.get_cal;
        if (err)
          fprintf('ERR: could not read calibration info from flash\n');
          msg
        end

	me.ser.set_do_cmd_bug_responses({'AUTOERR:'});
      end
    end

    function get_settings(me)
% NC.DFPG1000_CLASS.GET_SETTINGS
% desc: querries device for current settings and records them all in the settings
%       structure.  Must be used with an open device.  For example, if your
%       dfpg1000_class object is stored in a variable named dfpg, you would do:
%           dfpg.get_settings;
%       And then you would access the settings structure:
%           dfpg.settings.
%
%       The settings structure contains:
%         waveplates_deg: matrix num_chan*num_wp of settings in deg
%         wavelens_nm: 1xnum_chan vector of wavelengths in nm
%         laser_en: 0=off,1=on
%         fdbk_en: whether stabilizing freq on an acetlyne line: 0=off,1=on
%         laser_freq_MHz: current laser frequency, in MHz
%         goal_linenum
%         goal_side

      get_settings@nc.pa1000_class(me); % get superclass settings
      me.ser.do_cmd('l'); % laser menu
      rsp = me.ser.do_cmd('p'); % print settings
      me.settings.voa_attn_dB = me.ser.parse_keyword_val(rsp, 'attn_dBx100',0)/100;
      me.settings.laser_en    = me.ser.parse_keyword_val(rsp, 'laser_en',0);
      me.settings.fdbk_en     = me.ser.parse_keyword_val(rsp, 'fdbk_en', 0);
      me.settings.laser_freq_MHz = me.ser.parse_keyword_val(rsp, 'freq_MHz', 0);
      goal = me.ser.parse_keyword_val(rsp, 'goal', [0 0 1 0]);
      me.settings.goal.linenum    = goal(1);
      me.settings.goal.offset_MHz = goal(2);
      me.settings.goal.side       = goal(3);
      me.settings.goal.freq_MHz   = goal(4);
% TODO: FIX
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % config
      rsp=me.ser.do_cmd('p'); % print
      me.settings.cal.gaslines = me.ser.parse_keyword_val(rsp,'gaslines',[]);
      me.settings.cal.itla_mode = me.ser.parse_keyword_val(rsp,'itla_mode','d');
      me.settings.cal.itla_pwr_dBm = me.ser.parse_keyword_val(rsp,'itla_pwr_dBmx100',-100)/100;
      me.settings.cal.itla_finetune_MHz = me.ser.parse_keyword_val(rsp,'itla_fine_MHz',0);
      me.settings.cal.itla_channel = me.ser.parse_keyword_val(rsp,'itla_chan',0);
      me.settings.cal.itla_grid_MHz = 50000;
      me.settings.cal.itla_f0_MHz = me.ser.parse_keyword_val(rsp,'itla_f0_MHz',0);
      me.settings.cal.itla_freq_MHz = me.ser.parse_keyword_val(rsp,'itla_freq_MHz',0);
      me.settings.cal.laser_fm = me.ser.parse_keyword_val(rsp,'laser_fm',0);
      me.settings.cal.downsamp = me.ser.parse_keyword_val(rsp,'downsamp',1);
      me.settings.samp_pd_us  = me.ser.parse_keyword_val(rsp, 'samp_pd_us', 1);
    end

    function stokes = calc_current_polarization(me, lsr_idx)
      import nc.*
      m = pol.muel_wp(me.cal.wp_axes, me.settings.waveplates_deg(lsr_idx,:)*pi/180);
      stokes = m(2:4,2:4) * me.cal.iv.';
    end

    function [err msg] = set_polarization(me, lsr_idx, stokes)
% inputs:
%   stokes: 3x1 stokes vector
      import nc.*
      if ((size(stokes,1)~=3)||(size(stokes,2)~=1))
	error('nc.dfpg1000_class.set_polarization: stokes must be 3x1');
      end
      if (~me.cal_ok)
        msg='did not read waveplate calibration info from flash';
        err=1;
        return;
      end
      % In the DFPG, the IV vector is the stokes vector incident on first wp I THINK.

      iv = me.cal.iv(lsr_idx,:).';

      goal = pol.rot_tox(stokes).' * pol.rot_tox(me.cal.iv(lsr_idx,:).');

      [n ph]=pol.muel_fit(goal, me.cal.wp_axes);
%uio.print_matrix('n',n);
%uio.print_matrix('ph_deg', ph*180/pi);
ph_deg = mod(ph*180/pi, 360);
%uio.print_matrix('ph_deg', ph_deg);

      me.set_waveplates_deg(1,1,ph_deg);
    end

    function en = set_laser_en(me, lsr_idx, en)
    % return value:
    %   en : resulting enable setting (may be different)
      me.ser.do_cmd('l'); % config menu
      me.ser.do_cmd('e'); %
      me.ser.set_cmd_params(2000, 60*1e6);
      en = logical(en);
      rsp = me.ser.do_cmd([num2str(en) char(13)]);
      me.ser.set_cmd_params(2000, 2000);
      en = logical(me.ser.parse_matrix(rsp));
      me.settings.laser_en = en;
    end

    function en = set_laser_fdbk_en(me, lsr_idx, en)
    % return value:
    %   en : resulting enable setting (may be different)
      me.ser.do_cmd('l'); % config menu
      me.ser.do_cmd('b'); % set fdbk en
      en = logical(en);
      rsp = me.ser.do_cmd([num2str(en) char(13)]);
      % en = logical(me.ser.parse_matrix(rsp));
      me.settings.fdbk_en(lsr_idx) = en;
    end

    function b = laser_islocked(me, lsr_idx)
      me.ser.do_cmd('l'); % laser menu
      rsp = me.ser.do_cmd('s'); % print status
      b = me.ser.parse_keyword_val(rsp, 'locked',0);
    end

    function status = get_status(me)
      % returns:
      %   status.locked: logical. 0=unlocked, 1=locked
      %   status.laser_init_err: 0=ok, otherwise, an error indication
      me.ser.do_cmd('l'); % laser menu
      rsp = me.ser.do_cmd('s'); % print status
      status.laser_locked = me.ser.parse_keyword_val(rsp, 'locked',0);
      status.laser_init_err = me.ser.parse_keyword_val(rsp, 'init_err', 1);
      err_var_MHz2 = me.ser.parse_keyword_val(rsp, 'err_var_MHz2', 10000);
      if (err_var_MHz2<0) % nonsensical
	err_var_MHz2=10000;
      end
      status.err_std_MHz = sqrt(err_var_MHz2);
    end

    function attn_dB = set_voa_attn_dB(me, lsr_idx, attn_dB)
      % desc: sets voa attenuation in units of dB.
      % inputs:
      %   attn_dB : desired attenuation in units of dB.    Resolution is 0.01 dB.
      % returns:
      %   attn_dB : attenuation actually used (may be different)
      me.ser.do_cmd('l'); % laser menu	     
      me.ser.do_cmd('a'); % set attn
      rsp = me.ser.do_cmd([num2str(round(attn_dB*100)) char(13)]);
      dBx100 = me.ser.parse_matrix(rsp);
      attn_dB = dBx100(1,1)/100;
      me.settings.voa_attn_dB = attn_dB;
    end


    function [n str] = get_sample_hdr(me)
    % desc: header for sampled data
    % returns:
    %     n: number of columns in sampled data
    %     str: space-separated string of n keywords, one for each column
      import nc.*	     
      me.ser.do_cmd('l'); % laser menu	     
      me.ser.do_cmd('c'); % calibration
      str = me.ser.do_cmd('h'); % get samphdr

      idxs=regexp(str, '\n');
      if (length(idxs)<2)
	fprintf('ERR: dfpg gave bad rsp to samphdr command:\n');
	uio.print_all(str);
	error('FAIL');
      end
      str = str(idxs(1)+1:idxs(2)-1);
      me.samp_hdr = regexp(str, '\w*', 'match');

      n = length(me.samp_hdr);
      if (n<3)
        fprintf('WARN: dfpg.get_run_hdrs: runhdr has only %d values, which does not seem right\n', n);
	uio.pause;
      end

      me.cols.time_10us  = nc.vars_class.datahdr2col(str, 'time_10us');
      me.cols.err_MHz    = nc.vars_class.datahdr2col(str, 'err_MHz');
      me.cols.gas1_adc   = nc.vars_class.datahdr2col(str, 'gas1_adc');
      me.cols.pwr1_adc   = nc.vars_class.datahdr2col(str, 'pwr1_adc');
      me.cols.itlaf1_MHz = nc.vars_class.datahdr2col(str, 'itlaf1_MHz');

      me.samp_hdr_len = n;
    end

    function data = sample(me, nsamps)
      % desc: takes nsamps samples at current downsampling rate.
      if (nargin<2)
        nsamps=1;
      end
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % cal menu
      me.ser.do_cmd('S'); % sample

      me.ser.set_cmd_params(64*nsamps, 1*1e6*nsamps);

      me.ser.cmd_nchar=256;
      [rsp err] = me.ser.do_cmd([num2str(nsamps) 13]); % sample

      me.ser.set_cmd_params(2000, 2000);
      m=me.ser.parse_matrix(rsp);
      if (size(m,2)~=me.samp_hdr_len)
	fprintf('BUG: tried to sample, expected width %d but got:\n', me.samp_hdr_len);
	nc.uio.print_all(rsp);
	m
	m(1,me.samp_hdr_len)=0;
	m=m(:,1:me.samp_hdr_len);
	error('BUG');
      end
      data = m;
    end

    function set_laser_fdbk_goal(me, lsr_idx, goal)
% inputs:
%
%   goal.linenum: nist-assigned acetlyne gasline number
%   goal.offset_MHz: offset from mid-slope in MHz
%   goal.side: +1 = rising edge ( approx 250MHz above dip)
%         -1 = falling edge( approx 250MHz below dip)
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('g'); % set goal
      me.ser.do_cmd([num2str(goal.linenum) 13]);
      me.ser.do_cmd([num2str(goal.offset_MHz) 13]);
      rsp = me.ser.do_cmd([num2str(goal.side) 13]);
      m = me.ser.parse_matrix(rsp);
      me.settings.goal.linenum = m(1);
      me.settings.goal.offset_MHz = m(2);
      me.settings.goal.side = m(3);
      me.settings.goal.freq_MHz = m(4);
    end

    function err = set_laser_freq_MHz(me, lsr_idx, freq_MHz)
      if (lsr_idx>me.devinfo.num_chan)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
      if (me.settings.fdbk_en(lsr_idx))
        error('BUG: calling dfpg1000_class.set_laser_freq_MHz while lock to gasline fdbk is enabled');
      end
      freq_MHz = round(freq_MHz);
      % fprintf('DBG: dfbg100_class: set_laser_freq_MHz %d\n', freq_MHz);
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('f'); % set freq
      me.ser.set_cmd_params(2000, 60*1e6);
      rsp = me.ser.do_cmd(sprintf('%d\r', freq_MHz));
      f=me.ser.parse_keyword_val(rsp,'f',0);
      idx1=me.ser.parse_keyword_val(rsp,'ndex',0);
      idx2=me.ser.parse_keyword_val(rsp,'ndex2',0);
      wl_nm=me.ser.parse_keyword_val(rsp,'avelength',0);
      me.settings.laser_freq_MHz = f;
      err = (f ~= freq_MHz);
    end

    function cal_set_voa_attn_dac(me, lsr_idx, attn_dac)
      % intended for calibration, not general use
      if (lsr_idx>me.devinfo.num_chan)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % config menu
      me.ser.do_cmd('a'); % set attn
      me.ser.do_cmd([sprintf('%d', attn_dac) 13]);
    end

    function cal_set_laser_fm(me, lsr_idx, fm)
      % intended for calibration, not general use
      if (lsr_idx~=1)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % cal menu
      me.ser.do_cmd('F'); % set fm
      me.settings.cal.laser_fm(lsr_idx)=me.ser.do_cmd_get_matrix([sprintf('%d', fm) 13], ...
							 me.settings.cal.laser_fm(lsr_idx));
    end

    function cal_set_itla_mode(me, lsr_idx, mode)
      % intended for calibration, not general use
      if (lsr_idx~=1)
        error(sprintf('BUG: laser index %d exceeds limit', lsr_idx));
      end
      if (~ischar(mode)||(length(mode)~=1))
        error('BUG: mode must be a single char');
      end
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % config menu
      me.ser.do_cmd('m'); % config menu
      me.ser.set_cmd_params(2000, 60*1e6);
      rsp = me.ser.do_cmd(mode);
      me.ser.set_cmd_params(2000, 2000);
      % fprintf('DBG: set laser %d mode to %s\n', lsr_idx, mode);
      % nc.uio.print_all(rsp)
      idxs=regexp(rsp, '(?<=\n).\n'); % single char on line by itself
      rsp_mode=0;
      if (~isempty(idxs))
        rsp_mode=rsp(idxs(1));
	me.settings.itla_mode=rsp_mode;
      end
      if (rsp_mode ~= mode)
	 % highly unusual.
	 fprintf('ERR: tried to set laser %d mode to %s\n', lsr_idx, mode);
	 fprintf('     but is now %s\n', rsp_mode);
	 nc.uio.print_all(rsp);
      end
    end

    function er = wait_for_pwr_stability(me, lsr_idx, verbose, min_itrlim)
       % returns: er: 1=timeout after 100 tries, 0=ok and stable
       % input: min_itrlim = OPTIONAL. min num iterations to wait.  Then this is the number
       %          of iterations over which we consider a "change" to take place. see code.
       % NOTE: If you change the power of the pure photonics laser, it will take some
       % time to do that.  Then it will indicate that it is done.  But don't beleive it!
       % call this function to wait for the power to truely stabilize.  Same goes
       % for laser enable and also channel change!
       if (nargin<2)
         verbose=0;
       end
       if (nargin<4)
         min_itrlim=8;
       end
       er=1;

       h_i = 1;
       h_l = min_itrlim;

       h = zeros(h_l,1);

       settle_start = tic;
       if (verbose)
         fprintf('waiting for power of lsr %d to settle\n', lsr_idx);
       end
       pcol = me.cols.pwr1_adc;
       pwr_pre=0;
       ok_ctr=0;
       for itr=1:1000
	 v = me.sample(1);
	 % assumes wl1 is stable.
         pwr = v(pcol);
         if (itr>h_l)
           pch_pct = 100 * (pwr - h(h_i)) / h(h_i);
	   if (abs(pch_pct) < 0.1)
             er=0;
             break;
           end
         else
           pch_pct = 100 * (pwr - h(1)) / h(1);
         end
         h(h_i) = pwr;
         h_i=mod(h_i,h_l)+1;
         if (verbose)
  	   fprintf('   laser  pwr %d  ch %.3f%%\n',  pwr, pch_pct);
         end
	 pause(0.025);
	 pwr_pre = pwr;
       end
%       er = (ok_ctr<=4);
       if (er && verbose)
         fprintf('dfpg1000_class.wait_for_stability(): ERR: laser is stuck!\n');
       end
       if (verbose)
         settle_s = round(toc(settle_start));
         fprintf('settling took %g seconds = %g min\n', settle_s, settle_s/60);
       end
     end

    function cal_set_itla_pwr_dBm(me, lsr_idx, pwr_dBm)
      if (lsr_idx>me.devinfo.num_chan)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
      me.ser.do_cmd('l'); % debug menu
      me.ser.do_cmd('c'); % calibration menu
      me.ser.do_cmd('P'); % set lsr pwr
      %pwr_dBm= round(pwr_dBm*100)/100;
      m = me.ser.do_cmd_get_matrix([sprintf('%d', round(pwr_dBm*100)) 13], ...
 				   me.settings.cal.itla_pwr_dBm(lsr_idx));
      me.settings.cal.itla_pwr_dBm = m/100;
    end

    function cal_set_itla_channel(me, lsr_idx, channel)
      % intended for calibration, not general use
      if (lsr_idx~=1)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % cal menu
      me.ser.do_cmd('c'); % set itla channel
      me.ser.set_cmd_params(2000, 60*1e6);
      m = me.ser.do_cmd_get_matrix([sprintf('%d', channel) 13], ...
 				   me.settings.cal.itla_channel(lsr_idx));
      me.settings.cal.itla_channel(lsr_idx) = m;
      me.settings.cal.itla_freq_MHz = me.settings.cal.itla_f0_MHz + (m-1)*me.settings.cal.itla_grid_MHz + me.settings.cal.itla_finetune_MHz;
      me.ser.set_cmd_params(2000, 2000);
    end

    function err = cal_set_itla_finetune_MHz(me, lsr_idx, finetune_MHz);
      % intended for calibration, not general use
      % tends to fail sometimes dont know why
      if (lsr_idx~=1)
        error(sprintf('BUG: device lsr_idx %d exceeds limit', lsr_idx));
      end
%      fprintf('DBG: cal_set_itla_finetune_MHz(%d, %d)\n', lsr_idx, finetune_MHz);
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % caibration menu
      me.ser.do_cmd('f'); % set itla finetune_MHz
      me.ser.set_cmd_params(2000, 60*1e6);
      finetune_MHz = round(finetune_MHz);
      m = me.ser.do_cmd_get_matrix([sprintf('%d', finetune_MHz) 13], ...
  			       me.settings.cal.itla_finetune_MHz(lsr_idx));
      me.settings.cal.itla_finetune_MHz = m;
      me.settings.cal.itla_freq_MHz = me.settings.cal.itla_f0_MHz + (me.settings.cal.itla_channel-1)*me.settings.cal.itla_grid_MHz + m;
      me.ser.set_cmd_params(2000, 2000);
      err = (finetune_MHz ~= m);
    end

    function cal_set_voa_dB2dac_map(me, map)
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % config menu
      rsp = me.ser.do_cmd('s'); % set voa attn dB to dac mapping
      max_pieces = me.ser.parse_keyword_val(rsp, 'max', 0);
      if (size(map,1)>max_pieces)
	fprintf('ERR: device accepts splines of no more than %d pieces\n', max_pieces);
	return;
      end
      for k=1:size(map,1)
	cmd = sprintf(' %d', round(map(k,:)*1000));
        me.ser.do_cmd([cmd char(13)]);
      end
      me.ser.do_cmd(char(13));
    end

    function cal_set_gaslines(me, lsr_idx, gaslines)
      % gaslines: see tunlsr calibration document
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % laser calibation menu
      rsp = me.ser.do_cmd('g'); % set gaslines
      max_gaslines = me.ser.parse_keyword_val(rsp, 'max',0);
      if (size(gaslines,1)>max_gaslines)
	fprintf('ERR: device accepts no more than %d gaslines\n', max_gaslines);
      end
      for k=1:size(gaslines,1)
	gl = gaslines(k,:);
	cmd = sprintf(' %d', gl);
        me.ser.do_cmd([cmd char(13)]);
      end
      rsp = me.ser.do_cmd_get_matrix(char(13), 0);
      if (rsp~=size(gaslines,1))
	fprintf('ERR: device accepted only %d gaslines\n', rsp);
      end
    end

    function cal_set_downsampling(me, ds)
      me.ser.do_cmd('l'); % laser menu
      me.ser.do_cmd('c'); % cal menu
      me.ser.do_cmd('d'); % set downsamp
      me.ser.do_cmd(sprintf('%d\r', ds));
      me.settings.cal.downsamp = ds;
    end

    function err = cal_save_flash(me, password)
      me.ser.do_cmd('s');
      [rsp err] = me.ser.do_cmd('w');
% 3/18/2016
% PA fwver 5.0.1 and higher ask for a password before writing the flash.
% the purpose is to protect the user against accidentally permanatly corrupting
% his calibration information and serial number
      if (strfind(rsp,'password'))
	[rsp err] = me.ser.do_cmd([password 13]);
      end
      idx=strfind(rsp, '--');
      err = isempty(idx);
      if (~err)
	idx=idx(1);
	idx2=strfind(rsp(idx:end),char(10));
	idx2=idx2(1);
	fprintf('device says: %s\n', rsp(idx:(idx+idx2-2)));
      end
    end

  end
end
