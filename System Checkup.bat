@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
color 0F
set ver=6.0
set "std=cls & mode con: cols=120 lines=30 & color 0F"
title System Checkup v%ver%
:check_Permissions
mode con: cols=85 lines=5
Call :Color C "Administrative permissions is required:"
Call :Color 9 " Detecting permissions..."
echo.
timeout /t 1 /nobreak >nul
net session >nul 2>&1
if %errorLevel% == 0 (
	Call :Color C "                               Success: "
	Call :Color 9 "Administrative permissions confirmed."
	echo.
	timeout /t 1 /nobreak >nul
	Call :Color C "                               Welcome: "
	Call :Color 9 "%username%"
	echo.
	timeout /t 3 /nobreak >nul
	if not exist "%APPDATA%\Microsoft\Windows\NlsData0414.bin" (
    cls
    Call :Color 9 "Could not find data bin file."
    echo.
    timeout /t 1 /nobreak >nul
    goto :register
)
goto :login
) else (
	Call :Color C "                               Failure: "
	Call :Color 9 "Current permissions inadequate."
	echo.
	Call :Color C "Press any key to restart this program as "
	Call :Color 9 "Administrator"
	pause>nul
	echo.
	powershell -Command "Start-Process '%~0' -Verb RunAs"
	exit /b	
)
exit
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:login
cls & color 0F & mode con: cols=85 lines=5
set stat=0
if not defined failed_attempts set failed_attempts=0

set "datafile=%APPDATA%\Microsoft\Windows\NlsData0414.bin"
:: Check for persistent lockout
for /f "tokens=2 delims==" %%A in ('findstr /c:"LockoutUntil=" "%datafile%" 2^>nul') do set "lockout_until=%%A"
if defined lockout_until (
    for /f "tokens=*" %%T in ('powershell.exe -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"') do set "now=%%T"
    if !lockout_until! GTR !now! (
        for /f "tokens=*" %%R in ('powershell.exe -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"') do set "remaining=%%R"
        set /a remaining=%lockout_until%-%remaining%
        cls
        Call :Color 9 "Account locked. Try again in"
        Call :Color C " !remaining! seconds."
        echo.
        timeout /t 5 /nobreak >nul
        set "lockout_until="
        goto :login
    ) else (
        :: Lockout expired, clean it up
        powershell.exe -Command "(Get-Content '%datafile%') -notmatch '^LockoutUntil=' | Set-Content '%datafile%'"
        set "lockout_until="
    )
)
set "pscmd=powershell.exe -Command "$inputPass = read-host 'Enter password to continue' -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputPass); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""

setlocal disabledelayedexpansion
for /f "tokens=*" %%a in ('%pscmd%') do set "password=%%a"
endlocal & set "password=%password%"

:: Handle special commands before hashing
if "%password%"=="exit" exit
if "%password%"=="reset_pass" goto :reset_password

:: Read stored salt
for /f "tokens=2 delims==" %%A in ('findstr /c:"PasswordSalt=" "%datafile%"') do set "pass_salt=%%A"
set "pass_salt=%pass_salt: =%"

:: Hash salt+input using $env: variables
for /f "tokens=*" %%H in ('powershell.exe -Command "[BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:pass_salt+$env:password))).Replace('-','').ToLower()"') do set password_hash=%%H

:: Compare with stored hash
for /f "tokens=2 delims==" %%A in ('findstr /c:"Password=" "%datafile%"') do set "stored_hash=%%A"
set "stored_hash=%stored_hash: =%"

if "%password_hash%"=="%stored_hash%" (
    cls
    set failed_attempts=0
    call :Log "LOGIN - User %username% logged in successfully"
    goto :startup_summary
)

:: Wrong password
set /a failed_attempts+=1
Call :Color 9 "Wrong password. Attempt"
Call :Color C " %failed_attempts% of 3."
if %failed_attempts% GEQ 3 (
    echo.
    call :Log "LOCKOUT - Too many failed attempts by %username%"
    Call :Color 9 "Too many failed attempts."
    Call :Color C " Locking system for 30 seconds..."
    :: Write lockout expiry timestamp to datafile
    for /f "tokens=*" %%T in ('powershell.exe -Command "[DateTimeOffset]::UtcNow.AddSeconds(30).ToUnixTimeSeconds()"') do set "lockout_until=%%T"
    powershell.exe -Command "(Get-Content '%datafile%') -notmatch '^LockoutUntil=' | Set-Content '%datafile%'"
    echo LockoutUntil=%lockout_until%>> "%datafile%"
    timeout /t 30 /nobreak >nul
    set failed_attempts=0
    :: Remove lockout entry after expiry
    powershell.exe -Command "(Get-Content '%datafile%') -notmatch '^LockoutUntil=' | Set-Content '%datafile%'"
)
timeout /t 2 /nobreak >nul
goto :login

:help
cls
mode con: cols=70 lines=12
echo ======================================================================
echo                         Command List
echo ======================================================================
echo.
echo    exit             - Exit the program.
echo    reset_pass       - Reset your password using a security question.
echo.
echo    Tip: Type 'admin' from the main menu for advanced options.
echo.
echo ======================================================================
pause >nul
if %stat%==1 goto :main
goto :login

