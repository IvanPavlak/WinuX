function Set-LockScreenWallpaper {
	<#
	.SYNOPSIS
		Sets the Windows lock screen background image.

	.DESCRIPTION
		Applies a wallpaper image to the lock screen using the Windows native registry settings.
		Reads wallpaper paths from `WallpaperLightSettings` or `WallpaperDarkSettings` in
		Configuration.psd1 based on the requested theme.
		With `-Auto`, detects the current system theme and sets the matching wallpaper.
		Requires administrator privileges.

	.PARAMETER Theme
		Theme to use: "Light", "Dark", or "Auto" (detect from system settings). Defaults to "Auto".

	.EXAMPLE
		Set-LockScreenWallpaper
		Sets the lock screen wallpaper matching the current system theme.

	.EXAMPLE
		Set-LockScreenWallpaper -Theme "Dark"
		Sets the dark theme lock screen wallpaper.
	#>
	param(
		[Parameter(Mandatory = $false)]
		[ValidateSet("Light", "Dark", "Auto")]
		[string]$Theme = "Auto"
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting Lock Screen Wallpaper"

	try {
		Write-LogDebug " Parameters: Theme=$Theme" -Style Step

		$WallpaperDarkSettings = $Configuration.WallpaperDarkSettings
		$WallpaperLightSettings = $Configuration.WallpaperLightSettings

		$targetTheme = $Theme
		if ($targetTheme -eq 'Auto') {
			try {
				$isLightTheme = (Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop)
				$targetTheme = if ($isLightTheme -eq 1) { "Light" } else { "Dark" }
				Write-LogDebug " Detected theme from registry: $targetTheme (AppsUseLightTheme=$isLightTheme)" -Style Step
			}
			catch {
				Write-LogWarning "Could not detect system theme. Defaulting to [Dark]"
				$targetTheme = "Dark"
				Write-LogDebug " Theme detection error: $_" -Style Step
			}
		}

		$WallpaperSettings = if ($targetTheme -eq 'Light') { $WallpaperLightSettings } else { $WallpaperDarkSettings }
		Write-LogStep " Using [$targetTheme] theme lock screen wallpaper settings!"

		$MachineType = DetermineMachineType
		Write-LogDebug " MachineType: $MachineType" -Style Step

		$wallpaperSetting = $WallpaperSettings[$MachineType]
		if (-not $wallpaperSetting) {
			Write-LogWarning " No specific wallpaper found for [$MachineType]"
			Write-LogWarning "Using default"
			$wallpaperSetting = $WallpaperSettings["Default"]
		}

		# For multi-monitor configs use the first monitor's wallpaper; for single configs use the File key directly
		if ($wallpaperSetting.ContainsKey("Monitors")) {
			$wallpaperFile = $wallpaperSetting.Monitors[0].File
		}
		else {
			$wallpaperFile = $wallpaperSetting.File
		}

		$wallpaperPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile

		Write-LogDebug " Resolved lock screen wallpaper path: $wallpaperPath" -Style Step

		if (-not (Test-Path $wallpaperPath)) {
			Write-LogError "Lock screen wallpaper file not found at path: $wallpaperPath"
			return
		}

		# PersonalizationCSP requires elevation; fall back to per-user registry if needed
		$cspKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
		try {
			if (-not (Test-Path $cspKey)) {
				New-Item -Path $cspKey -Force | Out-Null
			}
			Set-ItemProperty -Path $cspKey -Name "LockScreenImagePath"   -Value $wallpaperPath -Force
			Set-ItemProperty -Path $cspKey -Name "LockScreenImageUrl"    -Value $wallpaperPath -Force
			Set-ItemProperty -Path $cspKey -Name "LockScreenImageStatus" -Value 1              -Force
			Write-LogSuccess "Lock screen wallpaper configured to [$wallpaperFile]"
		}
		catch {
			Write-LogDebug " PersonalizationCSP write failed (elevation required?): $_" -Style Step
			Write-LogDebug " Trying per-user registry fallback..." -Style Step
			# Per-user fallback (Windows 11 respects this for the lock screen in some builds)
			$userKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
			Set-ItemProperty -Path $userKey -Name "RotatingLockScreenEnabled"        -Value 0 -Force -ErrorAction SilentlyContinue
			Set-ItemProperty -Path $userKey -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

			$personalizationKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
			Set-ItemProperty -Path $personalizationKey -Name "LockScreenImagePath" -Value $wallpaperPath -Force -ErrorAction SilentlyContinue

			Write-LogWarning "Lock screen wallpaper set via per-user registry (run as Administrator for full CSP support)"
		}
	}
	catch {
		Write-LogError "Error detected: [$($_.Exception.Message)]"

		ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning lock screen wallpaper setup!"
	}
}
