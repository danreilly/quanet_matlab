classdef sersharecli_class < handle

  properties (Constant=true)

  end

  % instance members
  properties
    dbg  % 0=none, 1=debug IO
    cons_ipaddrs
    cons_srv_hs
  end

  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function e=disconnect_all
      %DISCONNECT_ALL Disconnect from all remote sershare servers
      e = nc.sershare_mex(10);
    end
    
    function msg = get_err_msg
      msg = nc.sershare_mex(11);
    end
    
    function [e, portlist] = inq( srv_h)
      % returns: portlist is cell array of strings
      [e, portlist] = nc.sershare_mex(1, srv_h);
    end
    
  end

  methods

    % CONSTRUCTOR
    function me = sersharecli_class
      % desc: makes a connection to one remote sershare server
      % returns: sersarecli object used to access ports on that remote server.
      % inputs:
      %   ipaddr is of form "192.168.1.2" or "192.168.1.2:<portnum>"
      %SERSHARE_CONNECT connects to a sershare server
      me.dbg=0;
      me.cons_srv_hs=ones(4,1)*-1; % none connected
      %  sets srv_h to -1 on error
    end

    % DESTRUCTOR
    function delete(me)
      me.disconnect_all;
    end

    function cons_idx = get_srv_h_idx(me, srv_h)
      for k=1:length(me.cons_srv_hs)
        if (me.cons_srv_hs(k)==srv_h)
           cons_idx=k;
           return;
        end
      end
      cons_idx=0;
    end


    function cons_idx = get_cons_idx(me, ipaddr)
      for k=1:length(me.cons_srv_hs)
        if (me.cons_srv_hs(k)>=0)
          if (strcmp(ipaddr, me.cons_ipaddrs{k}))
             cons_idx=k;
             return;
          end
        end
      end
      cons_idx=0;
    end

    function cons_idx = get_mt_idx(me)
      for k=1:length(me.cons_srv_hs)
        if (me.cons_srv_hs(k)<0)
          cons_idx=k;
          return;
        end
      end
      cons_idx = length(me.cons_srv_hs)+1;
    end

    function srv_h = connect(me, ipaddr)
    % if already connected, returns handle
    % returns: srv_h: -1 means not connected
      idx=me.get_cons_idx(ipaddr);
      if (idx)
        srv_h = me.cons_srv_hs(idx);
        return;
      end
      idx = me.get_mt_idx();
      if (~isempty(ipaddr))
        [e, srv_h] = nc.sershare_mex(0, ipaddr);
        if (~e)
          me.cons_ipaddrs{idx}=ipaddr;
          me.cons_srv_hs(idx)=srv_h;
          return;
        end
      end
      srv_h=-1;
    end

    function r = isconnected(me, ipaddr)
      idx=me.get_cons_idx(ipaddr);
      r = (idx>=0);
    end


    function e = disconnect(me, srv_h)
      if (ischar(srv_h))
        idx = me.get_cons_idx(srv_h);
      else	     
        idx = me.get_srv_h_idx(srv_h);
      end
      e=0;
      if (idx>0)
        e = nc.sershare_mex(9, me.cons_srv_hs(idx));
        me.cons_srv_hs(idx)=-1;
      end
    end




%    function [e portlist] = mswait(me, ms)
%      %MSWAIT
%      %   ms = milliseconds to wait on remote machine
%      % NOTE: yes, you could wait on the local machine.  But the IO latency
%      %   to the remote machine can vary greatly, even by seconds!
%      e = nc.sershare_mex(2, me.srv_h, ms);
%    end

  end

end
