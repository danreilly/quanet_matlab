% v3
classdef tunlsr_class < nc.ncdev_class

  properties (Constant=true)
    DFB_P1 = 1.84257e-6;
    DFB_P2 = -.0019305;
    DFB_K0C = -273.15; % zero kelvin in Celcius

   % Note: The Pure laser cant reach any Acetlyne R lines.
   %       Its range is 1527.61 to 1565.5 nm.
   %       But it can reach HCN R lines.

     % column descriptions and sources:
     %   line: positve are P line nums, negative are R line nums
     %   wl(nm): wavelength of gasline at 6.7kPa
     %           from SRM 2517a table 1page 2
     %   shift_slp(pm/kPa): pressure shift of center lines
     %           from  Gilbert table 2, which does not list all lines
     %   digits: significant digits of wavelen. again from table 1.
     %   norm_xmt: normalized transmittance
     %             eyeballed from SRM2517a fig 1 page 4
     %
     %              line    wl       shft_slp   digits  norm_xmit
     %                     (nm)      (pm/kPa)
     nist_acetlyne = [-7  1521.06040  .017           9   .08;
                      -1  1524.13609  .007           9   .44;
                       3  1526.87435  .016           9   .3;
                       4  1527.44114  .018           9   .6;
                       5  1528.01432  .017           9   .15;  % min wl for Pure
                       6  1528.59390  .016           9   .5;
                       7  1529.1799   .016           8   .1;
                       8  1529.7723   .015           8   .4;
                       9  1530.3711   .015           8   .1;
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

% NIST does not publish shift for all lines, so we compute it.
%              P    table 1     table5     table3     signif  xmit
%              line nm@0kPa     nm@13.3kPa nm/kPa*1e5 digits  ance
     nist_hcn = [ 1 1543.1141  1543.1148     5.6      8       .82
                  2 1543.8094  1543.809      0        7       .68
                  3 1544.5147  1544.515      0        7       .62
                  4 1545.2299  1545.2314    11.0      8       .58
                  5 1545.9552  1545.9563     8.8      8       .55
                  6 1546.6902  1546.690      0        7       .52
                  7 1547.4354  1547.435      0        7       .5
                  8 1548.1904  1548.190      0        7       .51
                  9 1548.9553  1548.9554      .8      8       .52
                 10 1549.7305  1549.7302    -2.2      8       .53
                 11 1550.5157  1550.5149    -5.6      8       .55
                 12 1551.3106  1551.311      0        7       .57
                 13 1552.1157  1552.116      0        7       .58
                 14 1552.9308  1552.931      0        7       .6
                 15 1553.7560  1553.756      0        7       .62
                 16 1554.5912  1554.5892   -14.8      8       .63
                 17 1555.4365  1555.4346   -14.4      8       .70
                 18 1556.2919  1556.292      0        7       .72
                 19 1557.1573  1557.157      0        7       .75
                 20 1558.0329  1558.033      0        7       .78
                 21 1558.9185  1558.919      0        7       .82
                 22 1559.8143  1559.814      0        8       .85
                 23 1560.7201  1560.7185   -11.6      8       .88
                 24 1561.6362  1561.6344   -13.4      8       .90
                 25 1562.5625  1562.563      0        7       .92];
     our_hcn_p_Pa = 25*133.322;

  end

  % instance members
  properties
    dbg
    port
    dbg_lvl  % 0=none, 1=debug
    port_str % name of windows com port.  a string.
    ser
    running
    idn
    devinfo
    samp_hdr
    samp_hdr_len 
    run_rd_len
    settings
    cols
    capa
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function str=gasline_num2str(num)
      if (num<0)
        str=['R' num2str(-num)];
      else
        str=['P' num2str(num)];
      end
    end

    function str = acetlyne_MHz2str(f_MHz)
       import nc.*	      
       c_mps = 299792458.0; % speed of light m/s
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

      c_mps = 299792458.0; % speed of light m/s

      lines_l = length(lines);
      gas_freqs_Hz = zeros(lines_l,1);
      norm_xmit = zeros(lines_l,1);
      for li=1:lines_l
	for k=1:size(tunlsr_class.nist_acetlyne,1)
	  if (tunlsr_class.nist_acetlyne(k,1)==lines(li))
	    nist=tunlsr_class.nist_acetlyne(k,:);
	    %fprintf(' nm %10.5f nm\n', nist(2));
	    %fprintf('-sh %10.5f nm\n', (nist_p_Pa - our_p_Pa)/1000*nist(3)/1000);
            shft_nm = (tunlsr_class.our_p_Pa - tunlsr_class.nist_p_Pa)/1000*nist(3) / 1000;
	    gas_wl_nm = nist(2) + shft_nm;
	    %fprintf('nm %10.5f nm\n', gas_wl_nm);
	    gas_freqs_Hz(li) = c_mps./(gas_wl_nm*1e-9);
            norm_xmit(li) = nist(5);
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

    function [gas_freqs_Hz norm_xmit] = hcn_lookup(lines)
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

      c_mps = 299792458.0; % speed of light m/s

      lines_l = length(lines);
      gas_freqs_Hz = zeros(lines_l,1);
      norm_xmit    = zeros(lines_l,1);
      for li=1:lines_l
	for k=1:size(tunlsr_class.nist_hcn,1)
	  if (tunlsr_class.nist_hcn(k,1)==lines(li))
	    nist=tunlsr_class.nist_hcn(k,:);
	    % fprintf(' nm %10.5f nm\n', nist(2));
	    shift_nm_p_kPa = (nist(3)-nist(2))/13.3;
	    shft_nm = shift_nm_p_kPa * (tunlsr_class.our_hcn_p_Pa/1000);
%	    fprintf('line %d  sh %10.5f nm\n', lines(li), shft_nm);
	    gas_wl_nm = nist(2) + shft_nm;
	    % fprintf('nm %10.5f nm\n', gas_wl_nm);
	    gas_freqs_Hz(li) = c_mps./(gas_wl_nm*1e-9);

            norm_xmit(li) = nist(6);
	    if (t)
  	      fprintf('P%02d = %d MHz', lines(li), round(gas_freqs_Hz(li)/1e6));
  	      fprintf(' = %.4f nm\n', c_mps/gas_freqs_Hz(li)*1e9);
	    end
	    break;
	  end
	end
      end
    end

    function [gas_freqs_Hz norm_xmit] = gasline_lookup(gastype, lines)
      import nc.*	     
      if (gastype=='a')
        [gas_freqs_Hz norm_xmit] = tunlsr_class.acetlyne_lookup(lines);
      else
        [gas_freqs_Hz norm_xmit] = tunlsr_class.hcn_lookup(lines);
      end
    end
     
    function v = is_tunlsr(idn_rsp) % static
      flds=serclass.parse_idn_rsp(idn_rsp);
      flds{1}
      v = (length(flds)>1)&&(strcmp(flds{1},'TUNLSR'));
    end
    
    % for thremistor in interferometer chamber
    function v = intf_therm_C2V(temp_C)
      B = 3380;
      K0 = 273.1;      
      v = 10e3 * exp( B * (1/(temp_C + K0) - 1/(25+K0))) * 100e-6;
    end

    % for thremistor in interferometer chamber
% see wtc3293_dsply.pdf.  B version of Steinhard eqn is:
% 1/T = 1/T0 + 1/B * ln(R/R0)
% Where R is resistance of thermistor.  R = V/Ibias.
% wtc3293 generates constant current (Ibias) of 100uA.
% R0 is 10kOhm.
    function temp_c = intf_therm_V2C(V)
      B = 3380;
      K0 = 273.1;
% 'DBG'
% v / 10e3 / 100e-6
% Circuit designed so at room temp, thermistor Voltage is close to 1mV 
      temp_c = 1/(log(V / 10e3 / 100e-6)/B + 1/(25+K0))-K0;
    end

    function temp_C = intf_therm_adc2C(adc)
      opin_V = 3.3*adc/4096 / 3.3; % opamp gain is 3.3
      rtherm = 10e3*(1-opin_V)./opin_V;
      B = 3380;
      K0 = 273.1;
% 'DBG'
% v / 10e3 / 100e-6
      temp_C = 1./(log(rtherm / 10e3)/B + 1/(25+K0))-K0;
    end

    % for thermistor in DFB laser
    function c = dfb_temp_adc2c(adc)
      % laser therm is top part of resistive divider to 1V.
      v = adc*3.3/(2^12);
      r = 10e3*(1-v)/v;
      B = 3950;
      c = 1/(1/(25-nc.tunlsr_class.DFB_K0C) + 1/B*log(r/10e3))+nc.tunlsr_class.DFB_K0C;
    end
    

  end

  methods

    % CONSTRUCTOR
    function me = tunlsr_class(port, opt)
    % desc: returns handle to tunlsr in "open" state if possible
      import nc.*
      if (nargin<2)
	opt.dbg=0;
      end
      me.idn = [];
      me.devinfo.num_chan=2;
      me.port_str = port;
      me.ser = nc.ser_class(port, 115200, opt);
      if (me.ser.isopen())
        me.idn = me.ser.get_idn_rsp;
        me.devinfo = me.parse_idn(me.idn);
        pause(0.05);
        me.ser.flush;

        % some itla commands take a long time, so allow two minutes!
        me.ser.set_cmd_params(1000, 60000);
        % if tunlsr responds with any of these keywords, there is a bug in this class!
        me.ser.set_do_cmd_bug_responses({'ERR: ambiguous', 'ERR: syntax', 'ERR: bad cmd', 'ERR: no int'});
        me.get_sample_hdr;
        me.get_settings;
      end
    end

    function devinfo = parse_idn(me, idn)
      import nc.*
      flds=regexp(idn.irsp, '\S+', 'match');
      num_flds = length(flds);
      model=0;
      if (num_flds>=2)
        model = parse_word(flds{2}, '%d', model);
      end

      % default TUNLSR
      devinfo.name='';
      devinfo.num_chan = 1;

      k=1;			   
      if (k>num_flds)
	return;
      end
      devinfo.name = flds{1};

      k=2;
      if (k>num_flds)
	return;
      end
      devinfo.model = sscanf(flds{2},'%d',1);
      
      % C1
      k=3;
      devinfo.num_chan  = parse_word(flds{k}, '%d', 2);

      function v=parse_word(str, fmt, default) % nested
        [v ct]=sscanf(str, fmt, 1);
        if (~ct)
         v = default;
        end
      end

    end

    % DESTRUCTOR
    function delete(me)
      if (me.isopen)
	me.close;
      end
    end

    function set_io_dbg(me, en)
      me.ser.set_dbg(en);
    end

    function close(me)
      me.ser.close;
    end

    function f=isopen(me)
      f=me.ser.isopen;
    end

    function open(me, port)
    % inputs:
    %   port: optional string.  If omitted, uses port previously used
      import nc.*
      if (nargin>1)
        me.port = port;
      end
      opt.dbg = me.dbg;
      me.ser.open(me.port, 115200, opt);
    end


    function v=convert_units(me, v)
    % To make the embedded code run faster, when it prints data, it uses only integers.
    % For example, it prints out the phase error in units of tenths of degrees, not degrees.
    % It's the job of this higher-level code to convert it to sane units.
    % This code also translates the header labels so they have proper units as the suffixes.

      if (me.cols.time_hus) % time in units of 100us, convert to s
        v(me.cols.time_hus) = v(me.cols.time_hus)/10000;
      end
      if (me.cols.ph_x10)
	v(me.cols.ph_x10)=v(me.cols.ph_x10)/10; % phase in units of 0.1 deg, convert to deg
      end

      if (me.cols.wl1_mag2m)
	v(me.cols.wl1_mag2m)=v(me.cols.wl1_mag2m)/1000; % phase in units of madc
      end
      if (me.cols.wl2_mag2m)
	v(me.cols.wl2_mag2m)=v(me.cols.wl2_mag2m)/1000; % phase in units of madc
      end

      if (me.cols.ph_err_x10)
	v(me.cols.ph_err_x10)=v(me.cols.ph_err_x10)/10; % phase in units of 0.1 deg, convert to deg
      end

       if (me.cols.ph_err_avg_x10)
	 v(me.cols.ph_err_avg_x10)=v(me.cols.ph_err_avg_x10)/10; % 0.1 deg to deg
       end
       if (me.cols.fine_ph_err_x10)
	 v(me.cols.fine_ph_err_x10)=v(me.cols.fine_ph_err_x10)/10; % 0.1 deg to deg
       end

% % Now this class does not convert units of intf temp, so the conversion
% % can be calibrated by calibration code (tst_ramp4.m)
% 
%       % this is probably obsolete
%        if (me.cols.intf_temp)
% 	 v(me.cols.intf_temp)=tunlsr_class.intf_therm_v2c(3.3*v(me.cols.intf_temp)/2^12); % convert adc units to C
%        end
%tunlsr_class.intf_therm_v2c(3.3*v(me.cols.intf_temp_madc)/1000/2^12); % convert milli-adc units to C
       if (me.cols.intf_temp_madc)
  	 v(me.cols.intf_temp_madc)= v(me.cols.intf_temp_madc)/1000;
       end

       if (me.cols.tunepwr)
	 % adc is 12 bits.  ref is 3.3V.  The TIA has a 33k resistor.
	 % I checked with thor labs meter, seems to be only 90% of actual pwr, don't know why
	 v(me.cols.tunepwr)=(3.3*v(me.cols.tunepwr)/2^12)/33e3/0.90*1e6; % convert adc units to to uW
       end
     end

     function v=sample(me, nsamps)
       for k=1:3
	 [rsp err]= me.ser.do_cmd(['samp' char(13)]);
	 v = me.ser.parse_matrix(rsp);
	 if (length(v)==me.samp_hdr_len)
	   v=me.convert_units(v);
  	   if (length(v)~=me.samp_hdr_len)
	     fprintf('conv unit bug\n');
           end
	   return;
	 end
	 fprintf('\nERR tunlsr: bad tunlsr samp rsp!\n');
	 fprintf('             got %d numbers insted of %d\n', length(v), me.samp_hdr_len);
	 nc.uio.print_all(rsp);
	 if (k==3)
	   me.close();
	   error('BUG');
	 end
	 me.ser.write(['i' char(13)]);
	 pause(1);
	 me.ser.flush();
	 fprintf('TC: retry\n');
       end
       v=zeros(1,me.samp_hdr_len);
     end

     function v=meas_gas(me)
       v=me.samp;
       v=v(6);
     end


     function v=meas_dets(me)
       % desc: measures the four detectors in adc units      
       % returns: v = 1x4 row vector. all -1 if err
       fprintf('TODO: this is obs or wrong\n');
       error('fail');
       v=me.samp;
       v=v(1:4);
     end


     % thermistor in interferometer chamber
     function temp_adc = meas_intf_temp_adcval(me)
       v=me.samp;
       temp_adc = v(me.cols.intf_temp);
     end

     % thremistor in interferometer chamber
     function temp_C = meas_intf_temp_C(me)
       temp_C = me.intf_therm_V2C(3.3*me.meas_intf_temp_adcval/2^12);
       return;
     end



 %% old way... uses ds1626 temperature chip      
 %%      [irsp err]= tunlsr_class.do_cmd(me.ser, ['tmp' char(13)]);
 %%      v = tunlsr_class.parse_matrix(irsp)/16;
 %
 %      % new way... adc reads thermistor
 %      for k=1:10
 %        [irsp err]= me.ser.do_cmd(['adc' char(13)]);
 %        d = tunlsr_class.parse_matrix(irsp);
 %        if (length(d)==1)
 %          temp_c = tunlsr_class.therm_v2c(3.3*d/2^12);
 %          return;
 %        end
 %        fprintf('ERR tunlsr: bad tunlsr adc rsp!\n');
 %        irsp
 %        pause(1);
 %        me.ser.flush();
 %      end
 %      temp_c = 0;
 %    end

     function err = cfg_fsr(me, fsr0_Hz, ctr_Hz, temp0_C, tempdep_HzpC, gvd_pspnmkm)
     % desc: sets constants from which FSR is dynamically calculated based on
     %       current temperature and dispersion
     % syntax for low lvl cmd:
     %   cfg fsr <ctr_fsr_kHz> <ctr_MHz> <ctr_temp_C> <ctr_tempdep_kHz/C> <ps/nmkm>
       err =0;	     
       cmd = sprintf('cfg fsr %.3f %.3f %.3f %.3f %.3f\r', ...
		     fsr0_Hz/1e3, ctr_Hz/1e6, temp0_C, tempdep_HzpC/1000, gvd_pspnmkm);
       [rsp err]= me.ser.do_cmd(cmd);
     end


     function v = set_step(me, isref, steptype, itr, param, amts, lens)
 % desc: sets up a perturbation
 % inputs:
 %   isref: 0=tunlsr, 1=reflsr
 %   steptype: 'r'=ramp, 's'=step, 'n'=none
 %   amts: vector of amounts.  Units depend on param
 %   param: a single character.  One of:
 %       'f'=FM,
 %       't'=nom laser fream setting (tune)
 %       'F'=freq goal
 %   lens: vector of lengths in iterations
       if ((me.idn.fwver(1)<2)&&(me.idn.fwver(2)<1))
         cmd = sprintf('cal step %s %d %s', steptype, round(itr), param);
       else
	 cmd = sprintf('step %d %s %d %s', isref, steptype, round(itr), param);
       end
       for k=1:length(amts)
	 cmd = [cmd sprintf(' %.2f %d', amts(k), lens(k))];
       end
       cmd = [cmd char(13)];
       [rsp err]= me.ser.do_cmd(cmd);
       nc.uio.print_all(rsp);
     end

     function settings = get_settings(me, dacval)
     % querries device for settings.  caches settings in object (me).  also returns settings.
       [rsp err]= me.ser.do_cmd(['set' char(13)]);
       settings.num_chan   = me.devinfo.num_chan; % to make it easy
       settings.isdfb      = me.ser.parse_keyword_val(rsp,'isdfb',[]);

       settings.fsr_Hz     = me.ser.parse_keyword_val(rsp,'fsr_kHz',[])*1e3; % current FSR (changes)
       settings.ref_itr_lim = me.ser.parse_keyword_val(rsp,'ref_itr_lim',[]);
       settings.fdbk_gain  = me.ser.parse_keyword_val(rsp,'fdbk gain',[]);
%       settings.fdbk_gas   = me.ser.parse_keyword_val(rsp,'fdbk gas',[]);
       settings.extlsr_MHz = me.ser.parse_keyword_val(rsp,'ext',[]);
       settings.freq_MHz   = me.ser.parse_keyword_val(rsp,'freq',[]); % the fdbk goal
       settings.reflaser_MHz = me.ser.parse_keyword_val(rsp,'ref',[]);
       settings.foff_MHz   = me.ser.parse_keyword_val(rsp,'foff',[]);
       settings.dbg        = me.ser.parse_keyword_val(rsp,'dbg',[]);
       settings.tunlsr_goal_deg = me.ser.parse_keyword_val(rsp,'deg',[]);
       settings.fm_d_lim   = me.ser.parse_keyword_val(rsp,'fm_d_lim',[]);
       settings.tunedmin   = me.ser.parse_keyword_val(rsp,'tunedmin',[]);
       settings.itla_info_vld = 0;



       idx = regexpi(rsp, 'trig');
       ct=0;
       if (idx)
	 [a ct] =sscanf(rsp(idx(1)+5:end),'%c %g', 2);
       end
       if (ct==2)
	 settings.trig.type   = a(1);
	 settings.trig.thresh = a(2);
       else
	 settings.trig.type = 'n';
	 settings.trig.thresh = 0;
       end

       [rsp err]= me.ser.do_cmd(['cfg set' char(13)]);
       settings.cfg.gaslines = me.ser.parse_keyword_val(rsp,'gaslines',[]);
       if (size(settings.cfg.gaslines,2)>=7)
         settings.cfg.gaslines(:,7) = settings.cfg.gaslines(:,7)/1e6;
       end


       settings.samp_pd_us = me.ser.parse_keyword_val(rsp,'samppd',[]);
       settings.refpure = me.ser.parse_keyword_val(rsp,'refpure',[]);
       settings.erravg  = me.ser.parse_keyword_val(rsp,'erravg',[]);
       settings.ph_avg_pd_us = me.ser.parse_keyword_val(rsp,'phavgpd',[]);
       settings.cfg.fsr     = me.ser.parse_keyword_val(rsp,'fsr',[]);
       settings.cfg.tomem   = me.ser.parse_keyword_val(rsp,'tomem',[]);
       settings.cfg.usebeat = me.ser.parse_keyword_val(rsp,'usebeat',0);
       iqmap    = me.ser.parse_keyword_val(rsp,'iqmap',[]);
       settings.iqmap = reshape(iqmap, 9, []).';

       v = me.ser.parse_keyword_val(rsp,'reftemp',[]);
       if (length(v)==2)
         settings.reftemp_coarse = v(1);
         settings.reftemp_fine   = v(2);
       end

       [rsp err]= me.ser.do_cmd(['capa' char(13)]);
       me.capa.tomem_max = me.ser.parse_keyword_val(rsp,'tomem_max',[]);

       me.settings = settings;
       me.get_laser_set;
     end

     function set_tomem(me, en)
       me.ser.do_cmd(sprintf('cfg tomem %d\r', en));
       me.settings.cfg.tomem=en;
     end

     function set = cal_set_downsampling(me, ds)
	me.ser.do_cmd(sprintf('cfg ds %d\r', ds));
        me.settings.cal.downsamp = ds;
     end

     function bias = set_dfb_bias(me, bias)
       [rsp err]=me.ser.do_cmd(sprintf('dfb bias %d\r', bias));
       bias = me.ser.parse_matrix(rsp);
     end
     function bias = set_dfb_isobias(me, biasset)
       [rsp err]=me.ser.do_cmd(sprintf('dfb isobias %d\r', biasset));
       bias = me.ser.parse_matrix(rsp);
       if (bias ~= biasset)
	 fprintf('tunlsr ERR: tried setting bias to %d but only at %d\n', ...
		 biasset, bias);
       end				      
     end

     function attn = set_dfb_attn(me, attnset)
       [rsp err]=me.ser.do_cmd(sprintf('dfb attn %d\r', attnset));
       attn = me.ser.parse_matrix(rsp);
       if (attn ~= attnset)
	 fprintf('tunlsr ERR: tried setting attn to %d but only at %d\n', ...
		 attnset, attn);
       end				      
     end

     function tec = set_dfb_tec(me, tecset)
       [rsp err]=me.ser.do_cmd(sprintf('dfb tec %d\r', tecset));
       tec = me.ser.parse_matrix(rsp);
       if (tec ~= tecset)
	 fprintf('tunlsr ERR: tried setting tec to %d but only at %d\n', ...
		 tecset, tec);
       end				      
     end

     function set_dfb_freq_hz(me, hz)
       [rsp err]=me.ser.do_cmd(sprintf('freq %d\r', round(hz/1e6)));
 % uio.print_all(rsp);				       
     end


     function set_itla_cleansweep_GHz(me, isref, range_GHz)
       if (isref)
	 cmd = sprintf('ref cleansweep %d\r', range_GHz);
       else
         cmd = sprintf('laser cleansweep %d\r', range_GHz);
       end
       [rsp err]=me.ser.do_cmd(cmd,'','ERR');
       if (~err)
         if (isref)
           me.settings.itla.ref_cleansweep_GHz = range_GHz;
         else
           me.settings.itla.cleansweep_GHz = range_GHz;
         end
       end
     end

     function temp = set_reftemp(me, coarse, fine)
     % sets temp setting of reference laser
       cmd = sprintf('cfg reftemp %d %d\r', coarse, fine);
       [rsp err]=me.ser.do_cmd(cmd);
       me.settings.reftemp_coarse = coarse;
       me.settings.reftemp_fine = fine;
     end

     function set = get_otherlsr_set(me, temp)
       [rsp err]=me.ser.do_cmd(sprintf('otherlsr set\r'));
%     settings.temp  = me.ser.parse_keyword_val(rsp,'temp',[]);
     end

     function set = set_laser_en(me, en)
       me.settings.laser_en(2) = en;
       [rsp err]=me.ser.do_cmd(sprintf('laser en %d\r', en));
     end

     % laser iface
     function set = set_pwr_dBm(me, dBm)
	     error('depricated.  Use set_itla_pwr instead.');
     end

     function str = get_fwver(me)
       str = me.idn.fwver_str;
     end

     function [f_lo f_hi finetune_max] = get_laser_capabilities_Hz(me)
       % finetune_max: the max value in Hz to which the laser frequency fine tune offset may be settings.
       %               the overall range of fine tuning is -finetune_max ... +finetune_max

       [rsp err]= me.ser.do_cmd(['capa' char(13)]);
       me.capa.tomem_max = me.ser.parse_keyword_val(rsp,'tomem_max',[]);


       [rsp err]=me.ser.do_cmd(['laser capa' char(13)]);
       v = me.ser.parse_matrix(rsp);
       if (length(v)~=3)
	 fprintf('ERR: tunlsr_class.get_laser_capabilities_hz: bad rsp:\n');
	 nc.uio.print_all(rsp);
	 f_lo = 0;
	 f_hi = 0;
	 finetune_max = 0;
	 return;
       end
       f_lo         = v(1)*1e6;
       f_hi         = v(2)*1e6;
       finetune_max = v(3)*1e6;
       me.capa.finetune_max = finetune_max;
     end

     function set_dfb_const(me, const)
       [rsp err]= me.ser.do_cmd(['dfb const' sprintf(' %g', const) char(13)]);
     end

     function set = get_dfb_set(me, dacval)
       [rsp err]= me.ser.do_cmd(['dfb set' char(13)]);
       settings.attn   = me.ser.parse_keyword_val(rsp,'attn',[]);
       settings.tec    = me.ser.parse_keyword_val(rsp,'tec',[]);
       settings.bias   = me.ser.parse_keyword_val(rsp,'bias',[]);
       settings.const  = me.ser.parse_keyword_val(rsp,'const',[]);
       settings.nom_freq_Hz = me.ser.parse_keyword_val(rsp,'freq_MHz',[])*1e6;
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

       if (lsr_idx==1)
	 ldesc = 'refsr';
         pcol = me.cols.ref_pwr;
       else
	 ldesc = 'tunsr';
         pcol = me.cols.tun_pwr;
       end

       h_i = 1;
       h_l = min_itrlim;


       h = zeros(h_l,1);

       settle_start = tic;
       if (verbose)
         fprintf('waiting for power of %s to settle\n', ldesc);
       end
       % NOTE: wl1 is tunable laser.  wl2 is reference.

%       mag_pre=0;
       pwr_pre=0;
       ok_ctr=0;
       for itr=1:1000
%	 lset = me.get_laser_set;
%	 if (isref)
%	   pwr_dbm = lset.ref_pwr_dbm;
%         else
%	   pwr_dbm = lset.meas_pwr_dbm;
%         end
	 v = me.sample(1);
	 % assumes wl1 is stable.
	 ph = v(me.cols.ph_x10);

%	 mag = util.iff(col, sqrt(v(col)), 1);
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

	 % mag  = util.iff(me.cols.wl2_mag2, sqrt(v(me.cols.wl2_mag2)), 1);
         if (verbose)
%  	   fprintf('   laser pwr %.2f  mag %.1f  change %.3f%%\n', pwr_dBm, mag, change_pct);
  	   fprintf('   laser  pwr %d  ch %.3f%%\n',  pwr, pch_pct);
         end
	 pause(0.025);
%	 mag_pre = mag;
	 pwr_pre = pwr;
       end
%       er = (ok_ctr<=4);
       if (er && verbose)
         fprintf('tunlsr_class.wait_for_stability(): ERR: itla laser is stuck!\n');
       end
       settle_s = round(toc(settle_start));
       if (verbose)
         fprintf('settling took %g seconds = %g min\n', settle_s, settle_s/60);
       end
     end

     function get_laser_set(me)
     % desc: gets itla laser settings, caches and returns them
       import nc.*
       for c=1:me.devinfo.num_chan
	 [rsp err]=me.ser.do_cmd(sprintf('itla %d set\r', c-1));
         me.settings.cal.itla_fm(c)               = me.ser.parse_keyword_val(rsp,'fm',0);
	 me.settings.cal.itla_en(c)               = me.ser.parse_keyword_val(rsp,'en',0);
         me.settings.cal.itla_cleansweep_GHz(c)   = me.ser.parse_keyword_val(rsp,'cleansweep',0);
	 me.settings.cal.itla_pwr_dBm(c)      = me.ser.parse_keyword_val(rsp,'pwr_dBmx100',-100)/10;
	 me.settings.cal.itla_mode(c)         = me.ser.parse_keyword_val(rsp,'mode','d');
	 me.settings.cal.itla_grid_MHz(c)     = me.ser.parse_keyword_val(rsp,'grid_MHz',[]);
	 me.settings.cal.itla_f0_MHz(c)       = me.ser.parse_keyword_val(rsp,'f0_MHz',0);
	 me.settings.cal.itla_freq_MHz(c)     = me.ser.parse_keyword_val(rsp,'freq_MHz',0);
         me.settings.cal.itla_chan(c)         = me.ser.parse_keyword_val(rsp,'chan',1);
	 me.settings.cal.itla_finetune_MHz(c) = me.ser.parse_keyword_val(rsp,'finetune_MHz',0);

	 if (c==1)
	   [rsp err]=me.ser.do_cmd(['ref set' char(13)],[],'ERR');
	   me.settings.reflsr_attn_dB    = me.ser.parse_keyword_val(rsp,'attn',0);
	   rmode = me.ser.parse_keyword_val(rsp,'rmode','?');
	   me.settings.fdbk_en(1)      = me.ser.parse_keyword_val(rsp,'locken',[]);
% TODO: may be nice to change from gas_gain to gain
	   me.settings.ref.gas_gain    = me.ser.parse_keyword_val(rsp,'gas_gain',[]);
 	   % me.ser.parse_keyword_val(rsp,'gas_igain',[])]; % seem to have deleted this
           me.settings.ref.freq_MHz    = me.ser.parse_keyword_val(rsp,'freq_MHz',[]);

           me.settings.ref.goal            = me.ser.parse_keyword_val(rsp,'goal',[]); % new in 1.5
           me.settings.laser_en(1)         = 1; % TODO: fix
           me.settings.attn_dB(1) = me.ser.parse_keyword_val(rsp,'attn',0);
         end
	 if (c==2)
	   [rsp err]=me.ser.do_cmd(['laser set' char(13)],[],'ERR');
  	   rmode = me.ser.parse_keyword_val(rsp,'rmode','?');
	   me.settings.fdbk_en(2) = (rmode=='l');
           me.settings.attn_dB(2) = me.ser.parse_keyword_val(rsp,'attn',0);
           me.settings.laser_en(2)         = 1; % TODO: fix
         end
       end
       me.settings.itla_info_vld = 1;
     end


    function b = laser_islocked(me, lsr_idx)
      me.ser.do_cmd('l'); % laser menu
      rsp = me.ser.do_cmd('s'); % print status
      b = me.ser.parse_keyword_val(rsp, 'locked',0);
    end

     function status = get_status(me)
       [rsp err]= me.ser.do_cmd(['stat' char(13)]);
       status.laser_locked(1) = me.ser.parse_keyword_val(rsp,'ref_locked',0);
       status.laser_locked(2) = me.ser.parse_keyword_val(rsp,'tun_locked',0);
       % status.ref_st     = me.ser.parse_keyword_val(rsp,'ref_st',0);
       % status.ref_pwr_err_pct = me.ser.parse_keyword_val(rsp,'ref_pwr_err_pct',100);
     end

     function [n str] = get_sample_hdr(me)
       import nc.*
     % desc: headers for data returned by run_read
       [rsp err]= me.ser.do_cmd(['runhdr' char(13)]);
       idxs=[0 regexp(rsp, '\n')];
       for k=1:(length(idxs)-1)
         str = rsp(idxs(k)+1:idxs(k+1)-1);
         hdrs_ca = regexp(str, '\w*', 'match');
         n = length(regexp(str,' '))+1;
         if (n>4)

           me.samp_hdr_len = n;

           me.cols.time_hus  = vars_class.datahdr2col(str, 'time_hus');
           if (me.cols.time_hus)
             hdrs_ca{me.cols.time_hus}='time_s';
           end

           me.cols.ph_x10      = vars_class.datahdr2col(str, 'ph_x10');
           if (me.cols.ph_x10)
             hdrs_ca{me.cols.ph_x10}='ph_deg';
           end


           me.cols.wl1_mag2m     = vars_class.datahdr2col(str, 'wl1_mag2m');
           if (me.cols.wl1_mag2m)
             hdrs_ca{me.cols.wl1_mag2m}='wl1_mag2';
           end
           me.cols.wl2_mag2m     = vars_class.datahdr2col(str, 'wl2_mag2m');
           if (me.cols.wl2_mag2m)
             hdrs_ca{me.cols.wl2_mag2m}='wl2_mag2';
           end

           me.cols.ref_pwr   = vars_class.datahdr2col(str, 'ref_pwr');
           me.cols.tun_pwr   = vars_class.datahdr2col(str, 'tun_pwr');
           me.cols.gas       = vars_class.datahdr2col(str, 'gas');

           me.cols.ph_err_x10    = vars_class.datahdr2col(str, 'ph_err_x10');
           if (me.cols.ph_err_x10)
             hdrs_ca{me.cols.ph_err_x10}='ph_err_deg';
           end

           me.cols.ph_err_avg_x10    = vars_class.datahdr2col(str, 'ph_err_avg_x10');
           if (me.cols.ph_err_avg_x10)
             hdrs_ca{me.cols.ph_err_avg_x10}='ph_err_avg_deg';
           end

           me.cols.fine_ph_err_x10    = vars_class.datahdr2col(str, 'fine_ph_err_x10');
           if (me.cols.fine_ph_err_x10)
             hdrs_ca{me.cols.fine_ph_err_x10}='fine_ph_err_deg';
           end



           % % Now this class does not convert units of intf temp, so the conversion
           % % can be calibrated by calibration code (tst_ramp4.m)
           % 
           %        % this prob obsolete
           %        me.cols.intf_temp     = vars_class.datahdr2col(str, 'intf_temp');
           %        if (me.cols.intf_temp)
           %          hdrs_ca{me.cols.intf_temp}='intf_temp_C';
           %        end
           %        % above is obsolete because of the following
           me.cols.intf_temp_madc = vars_class.datahdr2col(str, 'intf_temp_madc');
           if (me.cols.intf_temp_madc)
             hdrs_ca{me.cols.intf_temp_madc}='intf_temp_adc';
           end

           me.cols.tunepwr       = vars_class.datahdr2col(me.samp_hdr, 'tunepwr');

           str = cell2mat(cellfun(@(x) [' ' x], hdrs_ca, 'UniformOutput', false));
           str = str(2:end);

           me.samp_hdr = str;
           return;
         end
       end

       fprintf('ERR: tunlsr gave bad rsp to rundhdr command:\n');
       uio.print_all(rsp);
       error('FAIL');

     end

     function e = run_start(me, num_samps)
       % inputs:
       %   num_samps: num samples, or 0=run forever.  But the amount of data
       %             is this divided by the recording downsample rate.
       % returns:
       global DBG
       e=0;
       DBG.line=0;
       me.ser.flush();

