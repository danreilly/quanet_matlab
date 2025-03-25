@date /T
for /F "TOKENS=2 DELIMS=/ " %%A in ('date /T') do set M=%%A
for /F "TOKENS=3 DELIMS=/ " %%A in ('date /T') do set D=%%A
for /F "TOKENS=4 DELIMS=/ " %%A in ('date /T') do set YY=%%A
for /F "TOKENS=2 DELIMS=0" %%A in ( "%YY%" ) do set Y=%%A
set DATE=%Y%%M%%D%

echo %DATE%


