classdef tunlsrutils_class
% general purpose code sort of specific to the tunlsr project

  methods (Static=true)

    function gaslines = ask_gasline_nums(tvars)
      import nc.*
      fprintf('\n');
      fprintf('\nThe more gas lines you measure, the more accurate, but slower.\n');
      gas_set_choice = tvars.ask_choice('size of the set of gas lines (small, med, large, test, custom)', 'smltc', 'gas_set_choice');
      switch (gas_set_choice)
	case 'l'
	% ctr wl column from NIST SRM 2517a p 2
				% third column of pressure shift of center lines
				% from  Gilbert table 2, which does not list all lines
				%       line    wl(nm)   shft_slp(pm/kPa)
	  gaslines = 5:27;
	case 's'
				% small set for testing, should get good fits
	  gaslines = [9 12];
	case 't'
				% another small set for testing, should get good fits
	  gaslines = [13 15 17];
	case 'm'
				% subset to be faster
	  gaslines = [5 6 8 12 13 15 17 18 21 23 24 25 27];
	case 'c'
	  fprintf('enter 0 when done\n');
	  gaslines=[];
	  while(1)
            n=uio.ask('gas line', 0);
	    if (~n)
	      break
            end
           gaslines(end+1)=n;
          end
      end
    end


    function [tst_ref_choice reflaser_Hz reflaser_desc ...
	      tst_lsr_choice tunlaser_Hz tunlaser_desc] = ...
	     ask_lsr_choices(dut, refpure, ovars, tvars)
      import nc.*             
      if (refpure)
	reflaser_desc = 'pure';
      else
	reflaser_desc = 'dfb';
      end
      uio.print_wrap(sprintf('\nThe tunlsr device reports a %s reference laser inside.  But you could re-connect optics and use a DIFFERENT REFERENCE laser for the purpose of testing. (this is not common)', reflaser_desc));
      tst_ref_choice = tvars.ask_choice('test ref choice (internal, clarity, other external', 'tst_ref_choice','ico', 'i');
      switch tst_ref_choice
	case 'i'
	  reflaser_Hz = dut.settings.reflaser_MHz*1e6;
	  fprintf('\ntunlsr thinks reference laser is %.6fTHz\n', reflaser_Hz/1e12);

          status = dut.get_status;
          if (~status.laser_locked(1))
	    fprintf('ERR: tunlsr reports that its reference is NOT locked\n');
            uio.pause;
          end
%	  reflaser_desc = sprintf('%c %.3fMHz', dut.settings.ref.rmode, dut.settings.freq_MHz);
	  reflaser_desc = sprintf('%.3fMHz', dut.settings.ref.freq_MHz);
	case 'c'
	  reflaser_Hz = 194.36985e12;
	  reflaser_desc = 'clarity';
	  dut.set_ref_rmode(me, 'e');
	case 'o'
	  reflaser_desc = 'other';
	  dut.set_ref_rmode(me, 'e');
	  uio.print_wrap('\nEnter the frequency of your reference laser.  The value you enter will be recorded, but is not written to the reference laser as a setting.\n');
	  reflaser_Hz = tvars.ask_THz('ref freq (will not set)', reflaser_THz', 195.580765e12)*1e12;
      end


      uio.print_wrap('\nAlthough the tunlsr device has a pure tunable laser (not the reference) inside, you could recconect optics to use a DIFFERENT TUNABLE laser for the purose of testing. (this is not common.)');
      tst_lsr_choice = tvars.ask_choice('test lsr choice (internal, clarity, other external','tst_lsr_choice', 'ico', 'i');
      tunlaser_Hz = dut.settings.freq_MHz*1e6;

      if (~isempty(ovars))
        ovars.set('tst_ref_choice', tst_ref_choice);
        ovars.set('reflaser_Hz', reflaser_Hz);
        ovars.set('tst_lsr_choice', tst_lsr_choice);
        ovars.set('tunlaser_Hz', tunlaser_Hz);
      end

%      tunlaser_desc = sprintf('pure mode %c', dut.settings.itla.pure_mode);
      tunlaser_desc = sprintf('pure mode %c', dut.settings.cal.itla_mode(1));

    end


  end % static methods

end  
      