%       samp_pd_us = round(1e6/fsamp_hz);
%       if (samp_pd_us ~= me.settings.samp_pd_us) 
%         cmd = sprintf('cmd cfg samppd %d\r', samp_pd_us);
%	 cmd
%         [str err]= me.ser.do_cmd(cmd);
%	 me.settings.samp_pd_us = samp_pd_us;
%       end

       [str err]= me.ser.do_cmd(['runhdr' char(13)]);
       hdrs = regexp(str, '\S+', 'match');
       if (length(hdrs)<2)
	 fprintf('ERR: tunlsr gave bad rsp to rundhdr command:\n');
	 uio.print_all(str);
         e=1;
	 error('FAIL');
       end
       me.running=1;

       cmd = sprintf('run %d\r', num_samps);
       me.ser.write(cmd);
       [rsp fk to]=me.ser.read(1000, 1000, char(10)); % skip cmd echo
       % uio.print_all(rsp);
     end

     function v = run_wait(me)
       global DBG
       while(1)
	 pause(1);
	 me.ser.write('?');
	 for k=1:100
	   [me.ser line done] = me.ser.accum_line;
	   if (~isempty(line))
	     break;
	   end
	 end
	 if (~isempty(line) && (line(1)=='y'))
	   break;
	 end
	 if (strfind(line, 'ERR:'))
	   fprintf('ERR: tunlsr.run_read() line %d got error msg:\n', DBG.line);
	   uio.print_all(line);
	 end
	 'DBG: got this line instead of y:'
	 line
       end
     end

     function v = run_read(me)
       global DBG
       if (me.settings.cfg.tomem && (mod(DBG.line, 200)==100))
	 % fprintf('DBG: c at line %d\n', DBG.line);
	 me.ser.write('c'); % continue
       end
       while(1)
	 [me.ser line done] = me.ser.accum_line;
	 if (~isempty(line))
	   if (strfind(line, 'ERR:'))
	     fprintf('ERR: tunlsr.run_read() line %d got error msg:\n', DBG.line);
	     uio.print_all(line);
	   end
	   [v ct]=sscanf(line, '%g');
	   if (ct)
	     DBG.line=DBG.line+1;
	   end
