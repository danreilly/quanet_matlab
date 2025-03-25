% for minickts RUDAT  rf attenuator

classdef rudat_class < nc.ncdev_class

  properties
    rudat
    devinfo
    op
    io_dbg
    settings
  end
  
  methods
    % CONSTRUCTOR
    function me = rudat_class(arg1, opt)
      if (~exist('mcl_RUDAT64.USB_RUDAT','class'))
        if (~exist('C:\Windows\System32\mcl_RUDAT64.dll'))
           nc.uio.print_wrap('ERR: To use the minickts RUDAT rf attenuator, you must put a copy of mcl_RUDAT64.dll into C:\Windows\System32.  Contrary to what you might think, C:\Windows\System32 is for 64-bit DLLs, and C:\Windows\SysWOW64 is for 32-bit DLLs.');
           me.rudat = [];
        else
          fprintf('WARN: adding C:\\Windows\\System32\\mcl_RUDAT64.dll\n');
          asm = NET.addAssembly('C:\Windows\System32\mcl_RUDAT64.dll');
          me.rudat = mcl_RUDAT64.USB_RUDAT;
        end
      end
      me.devinfo.name = 'rfatten';
      me.devinfo.sn = '';
      me.devinfo.fwver_str = '?';
      me.devinfo.fwver = [0 0];
      me.io_dbg=0;
      me.devinfo.num_chan = 1;
      me.devinfo.pp=mkpp( [  13.584 50.2028 165.498 180    ], [1.29869e-07 9.59586e-06 0.0022226 0.0318114
 1.99323e-07 -4.67109e-06 0.00240294 0.119691
 6.6916e-05 6.42716e-05 0.00927457 0.640128]);
      me.settings.atten_dB=0;
      me.settings.phase_deg = 0;
      me.open();
    end
    
    % DESTRUCTOR
    function delete(me)
      me.close;
    end
    
    function close(me)
      if (~isempty(me.rudat))             
        me.rudat.Disconnect()
      end
    end
    
    function b = isopen(me)
      b = me.op;
    end
    
    function set_io_dbg(me, en)
      me.io_dbg=en;
    end

    function [n, str] = scpi(me, str)
      if (me.io_dbg)
        fprintf('ATTN: tx ')
        nc.uio.print_all(str);
      end
      [n, rsp] = me.rudat.Send_SCPI(str,'');
      str=char(rsp);
      if (me.io_dbg)
        fprintf('      rx ');
        nc.uio.print_all(str);
      end
    end
    
    function open(me, arg2)
      if (nargin<2)
        sn='11702260052';
        opt.dbg=0;
      else
        if (isstruct(arg2))
          opt=arg2;
          sn='11702260052';
        else
          sn = arg2;
          opt.dbg=0;
        end               
      end               
      if (isempty(me.rudat))
        return;
      end
      me.op = me.rudat.Connect(sn);
      if (~me.op)
        fprintf('WARN: no minickts RUDAT rf attenuator (this is normal)\n');
      else
        [n, rsp] = me.scpi(':SN?');
        me.devinfo.sn = regexprep(rsp,'SN=','');
        [n, rsp] = me.scpi(':MN?');
        me.devinfo.model = regexprep(rsp,'MN=','');
        me.get_settings();
      end
    end

    function status = get_status(me)
      status.err = 0;
    end
    
    function get_settings(me)
      [n, str] = me.scpi(':ATT?');
      if (n==1)
        [dB n]=sscanf(str,'%g');
        if (n==1)
          me.settings.atten_dB=dB;
          opt.extend=1;
          degs = nc.fit.ppinv(me.devinfo.pp, 10^-(dB/20), opt);
          if (~isempty(degs))
            me.settings.phase_deg = degs(1);
          end
        end
      end
    end

    function deg = set_phase_deg(me, chan, deg)
      % fprintf('DBG: attn.set_phase_deg(%d, %g)\n', chan, deg);
      if (chan~=1)
        error(sprintf('DBG: rudat_class.set_phase_deg(%d,%g): chan must be 1', chan, deg));
      end
      pp=me.devinfo.pp;
      deg = max(pp.breaks(1), min(pp.breaks(end), deg));
      me.settings.phase_deg = deg; % just in case
      atten = ppval(pp, deg);
      atten_dB = -round(20*log10(atten)*4)/4;
      me.set_atten_dB(atten_dB);
      deg = me.settings.phase_deg(chan);
    end

    function set_atten_dB(me, dB)
      % fprintf('DBG: attn.set_atten_dB(%g)\n', dB);
      dB=max(0,min(30,dB));
      dB=round(dB*4)/4;
      [n, str] = me.scpi(sprintf(':SETATT=%.2f',dB));
      if (n && strcmp(str,'1'))
        me.settings.atten_dB=dB;
      else
        fprintf('ERR: rudat_class.set_atten_dB(%g) returned: ', dB);
        nc.uio.print_all(str);
        fprintf('\n');
      end
      opt.extend=1;
      degs = nc.fit.ppinv(me.devinfo.pp, 10^-(dB/20), opt);
      if (~isempty(degs))
        me.settings.phase_deg = degs(1);
      end
    end
    
  end
end
