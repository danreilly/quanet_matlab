+nc/README.txt
--------------

This is the NuCrypt matlab "package"
To use thse functions, in your code you can prefix the function with "nc.",
for example
  nc.
  import nc.*


The following classes are really just groups of utility functions.  You don't instantiate
a member of the class; the class only serves as an organizational categery.  In
matlab speak, these classes contains only "static" functions:
 
  uio.m          general IO utilties, such as prompting for a value with a default
  vars_class.m   create and access variables in a separate namespace, optionally save/load in a text file.
  fileutils.m    file IO and filename utility functions
  fit.m          least mean-square error fitting
  ncplot.m       plotting utilities

These classes access lab equipment.
When you instantiate each class, the resulting object gets associated with a
specific physical device that you can then control/access.

     class                  Manuf      desc
  cpds1000_class.m        NuCrypt    single photon detector
  pa1000_class.m          NuCrypt    polarization analyzer
  intf1000_class.m        NuCrypt    stabilized interferometer
  dfpg1000_class.m        NuCrypt    polarization generator
  tunlsr_class.m          NuCrypt    tunable laser
  tsteff_class.m          NuCrypt    SPD efficiency tester
  tstsrc1000_class.m      NuCrypt    simulated single-photon source
  wavemeter_class.m       Burleigh   optical wavemeter
  pm100d_class.m          Thor labs  optical power meter
  agilent81689a_class.m   Agilent    RF spectrum analyzer


Some objects (.mex64) are compiled from C.  These have already been compiled.
But if you need to recompile them, use:
  nc.compile
  nc.pm100d_compile