%	   uio.print_all(line);
	   if (ct~=me.run_rd_len)
	     fprintf('ERR: tunlsr.run_read() line %d parsed %d nums (not %d) from device rsp:\n', DBG.line, ct, me.run_rd_len);
	     uio.print_all(line);
	   else
	     v = me.convert_units(v);
	     if (length(v)~=me.run_rd_len)
	       fprintf('BUG: tunlsr.run_read() convert_units screwed up len, now %d', length(v));
             end
	   end
	   v = v.';
	   return;
 %        elseif (~done)
 %          DBG.line
	 end
	 if (done)
	   v=[];
	   return;
	 end
       end
     end

     function v = run_stop(me)
       me.running=0;
       n=[0 0];
       v=n;
       for k=1:4
	 [rsp fk to]=me.ser.read(1000, 1000, char(10));
	 if (to)
	   break;
	 end
	 [n ct]=sscanf(rsp, '%g');
	 if (ct==1)
	   v = n.';
 %          v(1)=sqrt(v(1)); % was mean-sq, now rms
	   break;
	 end
       end
% fprintf('DBG: tunlsr_class.run_stop() writing CR\n');
       me.ser.write(char(13));
       pause(0.1);
% fprintf('DBG: tunlsr_class.run_stop() will flush\n');
       me.ser.flush;
