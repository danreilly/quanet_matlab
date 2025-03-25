classdef ncdev_class < handle
% abstract class for NuCrypt device object classes

%  properties (Abstract)
%    settings
%  end

  methods (Abstract)
    open(me, portname, opt)
    isopen(me)
    set_io_dbg(me, en)
    close(me)
  end

  methods % default methods

    function status = get_status(me)
      status.ok=1;
    end

  end

end
