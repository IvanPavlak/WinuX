function Set-SystemTheme {
	<#
	.SYNOPSIS
		Sets the Windows system theme (Dark or Light).

	.DESCRIPTION
		Modifies registry entries to apply dark or light theme across the system.
		Restarts Explorer before wallpaper updates so `Set-Wallpaper` can apply
		desktop backgrounds reliably through the `IDesktopWallpaper` COM interface.
		This order is required; restarting Explorer after wallpaper changes can cause
		Windows to reload stale wallpaper cache data and revert the desktop image.

		Also calls `Set-LockScreenWallpaper` to update the lock screen background
		to match the selected theme.

		With `-Auto`, reads the theme for the current machine type from Configuration.psd1
		`Themes[MachineType]` and applies it automatically.

		Requires administrator privileges.

	.PARAMETER Theme
		Theme to apply: "Dark" or "Light". Omit with `-Auto` to read from config.

	.PARAMETER Auto
		Reads the theme for the machine type from Configuration.psd1.

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
	#>
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Dark", "Light")]
		[string]$Theme,

		[Parameter(Mandatory = $false)]
		[switch]$Auto,

		[Parameter(Mandatory = $false)]
		[switch]$KeepTerminalOpen
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting System Theme"

	try {
		Write-LogDebug " Verbose logging enabled for Set-SystemTheme" -Style Step
		Write-LogDebug " Parameters: Auto=$Auto, Theme=$Theme, KeepTerminalOpen=$KeepTerminalOpen" -Style Step

		$shouldCloseCurrentTerminal = (-not $KeepTerminalOpen) -and (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION))

		$MachineType = DetermineMachineType

		Write-LogDebug " MachineType detected: $MachineType" -Style Step

		if ($Auto) {
			Write-LogTitle "Setting Theme for $($MachineType)"

			$Theme = $Configuration.Themes[$MachineType]

			Write-LogDebug " Theme from configuration: $Theme" -Style Step

			if (-not $Theme) {
				Write-LogWarning "Unknown Machine Type"
				Write-LogSuccess "Defaulting to [Dark] theme!"
				$Theme = "Dark"
			}
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

			# Restart Explorer first; wallpaper COM updates are not reliable if Explorer is restarted afterward.
			Restart-Explorer

			Set-Wallpaper -Auto -Theme $Theme
			Set-LockScreenWallpaper -Theme $Theme
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

			Refresh-BrowserTabs
			# Restart Explorer first; wallpaper COM updates are not reliable if Explorer is restarted afterward.
			Restart-Explorer

			Set-Wallpaper -Auto -Theme $Theme
			Set-LockScreenWallpaper -Theme $Theme

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