% fprintf('DBG: tunlsr_class.run_stop() done flush\n');
     end

     function err = set_tunlsr_gas(me, m)
       'DBG set tunlsr gas'
       cmd = ['laser gas' sprintf(' %d', m) char(13)];
       cmd
     end

     function err = set_itla_pwr_dBm(me, isref, dBm)
       if (isref)	      
         if (me.settings.laser_en(1) && (me.settings.itla.ref_mode=='w'))
  	   fprintf('ERR: You cant change Pure laser pwr when in whisper mode');
         end
         [rsp err]=me.ser.do_cmd(sprintf('ref pwr %d\r', round(dBm*100)));
       else
	 if (me.settings.laser_en(2) && (me.settings.itla.pure_mode=='w'))
  	   fprintf('ERR: You cant change Pure laser pwr when in whisper mode');
	 end
	 [rsp err]=me.ser.do_cmd(sprintf('laser pwr %d\r', round(dBm*100)));
       end
       v = me.ser.parse_matrix(rsp);
       if (length(v)==1)
	 if (isref)
	   me.settings.itla.ref_pwr_dBm = v/100;
	 else
	   me.settings.itla.pwr_dBm = v/100;
	 end
       end
     end

     function cal_set_laser_fm(me, lsr_idx, fm)
       if (nargin<3)
         error('insufficient number of arguments');
       end
       cmd = sprintf('itla %d fm %d\r', lsr_idx-1, fm);
       [rsp err] = me.ser.do_cmd(cmd);
       if (~err)
	 me.settings.cal.laser_fm(lsr_idx)=fm;
       end
     end

     function err = set_ref_st(me, st)
       [rsp err] = me.ser.do_cmd(sprintf('dbg refst %d\r', st));
     end

     function err = set_fdbk_dbg(me, en)
       [rsp err] = me.ser.do_cmd(sprintf('dbg fdbk %d\r', en));
     end

     function v = set_fdbk_gain(me, v)
       [rsp err] = me.ser.do_cmd(['fdbk gain' sprintf(' %g', v) char(13)]);
     end

     function v = dbg_set_tunlsr_goal_deg(me, deg)
       [rsp err] = me.ser.do_cmd(sprintf('dbg deggoal %d\r', deg));
       me.settings.tunlsr_goal_deg = deg;
       nc.uio.print_all(rsp);
     end

     function set_laser_fdbk_en(me, lsr_idx, en)
       if (lsr_idx==1)
         cmd=sprintf('ref locken %d\r', en);
       else
         modes='ul';
         mode=modes(logical(en)+1);
         cmd=sprintf('laser rmode %c\r', mode);	  
       end
       [rsp err] = me.ser.do_cmd(cmd,'','ERR');
       if (err)
	 fprintf('ERR: tunlsr_class.set_laser_fdbk_en failed\n');
       else
         me.settings.fdbk_en(lsr_idx)=en;
       end
     end

     function v = set_ref_rmode(me, mode)
       error('DEPRECATED: tunlsr_class.set_ref_rmode\n');
     end

     function v = set_laser_fdbk_goal(me, lsr_idx, goal)