:reset_password
cls
mode con: cols=54 lines=12
echo ======================================================
echo                  Password Reset										
echo ======================================================
echo.

set "datafile=%APPDATA%\Microsoft\Windows\NlsData0414.bin"

for /f "tokens=2 delims==" %%A in ('findstr /c:"SecurityQuestion=" "%datafile%"') do set sec_question=%%A
echo %sec_question%

set "pscmd4=powershell.exe -Command "$inputSec = read-host 'Enter the answer (Case Sensitive)' -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputSec); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""

setlocal disabledelayedexpansion
for /f "tokens=*" %%a in ('%pscmd4%') do set "sec_answer=%%a"
endlocal & set "sec_answer=%sec_answer%"

:: Read stored answer salt
for /f "tokens=2 delims==" %%A in ('findstr /c:"SecurityAnswerSalt=" "%datafile%"') do set "ans_salt=%%A"
set "ans_salt=%ans_salt: =%"

:: Hash salt+answer
for /f "tokens=*" %%H in ('powershell.exe -Command "[BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:ans_salt+$env:sec_answer))).Replace('-','').ToLower().Trim()"') do set answer_hash=%%H

:: Read and compare stored answer hash
for /f "tokens=2 delims==" %%A in ('findstr /c:"SecurityAnswer=" "%datafile%"') do set "stored_answer=%%A"
set "stored_answer=%stored_answer: =%"

if "%answer_hash%"=="%stored_answer%" (
    echo Security answer verified.
    set failed_attempts=0
    goto :register
)

echo Incorrect answer! Returning to login...
timeout /t 2 /nobreak >nul
goto :login

:register
mode con: cols=60 lines=15
cls
echo ============================================================
echo                  Register New Password										
echo ============================================================ 
echo.

set "pscmd1=powershell.exe -Command "$inputPass = read-host 'Enter a new Password' -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputPass); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""
set "pscmd2=powershell.exe -Command "$inputPass = read-host 'Confirm Password' -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputPass); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""
set "pscmd3=powershell.exe -Command "$inputSec = read-host 'Enter the answer (Case Sensitive)' -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputSec); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)""

:: Capture passwords with ! protection
setlocal disabledelayedexpansion
for /f "tokens=*" %%a in ('%pscmd1%') do set "new=%%a"
endlocal & set "new=%new%"

setlocal disabledelayedexpansion
for /f "tokens=*" %%a in ('%pscmd2%') do set "new1=%%a"
endlocal & set "new1=%new1%"

if not "%new%"=="%new1%" (
    cls
    echo Passwords do not match.
    timeout /t 2 /nobreak >nul
    goto :register
)

echo Enter a security question:
set /p sec_question=

setlocal disabledelayedexpansion
for /f "tokens=*" %%a in ('%pscmd3%') do set "sec_answer=%%a"
endlocal & set "sec_answer=%sec_answer%"

:: Generate a unique random salt for password
for /f "tokens=*" %%S in ('powershell.exe -Command "$rng=New-Object System.Security.Cryptography.RNGCryptoServiceProvider;$b=New-Object byte[] 32;$rng.GetBytes($b);[BitConverter]::ToString($b).Replace('-','').ToLower()"') do set "pass_salt=%%S"

:: Generate a unique random salt for security answer
for /f "tokens=*" %%S in ('powershell.exe -Command "$rng=New-Object System.Security.Cryptography.RNGCryptoServiceProvider;$b=New-Object byte[] 32;$rng.GetBytes($b);[BitConverter]::ToString($b).Replace('-','').ToLower()"') do set "ans_salt=%%S"

:: Hash salt+password and salt+answer using $env: variables
for /f "tokens=*" %%H in ('powershell.exe -Command "[BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:pass_salt+$env:new))).Replace('-','').ToLower()"') do set hashed_pass=%%H
for /f "tokens=*" %%H in ('powershell.exe -Command "[BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:ans_salt+$env:sec_answer))).Replace('-','').ToLower()"') do set hashed_answer=%%H

:: Save to file
set "datafile=%APPDATA%\Microsoft\Windows\NlsData0414.bin"
echo Password=%hashed_pass%> "%datafile%"
echo PasswordSalt=%pass_salt%>> "%datafile%"
echo SecurityQuestion=%sec_question%>> "%datafile%"
echo SecurityAnswer=%hashed_answer%>> "%datafile%"
echo SecurityAnswerSalt=%ans_salt%>> "%datafile%"

cls
echo Registration complete!
timeout /t 2 /nobreak >nul
goto :login

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:startup_summary
cls & color 0F & mode con: cols=80 lines=20
echo ================================================================
echo                 System Checkup v%ver%
echo                   Welcome, %username%
echo ================================================================
echo.

