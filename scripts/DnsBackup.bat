@echo off

REM DNS Backup & Restore pentru Windows Server 2003

set ACTION=%1
for /f "tokens=1-4 delims=/ " %%a in ('date /t') do set DATE=%%d%%c%%b
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIME=%%a%%b
set COMPUTERNAME=%COMPUTERNAME%
set BACKUP_DIR=C:\DNS-Backup-%COMPUTERNAME%-%DATE%-%TIME%

if "%ACTION%"=="export" goto EXPORT
if "%ACTION%"=="import" goto IMPORT

echo Usage: %0 [export|import] [import_directory]
goto END

:EXPORT
echo Starting DNS export...
mkdir "%BACKUP_DIR%\zones"

REM Copiază doar fișierele .dns (fără subfoldere)
xcopy "%SystemRoot%\System32\dns\*.dns" "%BACKUP_DIR%\zones\" /C /H /R /Y

REM Exportă registry DNS
reg export "HKLM\SYSTEM\CurrentControlSet\Services\DNS" "%BACKUP_DIR%\dns_config.reg" /y
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\DNS Server\Zones" "%BACKUP_DIR%\dns_zones.reg" /y

echo Backup completed to %BACKUP_DIR%
goto END

:IMPORT
echo Starting DNS import...
set IMPORT_DIR=%2
if "%IMPORT_DIR%"=="" (
    echo Specify import directory!
    goto END
)

REM Importă registry DNS
reg import "%IMPORT_DIR%\dns_config.reg"
reg import "%IMPORT_DIR%\dns_zones.reg"

REM Copiază doar fișierele .dns (fără subfoldere)
xcopy "%IMPORT_DIR%\zones\*.dns" "%SystemRoot%\System32\dns\" /C /H /R /Y

echo DNS import completed from %IMPORT_DIR%
goto END

:END
pause