% inputs:
%   For gas-based feedback:
%     goal.linenum: nist-assigned acetlyne gasline number
%     goal.offset_MHz: offset from mid-slope in MHz
%     goal.side: +1 = rising edge ( approx 250MHz above dip)
%                -1 = falling edge( approx 250MHz below dip)
       if (lsr_idx==2)
	 error('TODO: set_laser_fdbk_goal not implemeneted for lsr idx 2');
       end
       cmd=sprintf('ref goal %d %d %d\r', goal.linenum, goal.offset_MHz, goal.side);
       m = me.ser.do_cmd_get_matrix(cmd);
       if ((lsr_idx==1) && (length(m)==4))
         me.settings.ref.goal = m(1:3);
	 me.settings.ref.freq_MHz = m(4);
       end
     end

     function v = set_tunlsr_rmode(me, mode)
       error('OBSOLETE: tunlsr_class.set_tunlsr_rmode. use set_laser_fdbk_en.\n');
     end

     function set_intf_temp_c(me, temp_C)
       fprintf('ERR: currently this wire is disconnected!\n');
       me.close();
       error('fail');
       dac = round(nc.tunlsr_class.therm_C2V(temp_C) / 3.3 * 2^12);
       cmd = [sprintf('dbg dac 1 %d', dac) char(13)];
       [irsp err]= me.ser.do_cmd(cmd);
     end

     function v = set_pi_const(me, pp, ii)
       cmd = [sprintf('const %g %g', pp, ii) char(13)];
       [irsp err]= me.ser.do_cmd(cmd);
     end

     function err=set_foff_MHz(me, foff_MHz)
       cmd = sprintf('foff %d%c', round(foff_MHz), char(13));
       [irsp err]= me.ser.do_cmd(cmd);
     end

     function err=set_freq_MHz(me, f_MHz)
       % sets feedback goal of tunable laser
