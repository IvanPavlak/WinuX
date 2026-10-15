function Docker-Cleanup {
	<#
	.SYNOPSIS
		Menu-driven Docker cleanup with per-action confirmation safeguards.

	.DESCRIPTION
		Presents the cleanup actions defined in Configuration.DockerCleanupActions plus
		an "All" option, and runs the selected ones (several can be picked at once) in
		configuration order. Each configured entry has:
		- Name                : the menu label
		- Description         : optional - one sentence on what the action does
		- Command             : the PowerShell command line to run
		- PreviewCommand      : optional - a command whose output lists what the action
		                        would stop or remove
		- ConfirmationMessage : optional - when present, the action only runs after an
		                        explicit "Yes" on a red prompt (Enter defaults to "No")

		Before anything runs, every selected action prints its name, its Description and
		the items its PreviewCommand lists. An action whose preview lists nothing is
		skipped; when nothing is left the function returns without a prompt. One red
		confirmation then covers all remaining actions (an action's own message when it
		is the only one), so destructive operations can never fire on muscle memory. A
		failing action is reported and the remaining ones still run.

		The shipped defaults stop all containers, delete all containers, delete all
		images, delete all volumes, and prune unused networks and the build cache - so
		"All" wipes Docker completely. Forks can replace the list wholesale in
		Configuration.local.psd1.

		When the Docker daemon is not running, Configuration.DockerCleanupStartMode
		decides what happens: "Ask" (the default, also used for an empty or unknown
		value) asks whether to start Docker, Enter meaning Yes; "Always" starts it
		without asking; "Never" warns and returns. Docker is started through
		DockerWizard -PassThru, and the menu only appears once it reports Success.

	.PARAMETER Action
		Optional action name(s) to run directly, skipping the menu: configured Names,
		menu numbers, or "All". The preview and the confirmation safeguard still apply.

	.EXAMPLE
		Docker-Cleanup

	.EXAMPLE
		Docker-Cleanup "Delete all volumes"

	.EXAMPLE
		Docker-Cleanup All

	.EXAMPLE
		Docker-Cleanup "Delete all containers", "Delete all volumes"
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string[]]$Action
	)

	if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Docker is not installed!"
		return
	}

	# Filtered, not just wrapped: an absent DockerCleanupActions yields @($null), whose
	# Count is 1, which would sail past the guard and offer a blank menu entry
	$cleanupActions = @((Get-ConfigSetting -Path 'DockerCleanupActions' -Default @()) | Where-Object { $_ -and $_.Name })
	if ($cleanupActions.Count -eq 0) {
		Write-LogWarning "No cleanup actions configured in Configuration.DockerCleanupActions!"
		return
	}

	docker info *> $null
	if ($LASTEXITCODE -ne 0) {
		# Ask is the default and the fallback for an empty or unknown value, so a typo
		# never silently starts Docker Desktop nor silently refuses to
		$startMode = "$(Get-ConfigSetting -Path 'DockerCleanupStartMode' -Default 'Ask')"

		if ($startMode -eq "Never") {
			Write-LogWarning "Docker is not running!"
			return
		}

		if ($startMode -ne "Always") {
			# Starting Docker deletes nothing, so Enter means Yes - the red, Enter-means-No
			# safeguard is reserved for the cleanup confirmation further down
			$startConfirmation = Resolve-Selection -PromptMessage "Docker is not running - start it?" -DefaultOptionIndex 1 -HideMenuTitle

			if ($startConfirmation -ne "Yes") {
				Write-LogWarning "Docker is not running - nothing was touched!"
				return
			}
		}

		$dockerResult = DockerWizard -PassThru
		if (-not $dockerResult -or -not $dockerResult.Success) {
			Write-LogError "Docker could not be started - nothing was touched!"
			return
		}
	}

	# "All" belongs to the menu, not to anybody's DockerCleanupActions, so it is added
	# here - the same shape Send-WakeOnLan and Visualize-Layouts use
	$actionNames = @($cleanupActions | ForEach-Object { $_.Name })

	$resolveParams = @{
		InputObject             = $Action
		OptionList              = @($actionNames + @("All"))
		MenuTitle               = "[Docker cleanup actions]"
		AllowMultipleSelections = $true
	}

	$selectedNames = @(Resolve-Selection @resolveParams | Where-Object { $_ })
	if ($selectedNames.Count -eq 0) {
		return
	}

	# Configuration order, never selection order: the shipped list stops and deletes
	# containers before the images and volumes they hold, so "All" or "5,2" still
	# runs in an order where every step can succeed
	$selectedActions = if ($selectedNames -contains "All") {
		$cleanupActions
	}
	else {
		@($cleanupActions | Where-Object { $selectedNames -contains $_.Name })
	}

	# Every preview runs before anything is touched, so the list the user confirms is
	# the state Docker is in now, not one an earlier action already changed
	$pendingActions = @()

	foreach ($actionEntry in $selectedActions) {
		$header = if ($actionEntry.Description) { "$($actionEntry.Name) - $($actionEntry.Description)" } else { $actionEntry.Name }

		if (-not $actionEntry.PreviewCommand) {
			Write-LogStep "=> $header"
			$pendingActions += $actionEntry
			continue
		}

		$previewItems = @(
			Invoke-Expression $actionEntry.PreviewCommand 2>$null |
				ForEach-Object { "$_".Trim() } |
				Where-Object { $_ }
		)

		if ($previewItems.Count -eq 0) {
			Write-LogWarning "$($actionEntry.Name) - nothing to do, skipped!"
			continue
		}

		Write-LogStep "=> $header"
		Write-LogList -Items $previewItems
		$pendingActions += $actionEntry
	}

	if ($pendingActions.Count -eq 0) {
		Write-LogWarning "Nothing to do - nothing was touched!"
		return
	}

	# One confirmation for the whole batch: asking per action would let a run stop
	# halfway, after the containers are gone but before the volumes the user meant
	# to wipe with them
	$confirmationMessage = if ($pendingActions.Count -eq 1) {
		$pendingActions[0].ConfirmationMessage
	}
	elseif (@($pendingActions | Where-Object { $_.ConfirmationMessage }).Count -gt 0) {
		"Are you sure you want to run these $($pendingActions.Count) actions?"
	}

	if ($confirmationMessage) {
		$confirmation = Resolve-Selection -ConfirmationMessage $confirmationMessage -HideMenuTitle

		if ($confirmation -ne "Yes") {
			Write-LogWarning "Cancelled - nothing was touched!"
			return
		}
	}

	# A failing action does not stop the ones after it: each is independent of the
	# previous one's exit code (removing images does not need every stop to succeed),
	# and each failure is reported on its own
	foreach ($actionEntry in $pendingActions) {
		Write-LogStep "=> $($actionEntry.Name)..."
		$global:LASTEXITCODE = 0
		Invoke-Expression $actionEntry.Command

		if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
			Write-LogSuccess "$($actionEntry.Name) completed!"
		}
		else {
			Write-LogError "$($actionEntry.Name) failed with exit code [$LASTEXITCODE]!"
		}
	}
}
