
% The Thor Labs PM100d optical power meter
%

% When the PM100d is plugged in, it should appear in the device manager under
% USB Test and Measurement Devices / USB Test and Measurement Device (IVI)

% This should work on:
%   Strauss
%   Photon
%   Chunlaptop
%   Lektor


classdef pm100d_class < handle
  
  % instance members
  properties
    err  % 0=none, 1=debug cpds reads
    devinfo
  end
  
  properties (Constant=true)
    JUNK=0;
  end
  
  methods (Static=true)
     % matlab "static" methods do not require an instance of the class
    function err = inq()
      err = nc.pm100d_mex(0);
    end
  end

  methods

    % CONSTRUCTOR
    function me = pm100d_class()
    % desc: constructor
      me.err = nc.pm100d_mex(1);
      if (me.err)
        fprintf('ERR: pm100d_class(): constructor cant open pm100d\n');
      end
    end

    % DESTRUCTOR
    function delete(me)
      me.close;
    end

    function bool = isopen(me)
      bool = ~logical(me.err);
    end

    function close(me)
      nc.pm100d_mex(2);      
    end
    
    function model_sn = get_model_and_sn(me)
      model_sn = nc.pm100d_mex(6);
    end
    
    function pwr_dBm = meas_pwr_dBm(me)
      if (me.err) pwr_dBm=nan;
      else
        pwr_dBm = nc.pm100d_mex(3);
        if (isnan(pwr_dBm))
          fprintf('WARN: pm100d_class: meter returned NAN which we assume means -inf dB.\n');
          pwr_dBm = -inf;
        end
      end
    end

    function wl_nm = set_wavelen_nm(me, wl_nm)
      if (me.err) wl_nm=nan;
      else
        wl_nm = nc.pm100d_mex(5, wl_nm);
        pause(1);
      end
    end

    function temp_C = meas_temp_C(me)
    % desc: measures the temperature sensor that is inside the optical detector
    %       which plugs in to the DB9 port of the pm100d.  We have two different
    %       such optical detectors, for different wavelengths.
    %       This could be considered to be the ambient temperature.
      if (me.err) temp_C=nan;
      else temp_C = nc.pm100d_mex(4); end
    end

  end
  
end
