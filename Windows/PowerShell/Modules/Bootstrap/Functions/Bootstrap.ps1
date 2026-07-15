function Bootstrap {
	<#
	.SYNOPSIS
		Orchestrates complete machine provisioning - installs software, configures Windows, creates symlinks.

	.DESCRIPTION
		Runs all provisioning steps in a fixed order. Requires administrator privileges and an active internet connection.
		Safe to re-run - all installation and configuration steps are idempotent.

		Execution sequence:
		1. (WithInitialSetup only) Rename-Machine, Start-MicrosoftActivationScripts, Start-Win11Debloat
		2. Git identity guarantee (restored from GitConfig when unset), then Update-Repositories -
		   pulls latest WinuX and all configured repositories
		3. Execution policy, Developer Mode, power plan, power button actions
		4. System theme, locale, display language, keyboard layouts
		5. Nerd Font, PowerShell modules, special folder redirections
		6. WSL configuration (config-gated per machine type via BootstrapConfig.WSLSetup)
		7. WinGet, Scoop, and Chocolatey - install package managers then apps from CSVs
		8. Upgrade all packages, fork-defined personal steps (BootstrapConfig.PersonalSteps, optionally machine-gated), .NET EF CLI
		9. Environment variables, Conda environments, NuGet config, taskbar pins
		10. WSL environment initialization, symbolic links, WSL SSH setup (WSL steps use the same gate)
		11. Lock taskbar layout, restart Explorer, restart machine

		Logs are written via Start-Logging / Stop-Logging for the duration of the run.

	.PARAMETER RepoRoot
		Absolute path to the WinuX repository root. Defaults to the path stored in
		`$global:MachineSpecificPaths.Projects.Self.Root` if omitted.

	.PARAMETER WithInitialSetup
		Includes first-time-only steps: machine rename, Windows activation, and Win11Debloat.
		Omit this switch on subsequent runs.

	.EXAMPLE
		Bootstrap
		Re-provisions the machine - safe for repeated use after initial setup.

	.EXAMPLE
		Bootstrap -WithInitialSetup
		First-time provisioning on a new machine.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$RepoRoot,

		[switch]$WithInitialSetup = $false
	)

	try {

		# Suppress progress bars to prevent console hanging
		$ProgressPreference = 'SilentlyContinue'
		# Suppress all confirmation prompts for fully automated execution
		$ConfirmPreference = 'None'

		Test-AdminPrivileges

		if (-not $global:startTime) {
			Start-Logging
		}

		if (-not $RepoRoot) {
			$RepoRoot = $global:MachineSpecificPaths.Projects.Self.Root
		}

		Load-PathConfiguration -RepoRoot $RepoRoot | Out-Null

		if ($WithInitialSetup) {
			Write-LogTitle "Initial Boostrap Started"
			# Capture personal identity/paths into Configuration.local.psd1 (from the install
			# one-liner's WINUX_* env vars, or prompted on a fresh machine), then reload so the
			# override is merged over the generic base for the rest of the run.
			# The {Dev} root is the folder that CONTAINS this repo clone (its parent), so {Dev}\<project>
			# siblings and the self-located {RepoRoot} stay consistent with wherever the repo was
			# actually cloned - independent of WINUX_DEV_PATH / WINUX_INSTALL_DIR / the clone folder name.
			$DevRoot = Split-Path -Path $RepoRoot -Parent
			# Record the machine type the engine ACTUALLY resolved above (Load-PathConfiguration set
			# $global:MachineType from HostnameToMachineType / DefaultMachineType). Without passing it,
			# Initialize-Configuration falls back to its own "Test" default and writes an override that
			# disagrees with the detected type: the BasePaths override lands under the wrong type, and the
			# next run (fresh shell, override now present) re-detects to that wrong type and silently
			# reclassifies the machine. Fall back to the config default if somehow unset.
			$detectedMachineType = if ($global:MachineType) { $global:MachineType } else { $global:Configuration.DefaultMachineType }
			Initialize-Configuration -GitName $env:WINUX_GIT_NAME -GitEmail $env:WINUX_GIT_EMAIL -DevPath $DevRoot -MachineType $detectedMachineType
			Load-PathConfiguration -RepoRoot $RepoRoot | Out-Null
			Rename-Machine
			Start-MicrosoftActivationScripts
			Start-Win11Debloat
		}
		else {
			Write-LogTitle "Bootstrap Started"
		}

		# Guarantee a global git identity before any repository operation. Update-Repositories
		# stashes local changes, and stashing creates commit objects that git refuses without an
		# identity ("fatal: empty ident name"). The identity the user entered at installation
		# lives in the merged configuration (GitConfig - captured into Configuration.local.psd1
		# by Initialize-Configuration on the first run, committed in a personal fork), so re-runs
		# and fresh shells can always restore it from there. No-op when the identity is already
		# set or the configuration carries none (Update-Repositories stashes with an ephemeral
		# identity as the last line of defense).
		$globalGitName = git config --global user.name 2>$null
		$globalGitEmail = git config --global user.email 2>$null
		if ([string]::IsNullOrWhiteSpace($globalGitName) -and -not [string]::IsNullOrWhiteSpace($global:Configuration.GitConfig.UserName)) {
			git config --global user.name "$($global:Configuration.GitConfig.UserName)"
			Write-LogWarning "Global git user.name was not set - restored from configuration => [$($global:Configuration.GitConfig.UserName)]"
		}
		if ([string]::IsNullOrWhiteSpace($globalGitEmail) -and -not [string]::IsNullOrWhiteSpace($global:Configuration.GitConfig.UserEmail)) {
			git config --global user.email "$($global:Configuration.GitConfig.UserEmail)"
			Write-LogWarning "Global git user.email was not set - restored from configuration => [$($global:Configuration.GitConfig.UserEmail)]"
		}

		# Clone/update the repositories this machine defines. Scope is config-driven via
		# BootstrapConfig.RepositoryUpdateScope (machine type -> "Private" | "Work" | "All" | "None",
		# with a "Default" fallback). Absent => "All", so a fork pulls every repo it defines.
		# Update-Repositories is idempotent (clones if missing, fast-forwards if present).
		$scopeMap = $global:Configuration.BootstrapConfig.RepositoryUpdateScope
		$updateScope = if ($scopeMap -and $scopeMap[$global:MachineType]) {
			$scopeMap[$global:MachineType]
		}
		elseif ($scopeMap -and $scopeMap.Default) {
			$scopeMap.Default
		}
		else {
			"All"
		}
		switch ($updateScope) {
			"None" { Write-LogWarning "Repository update skipped (RepositoryUpdateScope => None)" }
			"Private" { Update-Repositories -Private }
			"Work" { Update-Repositories -Work }
			default { Update-Repositories -All }
		}

		Set-CustomExecutionPolicy
		Enable-DeveloperMode

		Set-PowerPlan -Auto
		Set-PowerButtonActions -Auto

		Set-SystemTheme -Auto -KeepTerminalOpen

		Set-Locale -Locale $global:Configuration.DefaultLocale
		Set-DisplayLanguage -Language $global:Configuration.DefaultDisplayLanguage
		Set-KeyboardLayouts -Layout $global:Configuration.DefaultKeyboardLayoutSet
		Display-SystemLanguageSettings

		Configure-NerdFont -FontName $global:Configuration.DefaultNerdFont
		Install-PowerShellModules

		Set-SpecialFolders

		Restart-Explorer

		# WSL provisioning is config-driven via BootstrapConfig.WSLSetup (machine type ->
		# $true/$false, "Default" fallback; absent => $true). Nothing else in Bootstrap depends
		# on WSL, so minimal profiles (fresh test VMs) skip the Ubuntu download, the interactive
		# first-launch account setup, and the reboot it needs. $false is a real value here, so
		# resolve with explicit $null checks - truthiness (the RepositoryUpdateScope pattern)
		# would misread it, and indexing with a $null machine type key errors.
		$wslMap = $global:Configuration.BootstrapConfig.WSLSetup
		$wslSetupEnabled = if ($wslMap -and $global:MachineType -and $null -ne $wslMap[$global:MachineType]) {
			[bool]$wslMap[$global:MachineType]
		}
		elseif ($wslMap -and $null -ne $wslMap.Default) {
			[bool]$wslMap.Default
		}
		else {
			$true
		}

		if ($wslSetupEnabled) {
			Configure-WSL
		}
		else {
			Write-LogWarning "WSL setup disabled for machine type [$global:MachineType] (BootstrapConfig.WSLSetup) - skipping Configure-WSL, Initialize-WSLEnvironment, Configure-WSLSSH"
		}

		Install-WinGetPackageManager
		Install-WinGetApps

		Install-ScoopPackageManager
		Install-ScoopApps

		Install-ChocolateyPackageManager
		Install-ChocolateyApps

		Upgrade-All

		# Fork-defined optional install steps (BootstrapConfig.PersonalSteps) - the base config
		# ships an empty list, so a vanilla WinuX bootstrap runs nothing here. Forks name their
		# personal tools in Configuration.local.psd1; each entry must be an exported function.
		# An entry is either a plain function name (runs on every machine type) or a hashtable
		# @{ Function = "Name"; Machine = "PC/Laptop" } gated per machine type exactly like the
		# app CSVs' Machine column (tokens validated by Test-MachineTypeScope).
		foreach ($personalStep in @($global:Configuration.BootstrapConfig.PersonalSteps)) {
			if (-not $personalStep) { continue }

			$stepName = if ($personalStep -is [System.Collections.IDictionary]) { "$($personalStep['Function'])" } else { "$personalStep" }
			$stepScope = if ($personalStep -is [System.Collections.IDictionary] -and $null -ne $personalStep['Machine']) { "$($personalStep['Machine'])" } else { "All" }

			if (-not $stepName) {
				Write-LogWarning "Personal step entry has no Function name - skipping"
				continue
			}

			if (-not (Test-MachineTypeScope -Scope $stepScope -Context "PersonalSteps [$stepName]")) {
				Write-LogDebug "Personal step [$stepName] skipped (machine scope => [$stepScope])"
				continue
			}

			if (Get-Command $stepName -ErrorAction SilentlyContinue) {
				& $stepName
			}
			else {
				Write-LogWarning "Personal step [$stepName] not found - skipping"
			}
		}

		Install-DotnetEf

		Set-EnvironmentVariables -Auto

		Create-CondaEnvironments
		# PostgreSQL is provisioned via the Docker compose library, so password setup is redundant.
		#Configure-PostgreSqlPasswords
		Configure-NuGetConfig

		Configure-Taskbar -FromBootstrap

		# Config-driven (TaskbarAutoHide); no-op unless the fork opts in. FancyZones zone
		# geometry is work-area based and correct either way - this is UX parity only.
		Set-TaskbarAutoHide -Auto

		# Config-driven (VisualEffects); no-op unless the fork opts in. Applies the
		# Performance Options visual-effects profile (registry + SystemParametersInfo).
		Set-VisualEffects

		if ($wslSetupEnabled) {
			Initialize-WSLEnvironment
		}

		SymbolicLinkMaker

		if ($wslSetupEnabled) {
			Configure-WSLSSH
		}

		try {
			$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
			Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 1 -Type DWord -Force
			Write-LogSuccess "Taskbar layout locked to prevent future modifications!"
		}
		catch {
			Write-LogWarning "Could not lock taskbar layout => $($_.Exception.Message)"
		}

		Restart-Explorer

		Write-LogSuccess "Bootstrap completed"

		Restart-Machine
	}
	catch {
		Write-LogError "Bootstrap failed => $($_.Exception.Message)" -Exception $_
		if ($_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
			Write-Host -ForegroundColor DarkGray ("   at {0}:{1}  =>  {2}" -f (Split-Path -Leaf $_.InvocationInfo.ScriptName), $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim())
		}
		throw
	}
	finally {
		if ($global:startTime) {
			Stop-Logging
		}
	}
}