%       fprintf('DBG set_freq_MHz(%d): was %d\n', round(f_MHz), me.settings.freq_MHz);
       cmd = sprintf('freq %d%c', round(f_MHz), char(13));
       [rsp err]= me.ser.do_cmd(cmd);
%       uio.print_all(rsp);
%       r = me.ser.parse_matrix(rsp);
%       if (length(r)==1)
         me.settings.freq_MHz = f_MHz;
%       else
%         err=1;
%       end
     end

     function err=set_tunlsr_offset_MHz(me, offset_MHz)
       % sets feedback goal of tunable laser

       cmd = sprintf('foff %d%c', round(offset_MHz), char(13));
       [rsp err]= me.ser.do_cmd(cmd);
       %uio.print_all(rsp);
       r = me.ser.parse_matrix(rsp);
       if (length(r)==1)
         
       else
         err=1;
       end
     end


     function err=wait_for_ref_st(me, st, timo_s)
       s=tic;
       % fprintf('ref_st');		     
       while(1)
	 [rsp err]=me.ser.do_cmd(['ref set' char(13)]);	
	 ref_st = me.ser.parse_keyword_val(rsp,'state',[]);
	 % fprintf(' %d', ref_st);		     
	 if (ref_st==st)
	   err = 0;
           break;
	 end
         if (toc(s)>timo_s)
           err=1;
           return;
         end
         pause (0.5);
       end
     end

     function err=wait_for_lock(me, lsr_idx, timo_s)
       s = tic;
       err=0;
       while(1)
         stat=me.get_status;
         if (stat.laser_locked(lsr_idx))
  	   return;
         end
         if (toc(s)>timo_s)
           err=1;
           return;
         end
         pause (0.2);
       end
     end

     function err=cal_set_itla_channel(me, lsr_idx, ch)
       err=0;
       cmd = sprintf('itla %d chan %d\r', lsr_idx-1, ch);
       me.ser.set_cmd_params(1000, 120000); % 2 min
       m = me.ser.do_cmd_get_matrix(cmd, 0);
       me.ser.set_cmd_params(1000,  5000); % 5 sec
       if (~err)
	 me.settings.cal.itla_chan(lsr_idx) = m;
       end
     end


     function err=cal_set_itla_finetune_MHz(me, lsr_idx, MHz)
       err=0;
       if (length(MHz)~=1)
         fprintf('BUG: MHz param not of length 1\n');
         MHz
         me.close();
         error('BUG');
       end
       MHz=round(MHz);

       cmd = sprintf('itla %d fine %d%c', lsr_idx-1, MHz, char(13));

       me.ser.set_cmd_params(1000, 120000); % 2 min
       m = me.ser.do_cmd_get_matrix(cmd, 0);
       me.ser.set_cmd_params(1000,  5000); % 5 sec
       if (m~=MHz)
	 err=1;
       end
       % uio.print_all(rsp);
