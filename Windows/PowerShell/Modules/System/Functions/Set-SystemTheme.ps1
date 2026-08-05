function Set-SystemTheme {
	<#
	.SYNOPSIS
		Sets the Windows system theme (Dark or Light).

	.DESCRIPTION
		Modifies registry entries to apply dark or light theme across the system,
		then runs a configurable sequence of follow-up steps:
		- RefreshBrowserTabs     : reloads open browser tabs (Refresh-BrowserTabs, off
		                           by default; only runs when the theme actually changed)
		- RestartExplorer        : restarts Windows Explorer (off by default)
		- SetWallpaper           : applies the matching desktop wallpaper (Set-Wallpaper -Auto)
		- SetLockScreenWallpaper : applies the matching lock screen image

		Explorer is restarted before the wallpaper updates so `Set-Wallpaper` can apply
		desktop backgrounds reliably through the `IDesktopWallpaper` COM interface.
		This order is required; restarting Explorer after wallpaper changes can cause
		Windows to reload stale wallpaper cache data and revert the desktop image.

		Every step can be enabled or disabled persistently via the SystemTheme.Steps
		section of Configuration.psd1 / Configuration.local.psd1. Each entry is either a
		plain boolean or a per-machine-type hashtable with a Default fallback, e.g.:
		  SystemTheme = @{ Steps = @{ RestartExplorer = @{ Default = $false; PC = $true } } }
		Steps missing from config use their built-in defaults (both wallpaper steps on,
		RefreshBrowserTabs and RestartExplorer off).

		Per invocation, -Skip forces steps off and -Include forces them on, overriding
		config in both directions. -Skip wins when a step appears in both.

		With `-Auto`, reads the theme for the current machine type from Configuration.psd1
		`Themes[MachineType]` and applies it automatically. When `Themes` is not configured
		(the empty base config) or carries no entry for the machine type, `-Auto` leaves the
		system theme as-is - opting in happens via Configuration.local.psd1.

		Requires administrator privileges.

	.PARAMETER Theme
		Theme to apply: "Dark" or "Light". Omit with `-Auto` to read from config.

	.PARAMETER Auto
		Reads the theme for the machine type from Configuration.psd1.

	.PARAMETER Skip
		Step names to skip for this invocation, overriding config. Valid names:
		RefreshBrowserTabs, RestartExplorer, SetWallpaper, SetLockScreenWallpaper.
		Wins over -Include when a step appears in both.

	.PARAMETER Include
		Step names to run for this invocation even if config disables them.
		Same valid names as -Skip.

	.PARAMETER KeepTerminalOpen
		Skips the default delayed close of the current Windows Terminal tab after
		the theme update succeeds. Use this for longer-running admin workflows such
		as `Bootstrap` that need to continue after the theme change completes.

	.EXAMPLE
		Set-SystemTheme -Auto
		Applies the configured theme for the current machine type.

	.EXAMPLE
		Set-SystemTheme -Theme "Dark"
		Forces dark theme regardless of configuration.

	.EXAMPLE
		Set-SystemTheme -Auto -Include RestartExplorer
		Applies the configured theme and restarts Explorer even though config disables it.

	.EXAMPLE
		Set-SystemTheme -Theme "Dark" -Skip SetLockScreenWallpaper
		Applies dark theme and the desktop wallpaper, leaving the lock screen alone.
	#>
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Dark", "Light")]
		[string]$Theme,

		[Parameter(Mandatory = $false)]
		[switch]$Auto,

		[Parameter(Mandatory = $false)]
		[ValidateSet("RefreshBrowserTabs", "RestartExplorer", "SetWallpaper", "SetLockScreenWallpaper")]
		[string[]]$Skip,

		[Parameter(Mandatory = $false)]
		[ValidateSet("RefreshBrowserTabs", "RestartExplorer", "SetWallpaper", "SetLockScreenWallpaper")]
		[string[]]$Include,

		[Parameter(Mandatory = $false)]
		[switch]$KeepTerminalOpen
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting System Theme"

	try {
		Write-LogDebug " Verbose logging enabled for Set-SystemTheme" -Style Step
		Write-LogDebug " Parameters: Auto=$Auto, Theme=$Theme, KeepTerminalOpen=$KeepTerminalOpen" -Style Step

		$shouldCloseCurrentTerminal = (-not $KeepTerminalOpen) -and (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION))

		$stepStates = Resolve-SystemThemeSteps -Skip $Skip -Include $Include

		if (Test-LogVerbose) {
			$disabledSteps = @($stepStates.Keys | Where-Object { -not $stepStates[$_] })
			if ($disabledSteps) {
				Write-LogDebug " Skipping steps => [$($disabledSteps -join ', ')]" -Style Step
			}
		}

		$MachineType = DetermineMachineType

		Write-LogDebug " MachineType detected: $MachineType" -Style Step

		if ($Auto) {
			Write-LogTitle "Setting Theme for $($MachineType)"

			# Empty-by-default contract: an unconfigured Themes section means the user
			# never opted into theme management, so -Auto leaves the system untouched.
			if (-not (Confirm-ConfigValue $Configuration.Themes "Themes not configured - leaving system theme as-is!")) {
				return
			}

			# Check a local first: $Theme carries ValidateSet, so assigning a null
			# config lookup to it would throw before any guard could run.
			$configuredTheme = $Configuration.Themes[$MachineType]

			Write-LogDebug " Theme from configuration: $configuredTheme" -Style Step

			if (-not (Confirm-ConfigValue $configuredTheme "No theme configured for [$MachineType] (Themes) - leaving system theme as-is!")) {
				return
			}

			$Theme = $configuredTheme
		}
		elseif (-not $Theme) {
			$Theme = "Dark"
			Write-LogTitle "Setting Theme to default => $($Theme)"
		}

		$keyPersonalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
		$themeValue = if ($Theme -eq "Light") { 1 } else { 0 }

		Write-LogDebug " Registry key: $keyPersonalize" -Style Step
		Write-LogDebug " Theme value to set: $themeValue (0=Dark, 1=Light)" -Style Step

		$currentThemeValue = (Get-ItemProperty -Path $keyPersonalize).AppsUseLightTheme

		Write-LogDebug " Current AppsUseLightTheme value: $currentThemeValue" -Style Step

		$isThemeAlreadyConfigured = (($currentThemeValue -eq 1 -and $Theme -eq 'Light') -or ($currentThemeValue -eq 0 -and $Theme -eq 'Dark'))

		if ($isThemeAlreadyConfigured) {
			Write-LogWarning "Theme already configured to [$($Theme)]!"
		}
		else {
			$properties = @(
				@{ Name = "AppsUseLightTheme"; Value = $themeValue }
				@{ Name = "ColorPrevalence"; Value = $themeValue }
				@{ Name = "SystemUsesLightTheme"; Value = $themeValue }
			)

			if (Test-LogVerbose) {
				Write-LogDebug "Setting registry properties:" -Style Step
				foreach ($prop in $properties) {
					Write-LogDebug "$($prop.Name) = $($prop.Value)" -Style Step
				}
			}

			foreach ($prop in $properties) {
				Set-ItemProperty -Path $keyPersonalize -Name $prop.Name -Value $prop.Value
			}

			Write-LogSuccess "Theme configured to [$($Theme)]"

			# Only worth doing when the theme actually changed - tabs that already
			# render the requested theme have nothing to pick up from a reload.
			if ($stepStates.RefreshBrowserTabs) {
				Refresh-BrowserTabs
			}
		}

		# Restart Explorer first; wallpaper COM updates are not reliable if Explorer is restarted afterward.
		if ($stepStates.RestartExplorer) {
			Restart-Explorer
		}

		if ($stepStates.SetWallpaper) {
			Set-Wallpaper -Auto -Theme $Theme
		}

		if ($stepStates.SetLockScreenWallpaper) {
			Set-LockScreenWallpaper -Theme $Theme
		}

		if (-not $isThemeAlreadyConfigured) {
			Write-LogWarning "Changes for some applications and/or windows may not take effect until they are reloaded or restarted!"
		}

		if ($shouldCloseCurrentTerminal) {
			Write-LogDebug " Current Windows Terminal tab will close in 5 second(s)" -Style Step

			Terminate-WindowsTerminalTabs -OnlyCurrent -CloseWaitSeconds 5
		}
	}
	catch {
		Write-LogError "Error detected: [$($_.Exception.Message)]"

		ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning theme setup!"
	}
}
