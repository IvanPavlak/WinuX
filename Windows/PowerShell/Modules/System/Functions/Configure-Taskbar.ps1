function Configure-Taskbar {
	<#
	.SYNOPSIS
		Configures taskbar pins from the configuration.

	.DESCRIPTION
		Clears all existing taskbar pins and applies the pins from `TaskbarConfiguration` in
		Configuration.psd1. The layout XML is generated entirely from configuration and written
		directly to the machine-local `TaskbarLayoutFile` path that the StartLayoutFile Group
		Policy points at - it is not versioned in the repository and needs no symlink.

		Each `TaskbarConfiguration` row may carry a `Machine` scope ("All", "Test",
		"PC/Laptop", ...) matched against the current machine type by Test-MachineTypeScope -
		the same gate the app CSVs use - so one list can drive every machine. A row without a
		`Machine` key (or a blank one) defaults to "All" and pins on every machine.

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

	# Resolve the machine type and state it up front, so the output makes clear which machine's
	# pins are being applied (or that the hostname is unmapped and the default set is used).
	$MachineType = DetermineMachineType
	$hostname = $env:COMPUTERNAME
	$hostnameMapped = ($Configuration.HostnameToMachineType -is [hashtable]) -and $Configuration.HostnameToMachineType.ContainsKey($hostname)
	if ($hostnameMapped) {
		Write-LogStep "Configuring taskbar for machine type => [$MachineType]"
	}
	else {
		Write-LogStep "Configuring taskbar for the default machine set (hostname [$hostname] is not mapped) => [$MachineType]"
	}

	$taskbarPinList = ""
	foreach ($app in $taskbarConfig) {
		# A row's Machine scope ("All", "Test", "PC/Laptop", ...) is validated and matched by
		# Test-MachineTypeScope, mirroring the app CSVs' Machine column. A missing or blank
		# Machine defaults to "All", so an untagged app pins on every machine.
		$machineScope = if ($app.Machine) { "$($app.Machine)" } else { "All" }
		if (-not (Test-MachineTypeScope -Scope $machineScope -MachineType $MachineType -Context "TaskbarConfiguration [$($app.Name)]")) {
			continue
		}

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

	$layoutFile = $MachineSpecificPaths.TaskbarLayoutFile
	if (-not $layoutFile) {
		Write-LogError "TaskbarLayoutFile not found in configuration!"
		return
	}

	# The layout is produced entirely from configuration, so it is written straight to its
	# machine-local path (created if missing) - no versioned copy in the repo, no symlink.
	$layoutDir = Split-Path -Parent $layoutFile
	if ($layoutDir -and -not (Test-Path $layoutDir)) {
		New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
	}

	# A machine provisioned by the old design has a symlink here pointing into the repo; writing
	# through it would modify the versioned file. Remove any such link (live or dangling) first so
	# the layout is written as a real machine-local file.
	$existingLayout = Get-Item -LiteralPath $layoutFile -Force -ErrorAction SilentlyContinue
	if ($existingLayout -and $existingLayout.LinkType) {
		Remove-Item -LiteralPath $layoutFile -Force -ErrorAction SilentlyContinue
	}

	try {
		$taskbarLayout | Out-File $layoutFile -Encoding utf8 -Force
		Write-LogSuccess "Taskbar layout written => [$layoutFile]"
	}
	catch {
		Write-LogError "Failed to save taskbar layout XML => $($_.Exception.Message)"
		return
	}

	try {
		$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"

		if (-not (Test-Path $explorerPolicyRegistryPath)) {
			New-Item -Path $explorerPolicyRegistryPath -Force | Out-Null
		}

		Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "StartLayoutFile" -Value $layoutFile -Type ExpandString -Force

		Write-LogStep "Unlocking layout to apply XML configuration..."
		Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 0 -Type DWord -Force
	}
	catch {
		Write-LogError "Failed to configure registry keys => [$($_.Exception.Message)]"
		return
	}

	if (-not $FromBootstrap) {
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

		Write-LogSuccess "Taskbar configuration completed for [$MachineType]!"
	}
	else {
		Write-LogSuccess "Layout configuration ready for [$MachineType]!"
		Write-LogWarning "Note: Layout is currently unlocked. Bootstrap will lock it after Explorer restart!"
	}

	Write-LogWarning "If any app opens as a new, unpinned icon on the taskbar, right-click the new icon and select [Pin to taskbar] to fix it!"
}
