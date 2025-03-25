classdef efpc_class
% class for one Electronic Fiber Polarization Controller (EFPC)
% NuCrypt device classes may use this class.

  properties
    num_wp           % intger. typically 4 or 6
    wp_axes          % 3xnum_wp
    efpc_type        % 'b' = BATi, 'o'=Oz Optics
    no_wl_interp     % 0|1
    has_beamsplitter_at_egress % 0|1
    iv               % 3x1     OBSOLETE?
    wavelens_nm      % 
    dac2ph_coef      %
  end

  properties
    dbg_lvl  % 0=none, 1=debug cpds reads
    ser      % obj of type serclass
  end

  methods (Static=true)
    % static
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
      cal.samp_pd_us=1000;

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
      
      return;

      % nested inside read_calfile
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
    
      % nested inside read_calfile
      function handle_str(name, val)
        if (strcmp(name,'date'))
          cal.date=val;
        elseif (strcmp(name,'src1'))
          cal.src1=val;
        elseif (strcmp(name,'sernum'))
          cal.sernum=val;
        elseif (strcmp(name,'pol_type'))
          cal.pol_type=val;
        end
      end

    end % end function cal = read_calfile(fname)
    
  end

end
