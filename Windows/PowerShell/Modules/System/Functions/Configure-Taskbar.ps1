function Configure-Taskbar {
	<#
	.SYNOPSIS
		Configures taskbar pins from the configuration.

	.DESCRIPTION
		Clears all existing taskbar pins, creates the taskbar pin folder, and applies
		new pin shortcuts from `TaskbarConfiguration` in Configuration.psd1.

		With `-FromBootstrap`, skips a 5-second initialization delay (used when called
		during the bootstrap sequence before all processes are fully settled).

		Requires administrator privileges.

	.PARAMETER FromBootstrap
		Skips the 5-second wait for Explorer initialization (used internally during setup).

	.EXAMPLE
		Configure-Taskbar
		Clears and reconfigures the taskbar pins.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$FromBootstrap
	)

	Test-AdminPrivileges

	if ($FromBootstrap) {
		Unpin-TaskbarApps -FromBootstrap
	}
	else {
		Unpin-TaskbarApps
	}

	if ($FromBootstrap) {
		Loading-Spinner -Function { Start-Sleep 5 } -Label "Allowing Explorer to complete initialization before configuring taskbar apps..."
	}

	Write-LogTitle "Configuring Taskbar"

	Write-LogStep "Cleaning up existing taskbar shortcuts..."
	$taskbarPinFolder = $Configuration.Universal.TaskbarPinFolder
	if (Test-Path $taskbarPinFolder) {
		try {
			Get-ChildItem -Path $taskbarPinFolder -Filter "*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
			Write-LogSuccess "Taskbar shortcuts cleared!" -NoLeadingNewline
		}
		catch {
			Write-LogWarning "Could not clear all shortcuts => [$($_.Exception.Message)]" -NoLeadingNewline
		}
	}

	$taskbarConfig = $Configuration.TaskbarConfiguration
	if (-not $taskbarConfig) {
		Write-LogError "TaskbarConfiguration not found in configuration!"
		return
	}

	$taskbarPinList = ""
	foreach ($app in $taskbarConfig) {
		if ($app.Type -eq "AUMID") {
			$taskbarPinList += "`n        <taskbar:DesktopApp DesktopApplicationID=`"$($app.Value)`" />"
		}
		elseif ($app.Type -eq "Path") {
			$appPath = $app.Value -replace '\{User\}', "C:\Users\$env:USERNAME"
			$taskbarPinList += "`n        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$appPath`" />"
		}
	}

	$taskbarLayout = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>$taskbarPinList
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
 </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

	$taskbarConfigDir = $MachineSpecificPaths.TaskbarConfigurationDir
	if (-not $taskbarConfigDir) {
		Write-LogError "TaskbarConfigurationDir not found in configuration!"
		return
	}

	if (-not (Test-Path $taskbarConfigDir)) {
		New-Item -Path $taskbarConfigDir -ItemType Directory -Force | Out-Null
	}

	$xmlPath = Join-Path -Path $taskbarConfigDir -ChildPath "taskbar_layout.xml"

	try {
		$taskbarLayout | Out-File $xmlPath -Encoding utf8 -Force
	}
	catch {
		Write-LogError "Failed to save taskbar layout XML => $($_.Exception.Message)"
		return
	}

	$provisioningPath = $Configuration.PathTemplates.SymbolicLinks.TaskbarConfiguration.Path
	if (-not $provisioningPath) {
		Write-LogError "Taskbar provisioning path not found in configuration!"
		return
	}

	try {
		$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"

		if (-not (Test-Path $explorerPolicyRegistryPath)) {
			New-Item -Path $explorerPolicyRegistryPath -Force | Out-Null
		}

		Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "StartLayoutFile" -Value $provisioningPath -Type ExpandString -Force

		Write-LogStep "Unlocking layout to apply XML configuration..."
		Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 0 -Type DWord -Force
	}
	catch {
		Write-LogError "Failed to configure registry keys => [$($_.Exception.Message)]"
		return
	}

	if (-not $FromBootstrap) {
		$taskbarSymlinkConfig = $MachineSpecificPaths.SymbolicLinks.TaskbarConfiguration
		if ($taskbarSymlinkConfig -and $taskbarSymlinkConfig.Path -and $taskbarSymlinkConfig.Target) {
			$symlinkPath = $taskbarSymlinkConfig.Path
			$symlinkTarget = $taskbarSymlinkConfig.Target

			if (Test-Path $symlinkPath) {
				Remove-Item -Path $symlinkPath -Force -ErrorAction SilentlyContinue
			}

			$parentDir = Split-Path -Parent $symlinkPath
			if ($parentDir -and -not (Test-Path $parentDir)) {
				New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
			}

			try {
				New-Item -ItemType SymbolicLink -Path $symlinkPath -Target $symlinkTarget -Force | Out-Null
				Write-LogSuccess "Symbolic link created [$symlinkPath] => [$symlinkTarget]"
			}
			catch {
				Write-LogError "Failed to create symbolic link => [$($_.Exception.Message)]"
			}
		}
		else {
			Write-LogWarning "Taskbar symbolic link configuration not found!"
		}


		try {
			$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
			Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 1 -Type DWord -Force
			Write-LogSuccess "Layout locked to prevent future modifications!"
		}
		catch {
			Write-LogWarning "Could not lock layout => [$($_.Exception.Message)]"
		}

		Restart-Explorer -Message "Allowing Explorer to apply XML layout..."

		Rebuild-IconCache

		Write-LogSuccess "Taskbar configuration completed!"
	}
	else {
		Write-LogSuccess "Layout configuration ready!"
		Write-LogWarning "Note: Layout is currently unlocked. Bootstrap will lock it after Explorer restart!"
	}

	Write-LogWarning "If any app opens as a new, unpinned icon on the taskbar, right-click the new icon and select [Pin to taskbar] to fix it!"
}
