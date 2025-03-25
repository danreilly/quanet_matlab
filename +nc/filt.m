classdef filt
  methods (Static=true)
    % matlab "static" methods do not require an instance of the class

    function sig = gauss(sig, fs, fcut, ord)
    % desc: low-pass gaussian filter of specified order (FIR length)
    %       zero delay
    % inputs: ord: optional order
        import nc.*
        sigmaf = fcut/sqrt(2*log(sqrt(2)));
        sigma = 1/(2*pi*sigmaf);
        if (nargin<4)
            ord = ceil(sigma * sqrt(-2*log(.01))*fs * 2);
            fprintf('gaussian filter uses order %d\n', ord);
        end
        
        x = linspace(-ord / 2, ord / 2, ord)/fs;
        gf = exp(-x .^ 2 / (2 * sigma ^ 2));

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
        
        sig = conv(sig, gf, 'same');
        %  toc
    end


  end
end
    
