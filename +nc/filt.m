classdef filt
  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function sigo = gauss(sig, fs, fcut, ord)
    % desc: low-pass gaussian filter of specified order (FIR length)
    %       zero delay.  Tapered filtering at ends.
    % inputs: ord: optional order
        import nc.*
        sigmaf = fcut/sqrt(2*log(sqrt(2)));
        sigma = 1/(2*pi*sigmaf);
        if (nargin<4)
            ord = ceil(sigma * sqrt(-2*log(.01))*fs * 2);
            fprintf('gaussian filter uses order %d\n', ord);
        end
        
        x = linspace(-ord / 2, ord / 2, ord)/fs;
        gf = exp(-x .^ 2 / (2 * sigma ^ 2)).';

        %  xm = round(sigma * sqrt(-2*log(.01))*fs * 2);
        %  xm
        %gf(1)  
        if (1)
            if (gf(1)>1e-2)
                fprintf('\nERR: gausfilt(fcut=%g, ord=%d)\n', fcut, ord);
                fprintf('     order probably too low to achive that amt of averaging\n');
                fprintf('     because smallest tap %.1f%% >> 0\n', 100*gf(1));
            end
        end
        gf = gf / sum (gf); % normalize
                            %  fprintf('gausfilt start\n');
                            %  tic

        if (0)
          ncplot.init;
          plot(x / fs, gf, '.');
          title('gauss filter');
          uio.pause;
        end

        sig_l=length(sig);
        sigo = conv(sig, gf, 'same');

        % taper the filtering at the ends
        c=ceil(ord/2);
        for k=1:c-1
          sl=ord-c+k;
          sigo(k)=sum(gf(ord-sl+1:ord) .* sig(1:sl)) / sum(gf(ord-sl+1:ord));
        end
        for k=1:(ord-c)
          sl=c+k-1;
          sigo(sig_l+1-k)=sum(gf(1:sl) .* sig(sig_l-sl+1:end)) / sum(gf(1:sl));
        end
        
        %  toc
    end


  end
end
    
