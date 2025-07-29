@echo off
echo "This gets a file from the RedPitaya board"
for /F "TOKENS=2 DELIMS=/ " %%A in ('date /T') do set M=%%A
for /F "TOKENS=3 DELIMS=/ " %%A in ('date /T') do set D=%%A
for /F "TOKENS=4 DELIMS=/ " %%A in ('date /T') do set YY=%%A
for /F "TOKENS=2 DELIMS=0" %%A in ( "%YY%" ) do set Y=%%A
set DIR=log\d%Y%%M%%D%

if not exist %DIR% (
  echo making %DIR% 
  mkdir %DIR%
)
set CTRF=%DIR%\ctr.txt
if not exist %CTRF% (
  echo "0"> %CTRF%
)

rem echo reading %CTRF%
set /p CTR=<%CTRF%
set /A CTR=CTR+1
echo %CTR% > %CTRF%

set F=%DIR%
rem scp -i "C:/reilly/proj/quanet/matlab/analog.txt.pub" -r analog@analog:/home/analog/ech/out %F%
scp -r root@rp-f09987.local:/root/tst/RedPitaya/Examples/C/log.txt %F%
rem scp -i "analog.txt" -r analog@analog:/home/analog/ech/out %F%

call :cp %DIR%\log.txt %DIR%\rp_%CTR%.txt
rem rename %DIR%\r.txt 
rem rename %DIR%\d.raw 

echo got %F%\rp_%CTR%.txt


goto :eof




:cp
  echo :cp %1 %2
  if not exist %1 (
    echo ERR: copy from %1 does not exist!
    pause
    exit /b 99
  )
  echo F|xcopy /Y %1 %2