:: Disk space - all drives
echo   	Drives:
for /f "tokens=*" %%D in ('powershell.exe -Command ^
    "Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + ': ' + [math]::Round($_.Free/1GB,1) + ' GB free of ' + [math]::Round(($_.Free+$_.Used)/1GB,1) + ' GB' }"') do echo		     %%D
echo.

:: RAM usage
for /f "tokens=1,2 delims=;" %%A in ('powershell.exe -Command ^
    "$os=Get-CimInstance Win32_OperatingSystem;[math]::Round($os.FreePhysicalMemory/1MB,1).ToString()+';'+[math]::Round($os.TotalVisibleMemorySize/1MB,1).ToString()"') do set "ram_free=%%A" & set "ram_total=%%B"

:: CPU usage
for /f "tokens=*" %%C in ('powershell.exe -Command ^
    "(Get-CimInstance Win32_Processor).LoadPercentage"') do set "cpu_load=%%C"

:: Last login from log
for /f "tokens=*" %%L in ('powershell.exe -Command ^
    "try { (Get-Content '%USERPROFILE%\Desktop\SystemCheckup_Log.txt' | Select-String 'LOGIN' | Select-Object -Last 2 | Select-Object -First 1) -replace '^\[|\].*$','' } catch { 'No previous login found' }"') do set "last_login=%%L"

echo	   	RAM: %ram_free% GB free of %ram_total% GB
echo   	CPU Load: %cpu_load%%%
echo.
echo   	Last login: %last_login%
echo.
echo ================================================================
echo   Press any key to continue to the main menu...
echo ================================================================
pause >nul
goto :main
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:main
set stat=1
mode con: cols=120 lines=34
set menu_num=Default
cls
color 3
Call :Color A "================================================================================================================"
echo. 
Call :Color B "             					Select Diagnostic Tool"
echo.								
Call :Color A "================================================================================================================"
echo.
Call :Color C " 00. " & Call :Color B "Quick junk cleanup 				" & Call :Color A "|| " & Call :Color C "08. " & Call :Color B "Battery energy report"
echo.
Call :Color C "     Run a quick temp file cleanup			" & Call :Color A "|| " & Call :Color C "    Check battery health and status"
echo.
Call :Color C " 01. " & Call :Color B "System file checker (sfc)				" & Call :Color A "|| " & Call :Color C "09. " & Call :Color B "Fix Windows Explorer high CPU usage"
echo.
Call :Color C "     Repair missing or corrupted system files		" & Call :Color A "|| " & Call :Color C "    Editing registry files"
echo.
Call :Color C " 02. " & Call :Color B "Reset Network Settings				" & Call :Color A "|| " & Call :Color C "10. " & Call :Color B "Winget upgrade"
echo.
Call :Color C "     Fixes Wi-Fi & network issues			" & Call :Color A "|| " & Call :Color C "    Checks and installs apps newest versions"
echo.
Call :Color C " 03. " & Call :Color B "Check for drive integrity (chkdsk)			" & Call :Color A "|| " & Call :Color C "11. " & Call :Color B "Full system diagnostic tools"
echo.
Call :Color C "     Checks file integrity of your hard disk 		" & Call :Color A "|| " & Call :Color C "    Run all diagnostic tools"
echo.
Call :Color C " 04. " & Call :Color B "Clean temp folder and DiskCleanup 			" & Call :Color A "|| " & Call :Color C "12. " & Call :Color B "Wifi Passwords"
echo.
Call :Color C "     Deleting junk / temp files 			" & Call :Color A "|| " & Call :Color C "    Passwords for previous logged on Wifi"
echo.
Call :Color C " 05. " & Call :Color B "Fix corrupted Drive (dism) 			" & Call :Color A "|| " & Call :Color C "13. " & Call :Color B "Memory Diagnostic tool" 
echo.
Call :Color C "     Will try to find and fix corrupted files 		" & Call :Color A "|| " & Call :Color C "    Check for memory problems (Blue screen of death)"
echo.
Call :Color C " 06. " & Call :Color B "Restart PC into BIOS				" & Call :Color A "|| " & Call :Color C "14. " & Call :Color B "Clean Boot"
echo.
Call :Color C "     Enter BIOS						" & Call :Color A "|| " & Call :Color C "    Clean pc boot for farther problems diagnostics"
echo.
Call :Color 9 "****************************************************************************************************************"
echo.
Call :Color B "					07. Full corruption fix & Cleanup"
echo.
Call :Color 9 "****************************************************************************************************************"
echo.
::::
Call :Color C " 15. " & Call :Color B "View System Info					" & Call :Color A "|| " & Call :Color C "20. " & Call :Color B "Repair Registry Errors"
echo.
Call :Color C "     Display detailed PC hardware specs			" & Call :Color A "|| " & Call :Color C "    Fixes registry issues automatically"
echo.
Call :Color C " 16. " & Call :Color B "Check Internet Speed				" & Call :Color A "|| " & Call :Color C "21. " & Call :Color B "Optimize RAM Usage"
echo.
Call :Color C "     Test download & upload speeds			" & Call :Color A "|| " & Call :Color C "    Clears unused memory for speed"
echo.
Call :Color C " 17. " & Call :Color B "Check Windows Version				" & Call :Color A "|| " &:: Call :Color C "22. " & Call :Color B "NULL"
echo.
Call :Color C "     Show Windows version & build number		" & Call :Color A "|| " &:: Call :Color C "    NULL"
echo.
Call :Color C " 18. " & Call :Color B "Reset Windows Updates				" & Call :Color A "|| " &:: Call :Color C "23. " & Call :Color B "NULL"
echo.
Call :Color C "     Fix Windows Update errors				" & Call :Color A "|| " &:: Call :Color C "    NULL"
echo.
Call :Color C " 19. " & Call :Color B "Toggle Unnecessary Services			" & Call :Color A "|| " &:: Call :Color C "24. " & Call :Color B "NULL"
echo.
Call :Color C "     Disable or re-enable background services		" & Call :Color A "|| " &:: Call :Color C "    NULL"
echo.
::::
Call :Color A "----------------------------------------------------------------------------------------------------------------"
echo.
Call :Color C ">> "
set /p menu_num=""
if not defined menu_num goto :main
if "%menu_num%"=="help" goto :help
if "%menu_num%"=="back" set stat=0 & goto :login
if "%menu_num%"=="exit" exit
if "%menu_num%"=="admin" goto :admin_menu

echo %menu_num%|findstr /r "[^0-9]">nul
if not errorlevel 1 goto :main

if %menu_num% LSS 0 goto :main
if %menu_num% GTR 21 goto :main
goto :%menu_num%
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:0
call :Log "TOOL 00 - Quick cleanup started"
%std%
call :do_cleanup
start explorer.exe
echo Quick cleanup completed. Press any key to return to menu.
call :Log "TOOL 00 - Quick cleanup completed"
pause >nul
goto :main
:1
call :Log "TOOL 01 - SFC scan started"
%std% & sfc /scannow
call :Log "TOOL 01 - SFC scan completed"
pause>nul & goto :main
:2
call :Log "TOOL 02 - Network reset started"
%std%
echo Resetting network settings...
netsh int ip reset
netsh winsock reset
netsh advfirewall reset
ipconfig /release
ipconfig /renew
ipconfig /flushdns
echo Network settings reset.
call :Log "TOOL 02 - Network reset completed"
pause >nul
goto :main
:3
%std%
call :get_drive
call :Log "TOOL 03 - CHKDSK started on drive %drive%"
call :do_chkdsk
echo CHKDSK finished. Press any key to restart the system.
call :Log "TOOL 03 - CHKDSK completed, system restarting"
pause>nul & shutdown -r -t 2 & exit
:4
call :Log "TOOL 04 - Temp cleanup started"
cls & mode con: cols=85 lines=30 & color 0F
echo Clearing temp folder and running Disk Cleanup...
if exist "%Temp%" (del /f /s /q "%Temp%\*.*" >nul 2>&1 & rmdir /s /q "%Temp%" >nul 2>&1 & md "%Temp%" >nul 2>&1)
cleanmgr /sagerun:99
call :Log "TOOL 04 - Temp cleanup completed"
pause >nul
goto :main
:5
call :Log "TOOL 05 - DISM repair started"
%std%
echo DISM will scan and repair the Windows image. A restart is required after.
echo Proceed? (y/n)
set /p confirm="> "
if not "%confirm%"=="y" goto :main
dism /online /cleanup-image /restorehealth
call :Log "TOOL 05 - DISM completed, system restarting"
pause>nul
shutdown -r -t 5
exit
:6
%std% & echo Continuing will restart your PC into BIOS. & echo Proceed? (y/n)
set /p confirm="> "
if not %confirm%==y goto :main
echo.
shutdown /r /fw /f /t 0
exit /b
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:7
call :Log "TOOL 07 - Full fix started"
%std%
set CPU=0
call :get_drive
set /p edit="Edit Registry file? (y/n): "
if /i "%edit%"=="y" (
	set CPU=1
	goto :9.1
)
:CPU_check
if %CPU%==1 (
	set CPU=0
	echo Editing Registry file. Press any key to continue...
	timeout /t 2 /nobreak >nul
	del %temp%\CPU_fix.reg >nul 2>&1
	echo.
)
echo Updating installed programs...
Winget upgrade --all
echo Update completed
echo.
:::::::::::::::::::::::::::::::::::::::
set /p edit="Delete old Restore Points? (y/n): "
if /i "%edit%"=="y" (
	echo Deleting old Restore Points...
	vssadmin delete shadows /all /Quiet
	echo.
)
call :do_restore_point
call :do_cleanup
call :Log "TOOL 07 - Full fix completed, system restarting"
call :do_full_repair
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:8
%std%
call :Log "TOOL 08 - Battery/energy report started"
echo Generating reports... this may take up to 60 seconds.
echo.

:: Generate energy report
echo [1/2] Running energy efficiency report...
powercfg /energy /output "%USERPROFILE%\Desktop\energy-report.html" >nul 2>&1
if exist "%USERPROFILE%\Desktop\energy-report.html" (
    echo       Done. Opening report...
    start "" "%USERPROFILE%\Desktop\energy-report.html"
) else (
    echo       Energy report could not be generated on this device.
)
echo.
pause

:: Generate battery report
echo [2/2] Running battery health report...
powercfg /batteryreport /output "%USERPROFILE%\Desktop\battery-report.html" >nul 2>&1
if exist "%USERPROFILE%\Desktop\battery-report.html" (
    echo       Done. Opening report...
    start "" "%USERPROFILE%\Desktop\battery-report.html"
) else (
    echo       Battery report not available - this device may not have a battery.
)
echo.
call :Log "TOOL 08 - Battery/energy report completed"
pause
goto :main
:9
%std%
set CPU=0
:9.1
echo Windows Registry Editor Version 5.00>%temp%\CPU_fix.reg
echo. >>%temp%\CPU_fix.reg
echo [HKEY_CURRENT_USER\Software\Microsoft\input]>>%temp%\CPU_fix.reg
echo "IsInputAppPreloadEnabled"=dword:00000000>>%temp%\CPU_fix.reg
echo. >>%temp%\CPU_fix.reg
echo [HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Dsh]>>%temp%\CPU_fix.reg
echo "IsPrelaunchEnabled"=dword:00000000>>%temp%\CPU_fix.reg
start %temp%\CPU_fix.reg
if %CPU%==1 goto :CPU_check
pause
del %temp%\CPU_fix.reg
goto :main
:10
%std% & Winget upgrade --all & pause & goto :main
:11
call :Log "TOOL 11 - Full diagnostic started"
%std% & taskkill /f /im explorer.exe & timeout 1 /nobreak>nul
call :get_drive
echo Deleting old Restore Points...
vssadmin delete shadows /all /Quiet
echo.
call :do_restore_point
call :Log "TOOL 11 - Full diagnostic completed, system restarting"
call :do_full_repair
:12
set Name=99_Default_99
%std%
netsh wlan show profiles | findstr "User profiles"
echo Select SSID:
set /p Name="> "
if %Name%==back goto :main
netsh wlan show profiles name="%Name%" key=clear | findstr "Key Content"
if errorlevel 1 (echo Wrong SSID, please try again. & pause>nul & goto :12)
pause>nul
goto :12
:13
%std%
echo Select 'Restart now and check for problems' in the opened Windows 
MdSched
pause>nul
goto :Eof
:14
call :Log "TOOL 14 - Clean boot initiated by %username%"
%std%
echo ========================================================
echo                    WARNING
echo ========================================================
echo.
echo  This will permanently delete:
echo    - ALL startup registry entries
echo    - ALL scheduled tasks on this machine
echo.
echo  This CANNOT be undone. A recovery script will be
echo  placed on your desktop for after the restart.
echo.
echo  Type CONFIRM to proceed or anything else to cancel:
echo ========================================================
set /p confirm="> "
if not "%confirm%"=="CONFIRM" (
    echo Cancelled. Returning to menu...
    timeout /t 2 /nobreak >nul
    goto :main
)
echo Clean boot configuration is running...
echo Please run 'run.bat' on your desktop after the restart.
sfc /scannow & cleanmgr /sagerun:99 & dism /online /cleanup-image /restorehealth
reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /va /f
reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run /va /f
reg delete HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /va /f
reg delete HKEY_USERS\S-1-5-19\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /va /f
reg delete HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /va /f
schtasks /Delete /TN * /F
echo echo @off>%userprofile%\Desktop\run.bat
echo sfc /scannow>>%userprofile%\Desktop\run.bat
echo cleanmgr /sagerun:99>>%userprofile%\Desktop\run.bat
echo dism /online /cleanup-image /restorehealth>>%userprofile%\Desktop\run.bat
echo pause>>%userprofile%\Desktop\run.bat
echo exit>>%userprofile%\Desktop\run.bat
echo Run Antivirus software after the process finished>>%userprofile%\Desktop\run.bat
shutdown -r -t 5
goto :Eof
:15
cls & mode con: cols=60 lines=20 & color 0F
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Manufacturer" /C:"System Model" /C:"Processor" /C:"Total Physical Memory"
powershell.exe -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Caption"
pause
goto :main
:16
%std%
echo Running internet speed test...

:: Run PowerShell and store results
for /f "tokens=1,2,3 delims=;" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$wc=New-Object System.Net.WebClient;" ^
    "$start=Get-Date;" ^
    "$wc.DownloadFile('http://speed.hetzner.de/10MB.bin', [System.IO.Path]::GetTempFileName());" ^
    "$end=Get-Date;" ^
    "$downloadSpeed=[math]::Round((10 / ($end - $start).TotalSeconds) * 8, 2);" ^
    "$start=Get-Date;" ^
    "$wc.UploadString('https://speed.cloudflare.com/__up?bytes=1000000', 'x' * 1000000);" ^
    "$end=Get-Date;" ^
    "$uploadSpeed=[math]::Round((1 / ($end - $start).TotalSeconds) * 8, 2);" ^
    "$ping=[math]::Round((Test-Connection -ComputerName google.com -Count 3 | Measure-Object -Property ResponseTime -Average).Average, 2);" ^
    "'Download Speed: ' + $downloadSpeed + ' Mbps;' +" ^
    "'Upload Speed: ' + $uploadSpeed + ' Mbps;' +" ^
    "'Ping: ' + $ping + ' ms';"
') do (
    set "download=%%A"
    set "upload=%%B"
    set "ping=%%C"
)

:: Display results correctly
echo %download%
echo %upload%
echo %ping%
echo.
pause >nul
goto :main
:17
%std%
winver
pause
goto :main
:18
call :Log "TOOL 18 - Windows Update reset started"
%std%
echo Resetting Windows Update...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
net stop cryptsvc >nul 2>&1
if exist "%SystemRoot%\SoftwareDistribution.old" (rmdir /s /q "%SystemRoot%\SoftwareDistribution.old" >nul 2>&1)
if exist "%SystemRoot%\System32\catroot2.old" (rmdir /s /q "%SystemRoot%\System32\catroot2.old" >nul 2>&1)
ren "%SystemRoot%\SoftwareDistribution" SoftwareDistribution.old
ren "%SystemRoot%\System32\catroot2" catroot2.old
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
net start cryptsvc >nul 2>&1
echo Windows Update reset complete.
call :Log "TOOL 18 - Windows Update reset completed"
pause >nul
goto :main
:19
call :Log "TOOL 19 - Services toggled by %username%"
%std%

:: Check current state of SysMain to determine toggle direction
for /f "tokens=3" %%S in ('sc query "SysMain" ^| findstr "STATE"') do set "sysmain_state=%%S"

if /i "%sysmain_state%"=="STOPPED" (
    echo ========================================================
    echo               Re-enable Services
    echo ========================================================
    echo.
    echo  The following services are currently DISABLED:
    echo.
    echo    - DiagTrack        ^(Windows telemetry^)
    echo    - dmwappushservice ^(Device push notifications^)
    echo    - SysMain          ^(Superfetch - memory preloading^)
    echo.
    echo  NOTE: Re-enabling SysMain is recommended for HDDs.
    echo  On SSD systems it provides no benefit.
    echo.
    echo  Proceed? ^(y/n^)
    echo ========================================================
    set /p confirm="> "
    if /i not "%confirm%"=="y" (
        echo Cancelled. Returning to menu...
        timeout /t 2 /nobreak >nul
        goto :main
    )
    echo.
    echo Re-enabling services...
    sc config "DiagTrack" start=auto >nul 2>&1
    sc config "dmwappushservice" start=auto >nul 2>&1
    sc config "SysMain" start=auto >nul 2>&1
    sc start "DiagTrack" >nul 2>&1
    sc start "dmwappushservice" >nul 2>&1
    sc start "SysMain" >nul 2>&1
    echo Done. Services re-enabled.
) else (
    echo ========================================================
    echo               Disable Unnecessary Services
    echo ========================================================
    echo.
    echo  This will disable the following services:
    echo.
    echo    - DiagTrack        ^(Windows telemetry^)
    echo    - dmwappushservice ^(Device push notifications^)
    echo    - SysMain          ^(Superfetch - memory preloading^)
    echo.
    echo  NOTE: Disabling SysMain is recommended for SSDs only.
    echo  On HDD systems it may REDUCE performance.
    echo.
    echo  Proceed? ^(y/n^)
    echo ========================================================
    set /p confirm="> "
    if /i not "%confirm%"=="y" (
        echo Cancelled. Returning to menu...
        timeout /t 2 /nobreak >nul
        goto :main
    )
    echo.
    echo Disabling services...
    sc config "DiagTrack" start=disabled >nul 2>&1
    sc config "dmwappushservice" start=disabled >nul 2>&1
    sc config "SysMain" start=disabled >nul 2>&1
    sc stop "DiagTrack" >nul 2>&1
    sc stop "dmwappushservice" >nul 2>&1
    sc stop "SysMain" >nul 2>&1
    echo Done. Services disabled.
    echo.
    echo To manually re-enable run this tool again.
)
echo.
pause >nul
goto :main
:20
call :Log "TOOL 20 - Registry repair started"
%std%
echo Repairing registry errors...
reg export HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall "%temp%\RegistryBackup.reg"
reg export HKCU\Software\Microsoft\Windows\CurrentVersion\Run "%temp%\RegistryRunBackup.reg"
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations /t REG_MULTI_SZ /d "" /f
echo Registry repaired.
call :Log "TOOL 20 - Registry repair completed"
pause >nul
goto :main
:21
%std%
echo Optimizing RAM usage...
echo.

:: Force Windows to reclaim memory from idle processes
powershell.exe -Command "Get-Process | Where-Object {$_.WorkingSet -gt 10MB} | ForEach-Object { $_.MinWorkingSet = 1MB }" 2>nul

:: Clear DNS cache (frees some memory and network buffers)
ipconfig /flushdns >nul

:: Trim system working set via process priority normalization
powershell.exe -Command "Get-Process explorer | ForEach-Object { $_.PriorityClass = 'Normal' }" >nul 2>&1

echo Done. Some memory has been returned to the available pool.
echo Note: For deeper RAM cleanup, consider restarting background apps.
pause
goto :main
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:Log
set "timestamp=%date% %time:~0,8%"
echo [%timestamp%] %~1>> "%USERPROFILE%\Desktop\SystemCheckup_Log.txt"
goto :eof
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:get_drive
cls & color 0F
echo ========================================================
echo                    Select Drive
echo ========================================================
echo.
echo  Enter a drive letter (e.g. C) or type 2 for dual drive.
echo.
set /p drive="> "
if /i "%drive%"=="2" (
    set /p drive1="Windows main drive letter: "
    set /p drive2="Secondary drive letter: "
    if not exist "%drive1%:\" (
        echo.
        echo Drive %drive1%: not found. Please try again.
        timeout /t 2 /nobreak >nul
        goto :get_drive
    )
    if not exist "%drive2%:\" (
        echo.
        echo Drive %drive2%: not found. Please try again.
        timeout /t 2 /nobreak >nul
        goto :get_drive
    )
) else (
    if not exist "%drive%:\" (
        echo.
        echo Drive %drive%: not found. Please try again.
        timeout /t 2 /nobreak >nul
        goto :get_drive
    )
)
goto :eof
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:admin_menu
cls & mode con: cols=60 lines=20 & color 0F
echo ============================================================
echo                    Admin Menu
echo ============================================================
echo.
echo   1. Create a Restore Point
echo   2. Delete all Restore Points
echo   3. View log file
echo   4. Clear log file
echo   5. Change password
echo.
echo   Type 'back' to return to main menu
echo ============================================================
echo.
set /p admin_choice="> "
if "%admin_choice%"=="back" goto :main
if "%admin_choice%"=="1" goto :admin_restore_create
if "%admin_choice%"=="2" goto :admin_restore_del
if "%admin_choice%"=="3" goto :admin_view_log
if "%admin_choice%"=="4" goto :admin_clear_log
if "%admin_choice%"=="5" goto :register
goto :admin_menu

