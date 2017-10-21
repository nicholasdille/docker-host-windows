@echo off

rem Enable unsigned scripts
reg add HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell /v ExecutionPolicy /t REG_SZ /d "RemoteSigned" /f

rem Set shell to PowerShell
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\AlternateShells\AvailableShells" /v 35000 /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /t REG_SZ /f

rem Launch setup in PowerShell
powershell.exe -command "%WinDir%\Setup\Scripts\SetupComplete.ps1"