classdef pg300_cal_class < nc.pg300_class
% extends pg300 class with calibration functions (NuCrypt internal use)
  
  properties (Constant=true)
    JUNK = 0;
  end
  
  properties
    pwd
  end
  
  methods

    % CONSTRUCTOR
    function me = pg300_cal_class(arg1, arg2)
    % desc: pg300 constructor
      import nc.*
      args{1}=arg1;
      if (nargin==1)
        arg2.dbg=0;
      end
      me = me@nc.pg300_class(arg1, arg2);
    end
    
    function set_password(me, pwd)
      me.pwd = pwd;
      fprintf('pg300_cal_class dbg: SET PASSWORD\n');
    end
    
    function get_settings(me)
      me.get_settings@nc.pg300_class(); % superclass get settings
      rsp = me.ser.do_cmd(['cfg cal set' char(13)]);
      nd = me.devinfo.num_chan * me.devinfo.num_dlyrs_per_chan;
      for ch=1:nd
        me.settings.dlyr_coarse_dac(ch) = me.ser.parse_keyword_val(rsp,sprintf('dlyr %d c', ch),0);
        me.settings.dlyr_fine_dac(ch)   = me.ser.parse_keyword_val(rsp,sprintf('dlyr %d f', ch),0);
      end
    end
    
    function set_delayer_coarse_dac(me, dly_i, dac)
    % dly_i: 1-based index of delayer.  (usually there are two per spidly board)      
      [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg cal dlyr %d c %d\r', dly_i, dac));
      if (~err && (length(m)==1))
        me.settings.delayer_coarse_dac(ch) = m;
      end
    end
    
    function set_delayer_fine_dac(me, dly_i, dac)
    % dly_i: 1-based index of delayer.  (usually there are two per spidly board)      
      [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg cal dlyr %d f %d\r', dly_i, dac));
      if (~err && (length(m)==1))
        me.settings.delayer_fine_dac(ch) = m;
      end
    end


   function err=write_spline(me, fname, m)
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

    
   function set_voa_dB2dac_spline(me, voa_i, fname, spline)
   % inputs:
   %   spline: hxw matrix.  h = num pieces +1.  spline(1:h,1) are breaks;
   %           spline(2:end,2) are x^3 coef.  spline(2:end,3) are x^2 coef.
     err=1;
     w=size(spline,2);
     if (any(spline(1,2:end)))
       % compatible with old-format spline matricies that
       % assumed starting break was at zero.
       fprintf('DBG: old fmt spline\n');
       spline = [zeros(1,w); spline];
     end
     rsp = me.ser.do_cmd(sprintf('cfg voa %d\r', voa_i)); % set voa atten dB to dac mapping
     err = me.write_spline(fname, spline);
   end


    function err=set_delayer_cal(me, chan, fname, coarse, fine)
    % desc: Sets the calibration for the "fine" and "coarse" delay,
    %    which is a mapping from delay (typ -15ps .. +15 ps)
    %    to the dac value that drives FTUNE to cause that delay.
    % inputs:
    %   chan: one-based index of spline.
    %   fname: short file name of calibration file
    %   coarse: vector len 12 of coarse coefs
    %   fine: matrix representation of a spline.
      me.ser.do_cmd(sprintf('cfg cal dlyr %d w\r', chan));
      for c=1:12
        rsp = me.ser.do_cmd([num2str(coarse(c)) 13]);
      end
      err = me.write_spline(fname, fine);
    end

    
  end

end
