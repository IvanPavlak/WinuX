:: How to Fix the "Some Settings Are Managed By Your Organization" Bug in Windows 10/11

@Echo Off & Color 0E


(Net session >nul 2>&1)||(PowerShell start """%~0""" -verb RunAs & Exit /B)

PowerShell Checkpoint-Computer -Description "LocalGroupPolicy" -RestorePointType "MODIFY_SETTINGS"


Cls

secedit /configure /cfg %windir%\inf\defltbase.inf /db defltbase.sdb /verbose

Rd /S /Q  %SystemRoot%\System32\GroupPolicyUsers

Rd /S /Q  %SystemRoot%\System32\GroupPolicy

reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies" /f
reg delete "HKCU\Software\Microsoft\WindowsSelfHost" /f
reg delete "HKCU\Software\Policies" /f
reg delete "HKLM\Software\Microsoft\Policies" /f
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies" /f
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" /f
reg delete "HKLM\Software\Microsoft\WindowsSelfHost" /f
reg delete "HKLM\Software\Policies" /f
reg delete "HKLM\Software\WOW6432Node\Microsoft\Policies" /f
reg delete "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies" /f
reg delete "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" /f 

Cls

gpupdate /force 

Cls & Mode CON  LINES=11 COLS=55 & Color 0E & Title Created By FreeBooter
Echo.
Echo.
Echo.

CHOICE /C YN /M "Press Y to Reboot, N for exiting script."


If %errorlevel% == 1 ( Shutdown /r /t 0) Else (Exit)
