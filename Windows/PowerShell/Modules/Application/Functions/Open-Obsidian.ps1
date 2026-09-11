function Open-Obsidian {
	<#
	.SYNOPSIS
		Opens Obsidian, optionally into a saved Obsidian workspace.

	.DESCRIPTION
		Launches Obsidian through the official Obsidian command line interface (`Obsidian.com`,
		registered as `obsidian` on PATH from Settings > General > Command line interface) and,
		when a workspace is resolved, loads it with `obsidian vault=<Vault> workspace:load name=<Name>`.
		The CLI talks to the running instance, so with Obsidian already open the workspace is
		switched in place - no second window. Without a workspace an already-running Obsidian is
		left alone, as before.

		The workspace to load is resolved in this order:
		  1. -Workspace <Name>, or the menu -Select offers (names read from workspaces.json).
		  2. -CurrentWorkspace <Name>, injected by Open-Workspace with the WinuX workspace being
		     opened, when an Obsidian workspace of the SAME name exists in the vault. So `w Server`
		     lands Obsidian on its "Server" workspace as soon as the vault has one; a WinuX
		     workspace without a same-named Obsidian workspace loads nothing.
		  3. $Configuration.Obsidian.DefaultWorkspace, on a cold start only.
		  4. Nothing - Obsidian opens (or stays) wherever it is.

		The vault name for the CLI is $Configuration.Obsidian.Vault when set, else the leaf folder
		of $MachineSpecificPaths.ObsidianDirectory. Saved workspace names are read from
		<ObsidianDirectory>\.obsidian\workspaces.json; an explicit name that is not in that list is
		reported and still attempted.

		A cold start launches Obsidian.exe with the obsidian://open?vault= URI through WMI
		(Win32_Process.Create), so the new process is a child of the WMI provider host and owns no
		console. Launched as a child of the shell, Electron attaches to the shell's console and
		closing that terminal closes Obsidian with it - the reason the old pythonw hop existed. The
		CLI itself refuses to run while Obsidian is down. The function then polls the CLI until it
		answers - about half a second after launch, 10 seconds at most - and loads the workspace.
		When the CLI cannot be found (neither on PATH nor beside Obsidian.exe) a requested workspace
		is reported with the steps to register the CLI, and Obsidian still opens.

	.PARAMETER Workspace
		The Obsidian workspace to load. Takes precedence over -CurrentWorkspace and the configured
		default.

	.PARAMETER Select
		Pick the workspace from a menu of the vault's saved workspaces instead of naming it.
		PowerShell cannot bind a bare "-Workspace" with no value, hence the separate switch.

	.PARAMETER CurrentWorkspace
		The WinuX workspace being opened. Injected by Open-Workspace; only used when the vault has
		an Obsidian workspace of the same name. Not meant to be passed by hand.

	.EXAMPLE
		Open-Obsidian
		Opens Obsidian (into Obsidian.DefaultWorkspace when configured); does nothing if it already runs.

	.EXAMPLE
		Open-Obsidian -Workspace Server
		Opens Obsidian into the "Server" workspace, or switches the running instance to it.

	.EXAMPLE
		Open-Obsidian -Select
		Lists the saved workspaces and loads the chosen one.

	.EXAMPLE
		@{ Action = "Open-Obsidian"; Parameters = @{ Workspace = "DSA" } }
		A WorkspaceActions entry that loads "DSA" regardless of the WinuX workspace name.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string]$Workspace,

		[Parameter()]
		[switch]$Select,

		[Parameter()]
		[string]$CurrentWorkspace
	)

	$obsidianConfig = if ($global:Configuration -and $global:Configuration.Obsidian -is [hashtable]) { $global:Configuration.Obsidian } else { @{} }
	$vaultDirectory = if ($global:MachineSpecificPaths) { [string]$global:MachineSpecificPaths.ObsidianDirectory } else { '' }

	$vault = [string]$obsidianConfig.Vault
	if ([string]::IsNullOrWhiteSpace($vault)) {
		$vault = if ([string]::IsNullOrWhiteSpace($vaultDirectory)) { '' } else { Split-Path -Leaf $vaultDirectory.TrimEnd('\', '/') }
	}
	if ([string]::IsNullOrWhiteSpace($vault)) {
		Write-LogError "Error: Neither Obsidian.Vault nor PathTemplates.ObsidianDirectory is configured. Check the Configuration.local.psd1 file!"
		return
	}

	$savedWorkspaces = @(Get-ObsidianWorkspaceNames -VaultDirectory $vaultDirectory)
	$isRunning = [bool](Get-Process -Name 'obsidian' -ErrorAction SilentlyContinue)

	# --- Resolve the workspace to load --------------------------------------------------------
	$targetWorkspace = $null
	if ($Select) {
		if ($savedWorkspaces.Count -eq 0) {
			Write-LogWarning "No saved Obsidian workspaces found in [$vault] to choose from!"
		}
		else {
			$selection = Resolve-Selection -OptionList $savedWorkspaces `
				-MenuTitle "[Available Obsidian workspaces]" `
				-PromptMessage "Enter Obsidian workspace or press [Enter] to skip" `
				-AllowEmptyPromptResponse
			if ($selection -is [array]) { $selection = @($selection)[0] }
			if (-not [string]::IsNullOrWhiteSpace([string]$selection)) { $targetWorkspace = ([string]$selection).Trim() }
		}
	}
	elseif (-not [string]::IsNullOrWhiteSpace($Workspace)) {
		$targetWorkspace = $Workspace.Trim()
		if ($savedWorkspaces.Count -gt 0 -and $targetWorkspace -notin $savedWorkspaces) {
			Write-LogWarning "Obsidian workspace [$targetWorkspace] is not saved in vault [$vault] (saved: $($savedWorkspaces -join ', ')) - attempting anyway."
		}
	}
	elseif (-not [string]::IsNullOrWhiteSpace($CurrentWorkspace) -and $CurrentWorkspace.Trim() -in $savedWorkspaces) {
		$targetWorkspace = $CurrentWorkspace.Trim()
		Write-LogDebug " [Open-Obsidian] Same-named Obsidian workspace found for [$targetWorkspace]" -Style Success
	}
	elseif (-not $isRunning -and -not [string]::IsNullOrWhiteSpace([string]$obsidianConfig.DefaultWorkspace)) {
		$targetWorkspace = ([string]$obsidianConfig.DefaultWorkspace).Trim()
	}

	# --- Already running -------------------------------------------------------------------------
	$cli = Get-ObsidianCliPath
	$cliMissingWarning = "Obsidian CLI not found - cannot load a workspace. Enable it in Obsidian under Settings > General > Command line interface, then put its folder on PATH (AutoPathAdditions: `"%LOCALAPPDATA%\Programs\obsidian`") and open a new shell."

	if ($isRunning) {
		if (-not $targetWorkspace) {
			Write-LogWarning "Obsidian is already running!"
			return
		}
		if (-not $cli) {
			Write-LogWarning $cliMissingWarning
			return
		}
		Write-LogStep "Loading Obsidian workspace [$targetWorkspace]..."
		Invoke-ObsidianCli -CliPath $cli -Arguments @("vault=$vault", 'workspace:load', "name=$targetWorkspace") | Out-Null
		Write-LogSuccess "Obsidian workspace [$targetWorkspace] loaded!"
		return
	}

	# --- Cold start ------------------------------------------------------------------------------
	Write-LogStep "Opening Obsidian..."

	# The CLI only talks to a running Obsidian ("The CLI is unable to find Obsidian", exit 1 when
	# it is down), so the launch itself is a detached Obsidian.exe with the vault URI.
	Start-ObsidianDetached -Vault $vault

	if (-not $targetWorkspace) {
		Write-LogSuccess "Obsidian opened!"
		return
	}

	if (-not $cli) {
		Write-LogWarning $cliMissingWarning
		Write-LogSuccess "Obsidian opened!"
		return
	}

	# The CLI starts answering roughly a second after launch (measured: window at 0.4 s, CLI at
	# 1.0 s), after the Homepage plugin has done its startup load - so this load is the one that
	# sticks.
	if (Wait-ObsidianCli -CliPath $cli -Vault $vault -TimeoutSeconds 10) {
		Invoke-ObsidianCli -CliPath $cli -Arguments @("vault=$vault", 'workspace:load', "name=$targetWorkspace") | Out-Null
		Write-LogSuccess "Obsidian opened in workspace [$targetWorkspace]!"
	}
	else {
		Write-LogWarning "Obsidian CLI did not answer within 10 seconds - workspace [$targetWorkspace] may not be loaded. Run [Open-Obsidian -Workspace $targetWorkspace] again once it is up."
	}
}