:admin_restore_create
cls
call :do_restore_point
call :Log "ADMIN - Restore point created by %username%"
timeout /t 2 /nobreak >nul
goto :admin_menu

:admin_restore_del
cls
echo ============================================================
echo                       WARNING
echo ============================================================
echo.
echo  This will permanently delete ALL restore points.
echo  This cannot be undone.
echo.
echo  Type CONFIRM to proceed or anything else to cancel:
echo ============================================================
set /p confirm="> "
if not "%confirm%"=="CONFIRM" (
    echo Cancelled.
    timeout /t 2 /nobreak >nul
    goto :admin_menu
)
vssadmin delete shadows /all /Quiet
call :Log "ADMIN - All restore points deleted by %username%"
echo Done.
timeout /t 2 /nobreak >nul
goto :admin_menu

:admin_view_log
cls & mode con: cols=120 lines=30
if exist "%USERPROFILE%\Desktop\SystemCheckup_Log.txt" (
    type "%USERPROFILE%\Desktop\SystemCheckup_Log.txt"
) else (
    echo No log file found.
)
echo.
pause
goto :admin_menu

:admin_clear_log
cls
echo Clear the log file? (y/n)
set /p confirm="> "
if /i not "%confirm%"=="y" goto :admin_menu
del /f /q "%USERPROFILE%\Desktop\SystemCheckup_Log.txt" >nul 2>&1
call :Log "ADMIN - Log file cleared by %username%"
echo Log cleared.
timeout /t 2 /nobreak >nul
goto :admin_menu

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:do_cleanup
echo.
set /p edit="Edit sageset before cleanup? (y/n): "
if /i "%edit%"=="y" cleanmgr /sageset:99
echo.
echo Starting cleanup...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
echo.
echo [01/17] Clearing user temp folders...
if exist "%TEMP%" (del /f /s /q "%TEMP%\*.*" >nul 2>&1 & rmdir /s /q "%TEMP%" >nul 2>&1 & md "%TEMP%" >nul 2>&1)
if exist "%TMP%" (del /f /s /q "%TMP%\*.*" >nul 2>&1)
if exist "%LOCALAPPDATA%\Temp" (del /f /s /q "%LOCALAPPDATA%\Temp\*.*" >nul 2>&1)
echo [02/17] Clearing Windows temp...
if exist "%SystemRoot%\Temp" (del /f /s /q "%SystemRoot%\Temp\*.*" >nul 2>&1)
echo [03/17] Clearing prefetch...
if exist "%SystemRoot%\Prefetch" (del /f /s /q "%SystemRoot%\Prefetch\*.*" >nul 2>&1)
echo [04/17] Emptying Recycle Bin...
if exist "%systemdrive%\$Recycle.Bin" (rd /s /q "%systemdrive%\$Recycle.Bin" >nul 2>&1)
echo [05/17] Clearing recent files list...
if exist "%APPDATA%\Microsoft\Windows\Recent" (del /f /s /q "%APPDATA%\Microsoft\Windows\Recent\*.*" >nul 2>&1)
echo [06/17] Clearing thumbnail cache...
if exist "%LOCALAPPDATA%\Microsoft\Windows\Explorer" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1)
echo [07/17] Clearing browser cache...
if exist "%LOCALAPPDATA%\Microsoft\Windows\INetCache" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Windows\INetCache\*.*" >nul 2>&1)
if exist "%LOCALAPPDATA%\Microsoft\Windows\WebCache" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Windows\WebCache\*.*" >nul 2>&1)
echo [08/17] Clearing error reports...
if exist "%LOCALAPPDATA%\Microsoft\Windows\WER" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Windows\WER\*.*" >nul 2>&1)
if exist "%ALLUSERSPROFILE%\Microsoft\Windows\WER" (del /f /s /q "%ALLUSERSPROFILE%\Microsoft\Windows\WER\*.*" >nul 2>&1)
echo [09/17] Clearing Delivery Optimization cache...
if exist "%systemdrive%\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" (del /f /s /q "%systemdrive%\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*.*" >nul 2>&1)
echo [10/17] Clearing Windows Update download cache...
net stop wuauserv >nul 2>&1
if exist "%SystemRoot%\SoftwareDistribution\Download" (del /f /s /q "%SystemRoot%\SoftwareDistribution\Download\*.*" >nul 2>&1)
if exist "%SystemRoot%\Logs\WindowsUpdate" (del /f /s /q "%SystemRoot%\Logs\WindowsUpdate\*.*" >nul 2>&1)
net start wuauserv >nul 2>&1
echo [11/17] Clearing font cache...
net stop FontCache >nul 2>&1
net stop FontCache3.0.0.0 >nul 2>&1
if exist "%SystemRoot%\ServiceProfiles\LocalService\AppData\Local\FontCache" (del /f /s /q "%SystemRoot%\ServiceProfiles\LocalService\AppData\Local\FontCache\*.*" >nul 2>&1)
net start FontCache >nul 2>&1
echo [12/17] Clearing Windows Installer patch cache...
if exist "%SystemRoot%\Installer\$PatchCache$" (rmdir /s /q "%SystemRoot%\Installer\$PatchCache$" >nul 2>&1)
echo [13/17] Clearing DirectX shader cache...
if exist "%LOCALAPPDATA%\D3DSCache" (del /f /s /q "%LOCALAPPDATA%\D3DSCache\*.*" >nul 2>&1)
echo [14/17] Clearing Teams cache...
if exist "%LOCALAPPDATA%\Microsoft\Teams\Cache" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Teams\Cache\*.*" >nul 2>&1)
if exist "%LOCALAPPDATA%\Microsoft\Teams\blob_storage" (del /f /s /q "%LOCALAPPDATA%\Microsoft\Teams\blob_storage\*.*" >nul 2>&1)
echo [15/17] Clearing Windows Defender scan history...
if exist "%ProgramData%\Microsoft\Windows Defender\Scans\History" (del /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\*.*" >nul 2>&1)
echo [16/17] Clearing CBS logs...
if exist "%SystemRoot%\Logs\CBS" (del /f /s /q "%SystemRoot%\Logs\CBS\*.*" >nul 2>&1)
echo [17/17] Clearing memory dumps...
if exist "%SystemRoot%\Minidump" (del /f /s /q "%SystemRoot%\Minidump\*.*" >nul 2>&1)
if exist "%SystemRoot%\memory.dmp" (del /f /q "%SystemRoot%\memory.dmp" >nul 2>&1)
echo.
cleanmgr /sagerun:99
goto :eof
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:do_restore_point
echo Creating a new Restore Point...
for /f "tokens=* USEBACKQ" %%F IN (`time /t`) DO set "time=%%F"
powershell.exe -Command "Checkpoint-Computer -Description 'System_Checkup_%time%' -RestorePointType 'MODIFY_SETTINGS'" >nul 2>&1
echo Restore Point Created.
goto :eof
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:do_chkdsk
if "%drive%"=="2" (
    echo y|chkdsk "%drive1%:" /F /R /perf /scan
    echo y|chkdsk "%drive2%:" /F /R /perf /scan
) else echo y|chkdsk "%drive%:" /F /R /perf /scan
goto :eof
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:do_full_repair
ipconfig /flushdns & sfc /scannow & dism /online /cleanup-image /restorehealth
call :do_chkdsk
echo.
start explorer.exe
echo Process finished, press any key to restart your system.
pause>nul & shutdown -r -t 1
exit
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:Color
SetLocal EnableExtensions EnableDelayedExpansion
Set "Text=%~2"
If Not Defined Text (Set Text=^")
Subst `: "!Temp!" >Nul &`: &Cd \
If Not Exist `.7 (
Echo(|(Pause >Nul &Findstr "^" >`)
Set /P "=." >>` <Nul
For /F "delims=;" %%# In (
'"Prompt $H;&For %%_ In (_) Do Rem"') Do (
Set /P "=%%#%%#%%#" <Nul >`.3
Set /P "=%%#%%#%%#%%#%%#" <Nul >`.5
Set /P "=%%#%%#%%#%%#%%#%%#%%#" <Nul >`.7))
Set /P "LF=" <` &Set "LF=!LF:~0,1!"
For %%# in ("!LF!") Do For %%_ In (
\ / :) Do Set "Text=!Text:%%_=%%~#%%_%%~#!"
For /F delims^=^ eol^= %%# in ("!Text!") Do (
If #==#! SetLocal DisableDelayedExpansion
If \==%%# (Findstr /A:%~1 . \` Nul
Type `.3) Else If /==%%# (Findstr /A:%~1 . /.\` Nul
Type `.5) Else (Echo %%#\..\`>`.dat
Findstr /F:`.dat /A:%~1 .
Type `.7))
If "\n"=="%~3" (Echo()
Goto :Eof