function Bootstrap {
	<#
	.SYNOPSIS
		Orchestrates complete machine provisioning - installs software, configures Windows, creates symlinks.

	.DESCRIPTION
		Runs all provisioning steps in a fixed order. Requires administrator privileges and an active internet connection.
		Safe to re-run - all installation and configuration steps are idempotent.

		Every step is individually toggleable via BootstrapConfig.Steps (resolved once per run
		by Resolve-BootstrapSteps; -Skip/-Include override per invocation). Most steps also
		no-op on their own when their configuration section is empty, so an enabled step on
		the empty base config applies nothing. Opt-in steps that act the moment they run
		default off: MicrosoftActivationScripts, Win11Debloat, DeveloperMode, NuGetConfig,
		UpgradeAll, CoreAiRules, LockedStartLayout.

		Execution sequence:
		1. (WithInitialSetup only) Rename-Machine, Start-MicrosoftActivationScripts, Start-Win11Debloat
		2. Git identity guarantee (restored from GitConfig when unset), then Update-Repositories -
		   scope governed by BootstrapConfig.RepositoryUpdateScope ("None" skips)
		3. Execution policy, Developer Mode, power plan, power button actions
		4. System theme, locale, display language, keyboard layouts
		5. Nerd Font, PowerShell modules, special folder redirections
		6. WSL configuration (Steps.WSL; deprecated BootstrapConfig.WSLSetup still honored)
		7. WinGet, Scoop, and Chocolatey - install package managers then apps from CSVs
		8. Upgrade all packages, fork-defined personal steps (BootstrapConfig.PersonalSteps, optionally machine-gated), .NET EF CLI
		9. Environment variables, Conda environments, NuGet config, taskbar pins
		10. WSL environment initialization, symbolic links, CoreAiRules enforcement layer (opt-in via
		    Steps.CoreAiRules), WSL SSH setup (WSL steps use the same gate)
		11. Lock taskbar layout, restart Explorer, restart machine

		Logs are written via Start-Logging / Stop-Logging for the duration of the run.

	.PARAMETER RepoRoot
		Absolute path to the WinuX repository root. Defaults to the path stored in
		`$global:MachineSpecificPaths.Projects.Self.Root` if omitted.

	.PARAMETER WithInitialSetup
		Includes first-time-only steps: machine rename, Windows activation, and Win11Debloat.
		Omit this switch on subsequent runs.

	.PARAMETER Skip
		Step names forced off for this run, overriding BootstrapConfig.Steps. See
		Resolve-BootstrapSteps for the step list.

	.PARAMETER Include
		Step names forced on for this run, overriding BootstrapConfig.Steps.

	.EXAMPLE
		Bootstrap
		Re-provisions the machine - safe for repeated use after initial setup.

	.EXAMPLE
		Bootstrap -WithInitialSetup
		First-time provisioning on a new machine.

	.EXAMPLE
		Bootstrap -Skip UpgradeAll, WSL
		Re-provisions without upgrading packages or touching WSL.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$RepoRoot,

		[switch]$WithInitialSetup = $false,

		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
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
		$steps = Resolve-BootstrapSteps -Skip $Skip -Include $Include

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
			# Re-resolve: Initialize-Configuration may have just written the local override
			# whose BootstrapConfig.Steps should govern the rest of this run.
			$steps = Resolve-BootstrapSteps -Skip $Skip -Include $Include
			if ($steps.RenameMachine) { Rename-Machine } else { Write-LogWarning "Machine rename skipped (BootstrapConfig.Steps.RenameMachine)" }
			if ($steps.MicrosoftActivationScripts) { Start-MicrosoftActivationScripts } else { Write-LogWarning "Microsoft Activation Scripts skipped - opt in via BootstrapConfig.Steps.MicrosoftActivationScripts" }
			if ($steps.Win11Debloat) { Start-Win11Debloat } else { Write-LogWarning "Win11Debloat skipped - opt in via BootstrapConfig.Steps.Win11Debloat" }
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

		if ($steps.ExecutionPolicy) { Set-CustomExecutionPolicy } else { Write-LogWarning "Execution policy skipped (BootstrapConfig.Steps.ExecutionPolicy)" }
		if ($steps.DeveloperMode) { Enable-DeveloperMode } else { Write-LogWarning "Developer Mode skipped - opt in via BootstrapConfig.Steps.DeveloperMode" }

		if ($steps.PowerPlan) { Set-PowerPlan -Auto } else { Write-LogWarning "Power plan skipped (BootstrapConfig.Steps.PowerPlan)" }
		if ($steps.PowerButtonActions) { Set-PowerButtonActions -Auto } else { Write-LogWarning "Power button actions skipped (BootstrapConfig.Steps.PowerButtonActions)" }

		if ($steps.SystemTheme) { Set-SystemTheme -Auto -KeepTerminalOpen } else { Write-LogWarning "System theme skipped (BootstrapConfig.Steps.SystemTheme)" }

		if ($steps.Locale) { Set-Locale -Locale $global:Configuration.DefaultLocale } else { Write-LogWarning "Locale skipped (BootstrapConfig.Steps.Locale)" }
		if ($steps.DisplayLanguage) { Set-DisplayLanguage -Language $global:Configuration.DefaultDisplayLanguage } else { Write-LogWarning "Display language skipped (BootstrapConfig.Steps.DisplayLanguage)" }
		if ($steps.KeyboardLayouts) { Set-KeyboardLayouts -Layout $global:Configuration.DefaultKeyboardLayoutSet } else { Write-LogWarning "Keyboard layouts skipped (BootstrapConfig.Steps.KeyboardLayouts)" }
		Display-SystemLanguageSettings

		if ($steps.NerdFont) { Configure-NerdFont -FontName $global:Configuration.DefaultNerdFont } else { Write-LogWarning "Nerd Font skipped (BootstrapConfig.Steps.NerdFont)" }
		if ($steps.PowerShellModules) { Install-PowerShellModules } else { Write-LogWarning "PowerShell modules skipped (BootstrapConfig.Steps.PowerShellModules)" }

		if ($steps.SpecialFolders) { Set-SpecialFolders } else { Write-LogWarning "Special folders skipped (BootstrapConfig.Steps.SpecialFolders)" }

		Restart-Explorer

		# WSL provisioning is config-driven via Steps.WSL (deprecated BootstrapConfig.WSLSetup
		# is honored when Steps carries no WSL entry - see Resolve-BootstrapSteps). Nothing else
		# in Bootstrap depends on WSL, so minimal profiles (fresh test VMs) skip the Ubuntu
		# download, the interactive first-launch account setup, and the reboot it needs.
		if ($steps.WSL) {
			Configure-WSL
		}
		else {
			Write-LogWarning "WSL setup disabled for machine type [$global:MachineType] (BootstrapConfig.Steps.WSL) - skipping Configure-WSL, Initialize-WSLEnvironment, Configure-WSLSSH"
		}

		# Which package managers this machine actually uses: listed in PackageManagers AND holding at
		# least one app for this machine type (see Resolve-PackageManagers, which reports the ones it
		# drops). A manager with nothing to install is never installed just to sit there managing
		# nothing - the base Scoop and Chocolatey lists ship empty, so a vanilla bootstrap installs
		# WinGet alone. The step toggles remain the per-invocation override on top of that.
		$managers = @(Resolve-PackageManagers)

		if ($steps.WinGetApps -and $managers -contains "WinGet") {
			Install-WinGetPackageManager
			Install-WinGetApps
		}
		elseif (-not $steps.WinGetApps) {
			Write-LogWarning "WinGet apps skipped (BootstrapConfig.Steps.WinGetApps)"
		}

		if ($steps.ScoopApps -and $managers -contains "Scoop") {
			Install-ScoopPackageManager
			Install-ScoopApps
		}
		elseif (-not $steps.ScoopApps) {
			Write-LogWarning "Scoop apps skipped (BootstrapConfig.Steps.ScoopApps)"
		}

		if ($steps.ChocolateyApps -and $managers -contains "Chocolatey") {
			Install-ChocolateyPackageManager
			Install-ChocolateyApps
		}
		elseif (-not $steps.ChocolateyApps) {
			Write-LogWarning "Chocolatey apps skipped (BootstrapConfig.Steps.ChocolateyApps)"
		}

		# The managers resolved above are handed over rather than resolved a second time: same answer,
		# one set of skip warnings per run, and the upgrade provably covers exactly what was installed.
		if ($steps.UpgradeAll -and $managers.Count -gt 0) {
			Upgrade-All -PackageManager $managers
		}
		elseif (-not $steps.UpgradeAll) {
			Write-LogWarning "Package upgrade skipped - opt in via BootstrapConfig.Steps.UpgradeAll"
		}

		# Fork-defined optional install steps (BootstrapConfig.PersonalSteps) - the base config
		# ships an empty list, so a vanilla WinuX bootstrap runs nothing here. Entries are plain
		# function names or machine-gated hashtables; see Invoke-PersonalSteps.
		Invoke-PersonalSteps

		if ($steps.DotnetEf) { Install-DotnetEf } else { Write-LogWarning "dotnet-ef skipped (BootstrapConfig.Steps.DotnetEf)" }

		if ($steps.EnvironmentVariables) { Set-EnvironmentVariables -Auto } else { Write-LogWarning "Environment variables skipped (BootstrapConfig.Steps.EnvironmentVariables)" }

		if ($steps.CondaEnvironments) { Create-CondaEnvironments } else { Write-LogWarning "Conda environments skipped (BootstrapConfig.Steps.CondaEnvironments)" }
		# PostgreSQL is provisioned via the Docker compose library, so password setup is redundant.
		#Configure-PostgreSqlPasswords
		if ($steps.NuGetConfig) { Configure-NuGetConfig } else { Write-LogWarning "NuGet config skipped - opt in via BootstrapConfig.Steps.NuGetConfig" }

		if ($steps.Taskbar) { Configure-Taskbar -FromBootstrap } else { Write-LogWarning "Taskbar pins skipped (BootstrapConfig.Steps.Taskbar)" }

		# Config-driven (TaskbarSettings); no-op unless the fork opts in. Applies the
		# Settings > Personalisation > Taskbar page, auto-hide included.
		Set-TaskbarSettings

		# Config-driven (VisualEffects); no-op unless the fork opts in. Applies the
		# Performance Options visual-effects profile (registry + SystemParametersInfo).
		Set-VisualEffects

		if ($steps.WSL) {
			Initialize-WSLEnvironment
		}

		if ($steps.SymbolicLinks) { SymbolicLinkMaker } else { Write-LogWarning "Symbolic links skipped (BootstrapConfig.Steps.SymbolicLinks)" }

		# Machine-global AI agent policy (docs/ai/coreairules.md) - never imposed by a vanilla
		# bootstrap; the instruction/enforcement symlinks it complements are opt-in
		# SymbolicLinks entries handled by SymbolicLinkMaker above.
		if ($steps.CoreAiRules) { Deploy-CoreAiRules } else { Write-LogWarning "CoreAiRules skipped - opt in via BootstrapConfig.Steps.CoreAiRules" }

		if ($steps.WSL) {
			Configure-WSLSSH
		}

		if ($steps.LockedStartLayout) {
			try {
				$explorerPolicyRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
				Set-ItemProperty -Path $explorerPolicyRegistryPath -Name "LockedStartLayout" -Value 1 -Type DWord -Force
				Write-LogSuccess "Taskbar layout locked to prevent future modifications!"
			}
			catch {
				Write-LogWarning "Could not lock taskbar layout => $($_.Exception.Message)"
			}
		}
		else {
			Write-LogWarning "Taskbar layout lock skipped - opt in via BootstrapConfig.Steps.LockedStartLayout"
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
