function Docker-Cleanup {
	<#
	.SYNOPSIS
		Menu-driven Docker cleanup with per-action confirmation safeguards.

	.DESCRIPTION
		Presents the cleanup actions defined in Configuration.DockerCleanupActions and
		runs the selected one. Each configured entry has a Name (the menu label), a
		Command (the PowerShell command line to run) and an optional
		ConfirmationMessage - when present, the action only runs after an explicit
		"Yes" on a red confirmation prompt (pressing Enter defaults to "No"), so
		destructive operations can never fire on muscle memory.

		The shipped defaults cover stopping all containers, deleting all containers/
		images/volumes (docker system prune) and deleting all volumes; forks can
		replace the list wholesale in Configuration.local.psd1.

	.PARAMETER Action
		Optional action name to run directly (must match a configured Name). The
		confirmation safeguard still applies.

	.EXAMPLE
		Docker-Cleanup

	.EXAMPLE
		Docker-Cleanup "Delete all volumes"
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string]$Action
	)

	if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Docker is not installed!"
		return
	}

	# Filtered, not just wrapped: an absent DockerCleanupActions yields @($null), whose
	# Count is 1, which would sail past the guard and offer a blank menu entry
	$cleanupActions = @($Configuration.DockerCleanupActions | Where-Object { $_ -and $_.Name })
	if ($cleanupActions.Count -eq 0) {
		Write-LogWarning "No cleanup actions configured in Configuration.DockerCleanupActions!"
		return
	}

	docker info *> $null
	if ($LASTEXITCODE -ne 0) {
		Write-LogWarning "Docker is not running!"
		return
	}

	$resolveParams = @{
		InputObject = $Action
		OptionList  = @($cleanupActions | ForEach-Object { $_.Name })
		MenuTitle   = "[Docker cleanup actions]"
	}

	$selectedAction = @(Resolve-Selection @resolveParams) | Select-Object -First 1
	if (-not $selectedAction) {
		return
	}

	$actionEntry = $cleanupActions | Where-Object { $_.Name -eq $selectedAction } | Select-Object -First 1

	if ($actionEntry.ConfirmationMessage) {
		$confirmation = Resolve-Selection -ConfirmationMessage $actionEntry.ConfirmationMessage -HideMenuTitle

		if ($confirmation -ne "Yes") {
			Write-LogWarning "Cancelled - nothing was touched!"
			return
		}
	}

	Write-LogStep "=> $($actionEntry.Name)..."
	Invoke-Expression $actionEntry.Command

	if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
		Write-LogSuccess "$($actionEntry.Name) completed!"
	}
	else {
		Write-LogError "$($actionEntry.Name) failed with exit code [$LASTEXITCODE]!"
	}
}
