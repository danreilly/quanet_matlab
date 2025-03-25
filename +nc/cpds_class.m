classdef cpds_class < nc.ncdev_class

  properties (Constant=true)
    ACCID = uint32(65536);

    HISTID_RESID       = uint32(65536);
    HISTID_OK          = uint32(65537);
    HISTID_FLINK_BER   = uint32(65538);
    HISTID_FLINK_USAGE = uint32(65539);
  end

  methods (Abstract)
    set_clkdiv(me, clkdiv)
    set_measlen(me, measlen)
    set_masklen(me, chan, masklen)
  end

  methods (Static)
    function b=corrstat_isaccid(id)
      b = logical(bitand(id, nc.cpds_class.ACCID));
    end
    
    function id=a_id(id)
    % makes a correlation id into an accidental id
    % or a singles id into an afterpulsing id
      id = bitor(id, nc.cpds_class.ACCID);
    end
    
    function id=s_id(c1)
    % forms an "id" of a singles count
      id = bitset(0,c1);
    end
    
    function id=c_id(c1, c2, c3, c4)
    % forms an "id" of a correlation statistic.
    % can take 1 to four parameters
    %   C_ID(c1)
    %   C_ID(c1,c2)
    %   C_ID(c1,c2,c3)
    %   C_ID(c1,c2,c3,c4)
    % c1..4 are one-based channel indexes.
      id = bitset(0,c1);
      if (nargin>1)
        id = bitset(id,c2);
        if (nargin>2)
          id = bitset(id,c3);
          if (nargin>3)
            id = bitset(id,c4);
          end
        end
      end
    end
      

    function id=corrstat(c1, c2, c3, c4)
    % DEPRECATED
    % forms an "id" of a correlation statistic.
    % can take 1 to four parameters
    %   CORRSTAT(c1)
    %   CORRSTAT(c1,c2)
    %   CORRSTAT(c1,c2,c3)
    %   CORRSTAT(c1,c2,c3,c4)
    % c1..4 are one-based channel indexes.
      id = bitset(0,c1);
      if (nargin>1)
        id = bitset(id,c2);
        if (nargin>2)
          id = bitset(id,c3);
          if (nargin>3)
            id = bitset(id,c4);
          end
        end
      end
    end

  end

end
