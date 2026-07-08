function Start-Win11Debloat {
	<#
	.SYNOPSIS
		Runs the Win11Debloat script to remove bloatware and apply system tweaks.

	.DESCRIPTION
		Runs the vendored Win11Debloat PowerShell script from the local repository path
		configured in `BootstrapConfig.LocalScripts.Win11Debloat`.

		The vendored release reads saved settings from `<script>\Config\LastUsedSettings.json`
		(its `$script:SavedSettingsFilePath`). To keep that file version-controlled while letting
		Win11Debloat read and write it natively, this links `Config\LastUsedSettings.json` to the
		repo's `Windows\Win11Debloat\LastUsedSettings.json`. The custom app selection is stored
		inside that same file (the `Apps` setting), so no separate CustomAppsList file is managed.

		When a non-empty saved-settings file is present, offers to apply it via `-RunSavedSettings`;
		otherwise shows the interactive Win11Debloat menu.

		Only called automatically during `Bootstrap -WithInitialSetup` (first-time provisioning).

	.PARAMETER Selection
		Pre-selects one of the Win11Debloat menu options by name, bypassing the interactive menu.
		Valid values are determined by the Win11Debloat script itself.

	.EXAMPLE
		Start-Win11Debloat
		Runs Win11Debloat with saved settings if available, or shows the interactive menu.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Selection
	)

	Write-LogTitle "Win11Debloat"
	Test-AdminPrivileges

	Try {
		$repoRoot = $global:MachineSpecificPaths.Projects.Self.Root
		$win11DebloatScriptPath = $global:Configuration.BootstrapConfig.LocalScripts.Win11Debloat

		if (-not [string]::IsNullOrWhiteSpace($win11DebloatScriptPath) -and $win11DebloatScriptPath.Contains("{RepoRoot}")) {
			$win11DebloatScriptPath = $win11DebloatScriptPath.Replace("{RepoRoot}", $repoRoot)
		}

		if (-not $win11DebloatScriptPath) {
			$win11DebloatScriptPath = Join-Path $repoRoot "Windows\Win11Debloat\vendor\Win11Debloat.ps1"
		}

		if (-not (Test-Path -Path $win11DebloatScriptPath)) {
			Write-LogError "Win11Debloat script not found at: $win11DebloatScriptPath"
			Write-LogWarning "Download a release into Windows\Win11Debloat\vendor before running this step."
			return
		}

		# Win11Debloat reads saved settings from <script>\Config\LastUsedSettings.json (its
		# $script:SavedSettingsFilePath). Keep the source of truth version-controlled in the repo and
		# expose it to the vendored script through a symlink, so the script reads and writes it natively.
		# The current release embeds the custom app selection inside this file (the "Apps" setting); it
		# no longer reads a separate CustomAppsList file, so only LastUsedSettings.json is managed here.
		$win11DebloatConfigDir = Join-Path (Split-Path -Path $win11DebloatScriptPath -Parent) "Config"
		$savedSettingsTarget = Join-Path $repoRoot "Windows\Win11Debloat\LastUsedSettings.json"
		$savedSettingsLink = Join-Path $win11DebloatConfigDir "LastUsedSettings.json"

		# Saved settings are only usable when the repo file exists and is non-empty. This mirrors
		# Win11Debloat, which deletes LastUsedSettings.json when it is blank.
		$hasSavedSettings = $false
		if (Test-Path -LiteralPath $savedSettingsTarget) {
			$savedSettingsContent = Get-Content -LiteralPath $savedSettingsTarget -Raw -ErrorAction SilentlyContinue
			$hasSavedSettings = -not [string]::IsNullOrWhiteSpace($savedSettingsContent)
		}

		# Link the vendored Config file to the repo's source of truth. Done before the menu so a GUI
		# "Debloat" run also writes any saved settings straight back into the repo. Recreated on every
		# run, which self-heals after Update-Win11DebloatVendor wipes and re-extracts the vendor folder.
		if ($hasSavedSettings) {
			if (-not (Test-Path -Path $win11DebloatConfigDir)) {
				New-Item -ItemType Directory -Path $win11DebloatConfigDir -Force | Out-Null
			}

			$existingLink = Get-Item -LiteralPath $savedSettingsLink -Force -ErrorAction SilentlyContinue
			$existingTarget = if ($existingLink -and $existingLink.Target) { @($existingLink.Target)[0] } else { $null }
			$isExpectedSymlink = $existingLink -and $existingLink.LinkType -eq 'SymbolicLink' -and $existingTarget -eq $savedSettingsTarget

			if (-not $isExpectedSymlink) {
				if (Test-Path -LiteralPath $savedSettingsLink) {
					Remove-Item -LiteralPath $savedSettingsLink -Force
				}

				New-Item -ItemType SymbolicLink -Path $savedSettingsLink -Target $savedSettingsTarget -Force | Out-Null
				Write-LogSuccess "Linked Win11Debloat saved settings to the repo's LastUsedSettings.json"
			}
		}

		$optionList = if ($hasSavedSettings) {
			@("Use saved settings", "Debloat", "Don't debloat")
		}
		else {
			@("Debloat", "Don't debloat")
		}

		$resolveParams = @{
			InputObject              = $Selection
			OptionList               = $optionList
			HideMenuTitle            = $true
			PromptMessage            = "Do you want to debloat the system? (Press Enter for default => Don't debloat)"
			AllowEmptyPromptResponse = $true
		}

		$resolvedSelection = Resolve-Selection @resolveParams

		if ($null -eq $resolvedSelection -or $resolvedSelection -eq "Don't debloat") {
			Write-LogWarning "Debloating skipped!"
			return
		}
		elseif ($resolvedSelection -eq "Use saved settings") {
			Write-LogStep "=> Running Win11Debloat with saved settings..."
			& $win11DebloatScriptPath -RunSavedSettings -Silent
			Write-LogSuccess "Debloating with saved settings completed!"
		}
		elseif ($resolvedSelection -eq "Debloat") {
			Write-LogStep "=> Running Win11Debloat ..."
			& $win11DebloatScriptPath
			Write-LogSuccess "Debloating completed!"
		}
	}
	Catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
