function Open-Obsidian {
	<#
	.SYNOPSIS
		Opens Obsidian, optionally into a saved Obsidian workspace.

	.DESCRIPTION
		Launches Obsidian through the official Obsidian command line interface (`Obsidian.com`,
		registered as `obsidian` on PATH from Settings > General > Advanced > Command line interface)
		and, when a workspace is resolved, loads it with `obsidian vault=<Vault> workspace:load name=<Name>`.
		The CLI talks to the running instance, so with Obsidian already open the workspace is
		switched in place - no second window. Without a workspace an already-running Obsidian is
		left alone, as before.

		The workspace to load is resolved in this order:
		  1. -Workspace <Name>.
		  2. -CurrentWorkspace <Name>, injected by Open-Workspace with the WinuX workspace being
		     opened, when an Obsidian workspace of the SAME name exists in the vault. So `w Server`
		     lands Obsidian on its "Server" workspace as soon as the vault has one; a WinuX
		     workspace without a same-named Obsidian workspace loads nothing.
		  3. Otherwise, unless -Default is given, a menu of the vault's saved workspaces
		     (Resolve-Selection, the same pattern as Open-VSCode and Open-VisualStudio): a bare
		     `Open-Obsidian` by hand picks one, [Enter] skips.
		  4. $Configuration.Obsidian.DefaultWorkspace, on a cold start only.
		  5. Nothing - Obsidian opens (or stays) wherever it is.

		Inside a workspace open the injected CurrentWorkspace suppresses the menu, so workspace
		actions never prompt; `Parameters = @{ Default = $true }` on them is optional and harmless.
		An action list without that injection (ProjectActions) must pass it, or a Workspace, to
		stay non-interactive.

		The vault name for the CLI is $Configuration.Obsidian.Vault when set, else the leaf folder
		of $MachineSpecificPaths.ObsidianDirectory. Saved workspace names are read from
		<ObsidianDirectory>\.obsidian\workspaces.json (Get-ObsidianWorkspaceNames lists them); an
		explicit name that is not in that list is reported and still attempted.

		A cold start launches Obsidian.exe with the obsidian://open?vault= URI through WMI
		(Win32_Process.Create), so the new process is a child of the WMI provider host and owns no
		console. Launched as a child of the shell, Electron attaches to the shell's console and
		closing that terminal closes Obsidian with it - the reason the old pythonw hop existed. The
		CLI itself refuses to run while Obsidian is down. The function then polls the CLI until it
		answers - about half a second after launch, 10 seconds at most - and loads the workspace.

		The CLI's answer to the load is checked. The CLI toggle is per machine (Obsidian keeps it in
		%APPDATA%\obsidian\obsidian.json, not in the vault), so on a machine where it is off the CLI
		answers "Command line interface is not enabled" and the workspace is reported as NOT loaded,
		together with the fix (Enable-ObsidianCli with Obsidian closed, or the Settings toggle) -
		never as a success. When the CLI cannot be found at all (neither on PATH nor beside
		Obsidian.exe) a requested workspace is reported with the steps to register the CLI, and
		Obsidian still opens.

	.PARAMETER Workspace
		The Obsidian workspace to load. Takes precedence over -CurrentWorkspace and the configured
		default.

	.PARAMETER Default
		Skip the workspace menu: open Obsidian (into Obsidian.DefaultWorkspace on a cold start when
		configured) or leave the running one alone. Same role as -Default on Open-VSCode. Only the
		prompt is removed - an explicit -Workspace and the same-named CurrentWorkspace match still
		apply, so `Parameters = @{ Default = $true }` on a workspace action is safe belt-and-braces.

	.PARAMETER Deferred
		Record the workspace load instead of performing it, and return as soon as Obsidian is
		launched. Injected by Open-Workspace: the load is registered through
		Register-DeferredAction as a Complete-ObsidianWorkspaceLoad call, and the flow runs every
		registered tail (Complete-DeferredActions) once the remaining openers have run and before
		the layout starts waiting on window titles. The CLI round trip is seconds of waiting on Obsidian's own
		startup, and every action queued behind this one used to pay them. Not meant to be passed by
		hand: a bare Open-Obsidian loads the workspace before it returns, as always.

	.PARAMETER CurrentWorkspace
		The WinuX workspace being opened. Injected by Open-Workspace; only used when the vault has
		an Obsidian workspace of the same name. Not meant to be passed by hand.

	.EXAMPLE
		Open-Obsidian
		Lists the saved workspaces and opens Obsidian into the chosen one, or switches the running
		instance to it; [Enter] skips the menu.

	.EXAMPLE
		Open-Obsidian -Default
		Opens Obsidian (into Obsidian.DefaultWorkspace when configured); does nothing if it already runs.

	.EXAMPLE
		Open-Obsidian -Workspace Server
		Opens Obsidian into the "Server" workspace, or switches the running instance to it.

	.EXAMPLE
		@{ Action = "Open-Obsidian"; Parameters = @{ Workspace = "DSA" } }
		A WorkspaceActions entry that loads "DSA" regardless of the WinuX workspace name.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string]$Workspace,

		[Parameter()]
		[switch]$Default,

		[Parameter()]
		[string]$CurrentWorkspace,

		[Parameter()]
		[switch]$Deferred
	)

	$obsidian = Get-ConfigSetting -Path 'Obsidian'
	$obsidianConfig = if ($obsidian -is [hashtable]) { $obsidian } else { @{} }
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
	$hasCurrentWorkspace = -not [string]::IsNullOrWhiteSpace($CurrentWorkspace)
	if (-not [string]::IsNullOrWhiteSpace($Workspace)) {
		$targetWorkspace = $Workspace.Trim()
		if ($savedWorkspaces.Count -gt 0 -and $targetWorkspace -notin $savedWorkspaces) {
			Write-LogWarning "Obsidian workspace [$targetWorkspace] is not saved in vault [$vault] (saved: $($savedWorkspaces -join ', ')) - attempting anyway."
		}
	}
	elseif ($hasCurrentWorkspace) {
		# Injected by Open-Workspace: match by name, never prompt inside a workspace open.
		if ($CurrentWorkspace.Trim() -in $savedWorkspaces) {
			$targetWorkspace = $CurrentWorkspace.Trim()
			Write-LogDebug " [Open-Obsidian] Same-named Obsidian workspace found for [$targetWorkspace]" -Style Success
		}
	}
	elseif (-not $Default -and $savedWorkspaces.Count -gt 0) {
		# Interactive call without a name: the menu, as every other opener with a selection does.
		$selection = Resolve-Selection -OptionList $savedWorkspaces `
			-MenuTitle "[Available Obsidian workspaces]" `
			-PromptMessage "Enter Obsidian workspace or press [Enter] to skip" `
			-AllowEmptyPromptResponse
		if ($selection -is [array]) { $selection = @($selection)[0] }
		if (-not [string]::IsNullOrWhiteSpace([string]$selection)) { $targetWorkspace = ([string]$selection).Trim() }
	}

	if (-not $targetWorkspace -and -not $isRunning -and -not [string]::IsNullOrWhiteSpace([string]$obsidianConfig.DefaultWorkspace)) {
		$targetWorkspace = ([string]$obsidianConfig.DefaultWorkspace).Trim()
	}

	# --- CLI ------------------------------------------------------------------------------------
	$cli = Get-ObsidianCliPath
	$cliMissingWarning = "Obsidian CLI not found - cannot load a workspace. Enable it in Obsidian under Settings > General > Advanced > Command line interface, then put its folder on PATH (AutoPathAdditions: `"%LOCALAPPDATA%\Programs\obsidian`") and open a new shell."

	# Deferring only moves the CLI work: the registered tail is Complete-ObsidianWorkspaceLoad,
	# which does exactly what the two branches below would have done, through the same checked
	# load. Open-Workspace runs it (Complete-DeferredActions) before the layout.
	$deferLoad = {
		param([string]$Name, [bool]$IsColdStart)
		Register-DeferredAction -Label "Obsidian workspace [$Name]" `
			-Parameters @{ CliPath = $cli; Vault = $vault; Name = $Name; ColdStart = $IsColdStart } `
			-Action {
			param([string]$CliPath, [string]$Vault, [string]$Name, [bool]$ColdStart)
			Complete-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name -ColdStart:$ColdStart
		}
		Write-LogDebug " [Open-Obsidian] Workspace [$Name] queued - loading after the remaining openers"
	}

	# --- Already running -------------------------------------------------------------------------
	if ($isRunning) {
		if (-not $targetWorkspace) {
			Write-LogWarning "Obsidian is already running!"
			return
		}
		if (-not $cli) {
			Write-LogWarning $cliMissingWarning
			return
		}
		if ($Deferred) {
			& $deferLoad $targetWorkspace $false
			return
		}
		Write-LogStep "Loading Obsidian workspace [$targetWorkspace]..."
		if ((Invoke-ObsidianWorkspaceLoad -CliPath $cli -Vault $vault -Name $targetWorkspace).Loaded) {
			Write-LogSuccess "Obsidian workspace [$targetWorkspace] loaded!"
		}
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
	# Deferred: Obsidian is launching, and the CLI cannot answer until it has finished starting.
	# That wait is what the remaining openers can absorb, so the record is redeemed later.
	if ($Deferred) {
		& $deferLoad $targetWorkspace $true
		Write-LogSuccess "Obsidian opened!"
		return
	}

	if (Wait-ObsidianCli -CliPath $cli -Vault $vault -TimeoutSeconds 10) {
		if ((Invoke-ObsidianWorkspaceLoad -CliPath $cli -Vault $vault -Name $targetWorkspace).Loaded) {
			Write-LogSuccess "Obsidian opened in workspace [$targetWorkspace]!"
		}
		else {
			Write-LogSuccess "Obsidian opened!"
		}
	}
	else {
		Write-LogWarning "Obsidian CLI did not answer within 10 seconds - workspace [$targetWorkspace] may not be loaded. Run [Open-Obsidian -Workspace $targetWorkspace] again once it is up."
	}
}