%       if (~err && ~isempty(strfind(rsp,'ERR')))
%	 err=1;
%       end
       me.settings.cal.itla_finetune_MHz(lsr_idx) = m;
%       if (~err)
%         r = me.ser.parse_matrix(rsp);
%         err = (length(r)~=1) || (r~=MHz);
%         if (~err)
%         end
%       end
     end
    
    function show_fdbk_set(me)
'will show set'
      [irsp err]= me.ser.do_cmd(['set' 13]);
irsp
%      uio.print_all(irsp);
    end




    function err = cal_set_itla_freq_MHz(me, lsr_idx, MHz)
      err=0;
      if (~me.settings.itla_info_vld)
        tic
        me.get_laser_set;
        'DBG: set_itla_freq_MHz(): getting laser settings takes:'
        toc
      end
      first_chan_MHz = me.settings.cal.itla_f0_MHz(lsr_idx);
      grid_MHz = me.settings.cal.itla_grid_MHz(lsr_idx);

      ch  = round(1 + (MHz - first_chan_MHz)/grid_MHz);
      fine_MHz = round(MHz - (first_chan_MHz + (ch-1)*grid_MHz));
      if (isempty(ch) || isempty(fine_MHz))
        fprintf('BUG: problem in tunlsr.set_itla_freq_Hz(%dMHz)', MHz);
        me.settings.itla
        ch
        fine_MHz
        me.close();
        error('BUG');
      end
      err  = me.cal_set_itla_channel(lsr_idx, ch);
