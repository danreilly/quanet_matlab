
Matlab programs:

 Top-level code
 
    p.m - CDM stuff (ping and reflections)

    rx.m - processes IQ samples of unencrypted messages sent from Alice to Bob.
           Currently only computes symbol BER.

    im_preemp.m - calculate im preemphasis profile, stores result in a file
       that can be downloaded into HDL.

 Test code.  Less important.

  p2.m - analyze beat
  rp.m - plot data captured from Red Pitaya board
  beat.m - measure beat from QNA
  
  t1.m - effect of LO power on noise
  t2.m - sensitiviy vs sig pwr with & wo connet amp
  t3.m - junk
  t5.m - exploration of lorentzian fit
  t6.m - fourier transform of lorentz

  t8.m - illustrative plots of modulation signals
  t9.m - simulate pwr det by red pitaya.
  t10.m - illustrative plot of phase detector out

 Helper functions

  calc_*
  

Batch file utilities:
  g.bat   - get capture file from zcu106
  rpg.bat - get capture file from Red Pitaya
