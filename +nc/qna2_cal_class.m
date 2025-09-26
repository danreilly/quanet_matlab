classdef qna2_cal_class < nc.qna2_class
% extends qna2 class with calibration functions (NuCrypt internal use)
  
  properties (Constant=true)
    JUNK = 0;
  end
  
  properties
    pwd
  end
  
  methods

    % CONSTRUCTOR
    function me = qna2_cal_class(arg1, arg2)
    % desc: qna2 constructor
      import nc.*
      args{1}=arg1;
      if (nargin==1)
        arg2.dbg=0;
      end
      me = me@nc.qna2_class(arg1, arg2);
    end
    
    function set_password(me, pwd)
      me.pwd = pwd;
      fprintf('qna2_cal_class dbg: SET PASSWORD\n');
    end
    
    function get_settings(me)
      me.get_settings@nc.qna2_class(); % superclass get settings
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

      me.settings.efpc_ret_dac=zeros(me.devinfo.num_fpc,3);

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


   function save_cfg_in_flash(me)
     me.ser.do_cmd(['cfg write' char(13)]);
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

   %   function set_atten_spline(me, ch, fname, m)
   %   % inputs:
   %   %   ch: one-based index of channel
   %   %   fname: short file name of calibration file
   %   %   m: matrix representation of a spline.
   %     me.ser.set_dbg(1);
   %     rsp = me.ser.do_cmd(sprintf('cfg cal andvr c %d\r', ch));
   %     me.write_spline(fname, m);
   %     me.ser.do_cmd(sprintf('save\r'));
   %   end


    function set_waveplate_dac(me, pc, wp, val)
     %inputs: wp:1..6
      if ((pc<1)||(pc>me.devinfo.num_fpc))
        error(sprintf('qna2_cal_class.cal_set_waveplates_dac: waveplate %d of pc %d nonexistant', wp, pc));
      end
      if ((wp<1)||(wp>me.devinfo.num_wp(pc)))
        error(sprintf('qna2_cal_class.cal_set_waveplates_dac: waveplate %d of pc %d nonexistant', wp, pc));
      end
      [m err] = me.ser.do_cmd_get_matrix(sprintf('cfg cal efpc %d %d %d\r', pc, wp, val));
      if (~err && (length(m)==1))
        me.settings.efpc_ret_dac = m;
      end
    end


    function err=cal_set_efpc_cal(me, pc_i, cal)
% NOTE: This code expects a sequence of prompts as supplied by
%       efpc_ask_cal() in "common code" efpc.c (which uses zero-base indexing)
      import nc.*
      err=0;
me.ser.set_dbg(1);
      k = size(cal.dac2ph_coef,1)/cal.num_pc;
      coef_per_wp = k
        
      for pc_i=1:cal.num_pc
          
        if (any(any(cal.dac2ph_coef(1:coef_per_wp+(pc_i-1)*coef_per_wp,:))))
          if (pc_i==1)
            me.ser.do_cmd(['cfg efpc' char(13)]);
            me.ser.do_cmd([cal.fname char(13)]);
            me.ser.do_cmd(sprintf('%d\r', cal.num_pc));
            me.ser.do_cmd(sprintf('%d\r', 1)); %cal.no_wl_interp));
          end
          num_wp = cal.num_wp(pc_i);
          num_wp
          [m err] = me.ser.do_cmd_get_matrix(sprintf('%d\r', num_wp));
          if (~err && (m~= num_wp))
            fprintf('ERR: not as many physical waveplates as in calibration\n');
            num_wp = m;
          end
          % FUTURE: get pc_type which will be per-pc.
          me.ser.do_cmd([cal.pc_type char(13)]);
            
          for wp_i=1:num_wp
              for a_i=1:3
                me.ser.do_cmd(sprintf('%g\r', cal.wp_axes((pc_i-1)*3+a_i,wp_i)));
              end
          end
length(cal.pc_wavelens{pc_i})
          rsp = me.ser.do_cmd(sprintf('%d\r', length(cal.pc_wavelens{pc_i})));
          for wl_i=1:length(cal.pc_wavelens{pc_i})
              if (~strfind(lower(rsp), sprintf('wl%d ',wl_i)))
                 fprintf('ERR: not being prompted for wl at expected time\n');
                 fprintf('     instead prompt was: ');
                 uio.print_all(rsp);
              end
              me.ser.do_cmd(sprintf('%f\r', cal.pc_wavelens{pc_i}(wl_i)));
              k=(wl_i-1)*cal.num_pc;
              for a_i=1:3
                me.ser.do_cmd(sprintf('%.5g\r', cal.int_align(k+pc_i, a_i)));
              end
              k=(wl_i-1)*cal.num_pc*coef_per_wp + (pc_i-1)*coef_per_wp;
              for wp_i=1:num_wp
                for co_i=1:2 % in teps, pc_i=1 is BATi, and only two coef used
                  rsp = me.ser.do_cmd(sprintf('%g\r', cal.dac2ph_coef(k+co_i, wp_i)));
                end
              end
          end

        end % if any non-zero coef
      end % for pc

    end

    
  end

end
