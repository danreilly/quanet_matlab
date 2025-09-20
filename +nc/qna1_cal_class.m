classdef qna1_cal_class < nc.qna1_class
% extends qna1 class with calibration functions (NuCrypt internal use)
  
  properties (Constant=true)
    JUNK = 0;
  end
  
  properties
    pwd
  end
  
  methods

    % CONSTRUCTOR
    function me = qna1_cal_class(arg1, arg2)
    % desc: qna1 constructor
      import nc.*
      args{1}=arg1;
      if (nargin==1)
        arg2.dbg=0;
      end
      me = me@nc.qna1_class(arg1, arg2);
    end
    
    function set_password(me, pwd)
      me.pwd = pwd;
      fprintf('qna1_cal_class dbg: SET PASSWORD\n');
    end
    
    function get_settings(me)
      me.get_settings@nc.qna1_class(); % superclass get settings
      rsp = me.ser.do_cmd(['cfg set' char(13)]);
      rsp
      me.settings.voa_calfiles = cell(me.devinfo.num_voa,1);
      me.settings.voa_splines = cell(me.devinfo.num_voa,1);
      for ch=1:me.devinfo.num_voa
        me.settings.voa_calfiles{ch} = me.ser.parse_keyword_val(rsp,sprintf('voa%d_calfile', ch),'');
        me.settings.voa_spline{ch} = me.ser.parse_keyword_val(rsp,sprintf('voa%d_spline', ch),[]);
      end
      rsp = me.ser.do_cmd(['cfg cal set' char(13)]);
      for ch=1:me.devinfo.num_voa
        me.settings.voa_dac(ch) = me.ser.parse_keyword_val(rsp,sprintf('voa %d', ch),0);
      end
    end
    

   function err=write_spline(me, fname, m)
   % inputs:
   %   chan: one-based index of spline.
   %   fname: short file name of calibration file
   %   m: matrix representation of a spline.
   %      one row for each peice of the spline.
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

   function set_voa_attn_dac(me, chan, dac)
     [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg cal voa %d %d\r', chan, dac));
     if (err==0)
       me.settings.voa_dac(chan)=m;
     end
   end

   function save_cfg_in_flash(me)
     me.ser.do_cmd(['cfg write' char(13)]);
   end

   function set_atten_spline(me, ch, fname, m)
   % inputs:
   %   ch: one-based index of channel
   %   fname: short file name of calibration file
   %   m: matrix representation of a spline.
     'writing cal'
     me.ser.set_dbg(1);
     rsp = me.ser.do_cmd(sprintf('cfg cal andvr c %d\r', ch));
     me.write_spline(fname, m);
     me.ser.do_cmd(sprintf('save\r'));
   end

    
  end

end