%      pause(0.5);
      err2 = me.cal_set_itla_finetune_MHz(lsr_idx, fine_MHz);
      err = err || err2;
    end

    

    function err = cal_set_itla_mode(me, lsr_idx, mode)
    % actually this is the Pure Photonics mode: d or w
      err = 0;
      cmd = sprintf('itla %d mode %c\r', lsr_idx-1, mode);
      [irsp err]= me.ser.do_cmd(cmd);
      % nc.uio.print_all(irsp);
      if (~err)
        me.settings.cal.itla_mode(lsr_idx)=mode;
      end
    end


    function set_iqmap(me, iqmap)
      %  iqmap: 2x6
      iqmap2 = [iqmap zeros(2,3)];
      cmd = ['cfg iqmap' sprintf(' %.5e', reshape(iqmap2.',1,[])) char(13)];
      [rsp err]= me.ser.do_cmd(cmd);
    end
    function set_iqmap2(me, iqmap2)
      %  iqmap: 2x9
      cmd = ['cfg iqmap' sprintf(' %.5e', reshape(iqmap2.',1,[])) char(13)];
      [rsp err]= me.ser.do_cmd(cmd);
    end

    function cal_save_flash(me, pwd)
      % fprintf('\n\nTODO: implement tunlsr_class.cal_save_flash(pwd)\n');
      v=0;
      [rsp err]= me.ser.do_cmd(['cfg wflash' char(13)]);
      nc.uio.print_all(rsp);
    end

    function v = cal_set_gaslines(me, lsr_idx, fname, gaslines)
      %  gaslines: Nx7 (not inc std) or Nx8
      if (lsr_idx~=1)
        error('can only config ref gasline now');
      end
      me.ser.set_cmd_params(500, 500);
      me.ser.set_dbg(1,'tunlsr');
      [rsp err]= me.ser.do_cmd(['cfg gas ' fname char(13)]);

      for k=1:size(gaslines,1)
	r = gaslines(k,:);
	if (length(r)==7)
          r(8)=10;
        end
	if (   ((me.idn.fwver(1)==1)&&((me.idn.fwver(2)>=7)||(me.idn.fwver(3)>=0))) ...
            || ((me.idn.fwver(1)>=2)||(me.idn.fwver(2)>=3)||(me.idn.fwver(3)>=1)))
          cmd = [sprintf(' %d', r) char(13)]; % now MODAL
	elseif ((me.idn.fwver(1)>1)||(me.idn.fwver(2)>4)||(me.idn.fwver(3)>0))
	  r(7)=round(r(7)); % *1000000);
          cmd = ['cfg gas' sprintf(' %d', r) char(13)];
	else
	  fprintf('WARN: tunlsr_class.set_gaslines(): writing deprecated gaslines to device\n');
          cmd = ['cfg gas' sprintf(' %d', gaslines(k,1:6)) sprintf(' %g', gaslines(k,7)) char(13)];
	end
	for kk=1:4
	  [rsp err]= me.ser.do_cmd(cmd);
	  if (~err)
	    break;
	  end
	  fprintf('DBG: retry\n');
	  me.ser.set_dbg(1, 'tunlsr');
	  me.ser.write(char(13));
	  pause(0.5);
	  me.ser.flush();
	end
	pause(0.2); % otherwise embedded code drops chars. it cant read fast enough!
      end
      [rsp err]= me.ser.do_cmd(char(13));
      me.ser.set_cmd_params(1000, 60000);
      me.ser.set_dbg(0);
    end

    function v = set_const(me, const)
      cmd = ['dfb const' nc.uio.short_exp(sprintf(' %.6e', const(1:5))) sprintf(' %d', const(6)) char(13)];
      [rsp err]= me.ser.do_cmd(cmd);
      nc.uio.print_all(rsp);
    end

    function err = set_attn_dB(me, isref, attn_dB) 
      if (isref)
	cmd = [sprintf('ref attn %.2f', attn_dB) char(13)];
      else
	cmd = [sprintf('laser attn %.2f', attn_dB) char(13)];
      end
      [rsp err]= me.ser.do_cmd(cmd);
      if (~err)
        r = me.ser.parse_matrix(rsp);
        err = (length(r)~=1);
	if (~err)
	  if (isref)
	    me.settings.reflsr_attn_dB = r;
	  else
	    me.settings.tunlsr_attn_dB = r;
	  end
	  err = (r ~= attn_dB);
	end
      end
    end

    function v = set_attn_dac(me, isref, attn_dac)
    % for calibration purposes only
      cmd = sprintf('cfg attn %d %d%c', isref, attn_dac, char(13));
      [rsp err]= me.ser.do_cmd(cmd);
    end

  end    

end
