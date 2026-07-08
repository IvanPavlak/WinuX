function Unpin-TaskbarApps {
	<#
	.SYNOPSIS
		Clears taskbar pins and applies an XML layout policy to prevent taskbar modifications.

	.DESCRIPTION
		Calls `Clear-TaskbarPins`, then deploys a TaskbarLayout XML policy via Group Policy.
		The policy prevents users from modifying the taskbar layout until `Remove-Item` is called
		on the policy registry key.

		With `-FromBootstrap`, skips Explorer restart after clearing pins (let the caller handle it).
		With `-SkipExplorerRestart`, also skips the Explorer restart.

		Requires administrator privileges.

	.PARAMETER SkipExplorerRestart
		Skips the Explorer restart after clearing pins.

	.PARAMETER FromBootstrap
		Used internally during bootstrap; passes `-SkipExplorerRestart` to `Clear-TaskbarPins`.

	.EXAMPLE
		Unpin-TaskbarApps
		Clears taskbar pins and applies the policy.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$SkipExplorerRestart,

		[Parameter(Mandatory = $false)]
		[switch]$FromBootstrap
	)

	Test-AdminPrivileges

	Write-LogTitle "Unpinning All Taskbar Applications"

	Clear-TaskbarPins -SkipExplorerRestart

	Write-LogStep "=> Configuring XML layout policy (prevents taskbar modifications)..."

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
      <taskbar:TaskbarPinList>
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
		Write-LogStep "=> Created empty taskbar layout at [$xmlPath]"
	}
	catch {
		Write-LogError "Failed to save taskbar layout XML: $($_.Exception.Message)"
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

		if (-not $FromBootstrap) {
			Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 1 -Type DWord -Force
			Write-LogStep "=> Registry keys configured!"
		}
		else {
			Write-LogStep "=> Registry key configured (layout will be locked by Bootstrap)!"
		}
	}
	catch {
		Write-LogError "Failed to configure registry keys: $($_.Exception.Message)"
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
				Write-LogSuccess "Symbolic link overriden => [$symlinkPath] => [$symlinkTarget]"
			}
			catch {
				Write-LogError "Failed to create symbolic link [$($_.Exception.Message)]"
			}
		}
		else {
			Write-LogWarning "Taskbar symbolic link configuration not found!"
		}
	}
	else {
		Write-LogStep "=> Symbolic link will be created by Bootstrap!"
	}

	if (-not $SkipExplorerRestart -and -not $FromBootstrap) {
		Restart-Explorer -Message "Waiting for Explorer to fully restart and apply empty taskbar layout..."
	}

	Write-LogSuccess "All taskbar applications have been unpinned!"
}
