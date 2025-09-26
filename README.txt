
Matlab programs:

 Top-level code

    txattn.m - Sets Bob's transmit attenuation, which determines the transmitted
            power of his pilots.
	    Controls actual equipment using USB & TCPIP control.
	    Written and used at Photon Summit.  

    pol.m - Sweeps polarizer waveplates and chooses settings
            resulting in the highest recieved IQ power.
	    To be used during link setup.
	    Controls actual equipment using USB & TCPIP control.
	    Written and used at Photon Summit.
	    
    dsw.m - Delay Sweep.  Used when Alice synchronizes using a recovered clock.
            Initially, the phase relationship between the recoverd clock and her
            received pilots is unknown.  This sweeps the delay setting and measures
	    the number of detected pilots vs delay.  It makes a plot and sets
	    the "sync_dly" to the best setting.
	    To be used during link setup.
	    Controls actual equipment using USB & TCPIP control.
	    Written and used at Photon Summit.

    tsw.m - Threshold Sweep.
            Initially, the loss on the link is unknown, and the best correlation
	    threshold for Alice to use when detecting pilots is unknown.  This
	    sweeps the threshold and measures the number of detected pilots per 1024 frames.
	    Ideally this number should be 1024. (though the counter saturates at
	    1023).  This makes a plot and chooses a 
	    To be used during link setup or after changing transmit power.
	    Controls actual equipment using USB & TCPIP control.
	    Written and used at Photon Summit.

    p.m - general IQ samples file viewer.

    rx.m - analyze IQ sample files files for QSDC.
           Computes symbol error rate, Bit error rate (BER), and produces
	   a file r_###_out.txt containing per-bit confidence metrics that could
	   perhaps be used to compute an LLR.  Anyway, these values may be fed
	   into a Grand decoder, and that seems to work.

    cdm.m - analyze IQ sample files for CDM (or CDW) (reflection/transmission tomography)

    genhex.m - generate hex file for hdl simulation from IQ sample file

    im_preemp.m - calculate im preemphasis profile, stores result in a file
       that can be downloaded into HDL.

 Calibration code

  cal_imbal.m    - calibrate IQ imbalance
  cal_gas.m      - measure HCN gaslines
  cal_gas_show.m - calculate gasline params and gen calibration file
  wcal.m         - write gas calibration file to QNA

 Test code

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
