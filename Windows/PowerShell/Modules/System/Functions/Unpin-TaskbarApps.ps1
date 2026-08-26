function Unpin-TaskbarApps {
	<#
	.SYNOPSIS
		Clears taskbar pins and applies an XML layout policy to prevent taskbar modifications.

	.DESCRIPTION
		Calls `Clear-TaskbarPins`, then deploys a TaskbarLayout XML policy via Group Policy.
		The policy prevents users from modifying the taskbar layout until `Remove-Item` is called
		on the policy registry key.

		The empty layout XML is written directly to the machine-local `TaskbarLayoutFile` path
		(the StartLayoutFile the policy points at); it is not versioned in the repository.

		With `-FromBootstrap`, skips Explorer restart after clearing pins (let the caller handle it).
		With `-SkipExplorerRestart`, also skips the Explorer restart.

		Requires administrator privileges.

	.PARAMETER SkipExplorerRestart
		Skips the Explorer restart after clearing pins.

	.PARAMETER FromBootstrap
		Used internally during bootstrap; passes `-SkipExplorerRestart` to `Clear-TaskbarPins`.

	.PARAMETER BackupRoot
		Root of the unified backup sink an existing real layout file is copied into before it
		is overwritten. Defaults to <Repo>\Backups\Windows resolved inside Backup-RepositoryItem.

	.EXAMPLE
		Unpin-TaskbarApps
		Clears taskbar pins and applies the policy.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$SkipExplorerRestart,

		[Parameter(Mandatory = $false)]
		[switch]$FromBootstrap,

		[string]$BackupRoot = ""
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

	$layoutFile = $MachineSpecificPaths.TaskbarLayoutFile
	if (-not $layoutFile) {
		Write-LogError "TaskbarLayoutFile not found in configuration!"
		return
	}

	$layoutDir = Split-Path -Parent $layoutFile
	if ($layoutDir -and -not (Test-Path $layoutDir)) {
		New-Item -Path $layoutDir -ItemType Directory -Force | Out-Null
	}

	# A machine provisioned by the old design has a symlink here pointing into the repo; writing
	# through it would modify the versioned file. Remove any such link (live or dangling) first so
	# the empty layout is written as a real machine-local file.
	$existingLayout = Get-Item -LiteralPath $layoutFile -Force -ErrorAction SilentlyContinue
	if ($existingLayout -and $existingLayout.LinkType) {
		Remove-Item -LiteralPath $layoutFile -Force -ErrorAction SilentlyContinue
	}
	elseif ($existingLayout) {
		# A REAL layout file may encode the user's own hand-pinned arrangement; keep an undo in
		# the unified backup sink before replacing it with the empty layout. A backup that cannot
		# be taken skips the write - a layout that could not be saved is never replaced.
		try {
			$backupDir = Backup-RepositoryItem -Path $layoutFile -Category "System" -Key "TaskbarLayout" -BackupRoot $BackupRoot
			Write-LogWarning "Backed up existing taskbar layout => [$layoutFile] => [$backupDir]"
		}
		catch {
			Write-LogError "Skipped taskbar layout (could not back up the existing file) => [$layoutFile] => $($_.Exception.Message)"
			return
		}
	}

	try {
		$taskbarLayout | Out-File $layoutFile -Encoding utf8 -Force
		Write-LogStep "=> Created empty taskbar layout at [$layoutFile]"
	}
	catch {
		Write-LogError "Failed to save taskbar layout XML: $($_.Exception.Message)"
		return
	}

	try {
		$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"

		if (-not (Test-Path $explorerPolicyRegistryPath)) {
			New-Item -Path $explorerPolicyRegistryPath -Force | Out-Null
		}

		Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "StartLayoutFile" -Value $layoutFile -Type ExpandString -Force

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

	if (-not $SkipExplorerRestart -and -not $FromBootstrap) {
		Restart-Explorer -Message "Waiting for Explorer to fully restart and apply empty taskbar layout..."
	}

	Write-LogSuccess "All taskbar applications have been unpinned!"
}
