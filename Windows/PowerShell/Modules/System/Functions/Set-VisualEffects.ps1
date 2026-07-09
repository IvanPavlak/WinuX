function Set-VisualEffects {
	<#
	.SYNOPSIS
		Applies the Performance Options "Visual Effects" settings from configuration.

	.DESCRIPTION
		Reads per-effect booleans from `VisualEffects` in Configuration.psd1 /
		Configuration.local.psd1 and applies them - the programmatic equivalent of the
		"Custom" profile in System Properties > Performance Options > Visual Effects.
		Every key mirrors one dialog checkbox one-to-one: $true enables the effect
		(appearance), $false disables it (performance). Keys left out of the
		configuration are not touched, and when the section is absent or empty the
		function changes NOTHING - the machine keeps its current visual effects. This
		keeps the upstream default vanilla; a fork opts in via its local configuration.

		Explorer- and DWM-backed effects are written to the registry; the remaining
		effects go through SystemParametersInfo - the same mechanism the dialog itself
		uses - which persists them to the user profile (UserPreferencesMask et al.) and
		broadcasts WM_SETTINGCHANGE so they apply live. The dialog's radio button is
		set to "Custom" (VisualFXSetting = 3) whenever at least one effect is managed.
		Restart-Explorer runs only when a registry-backed effect actually changed.

		Idempotent - compares every configured effect against the current state and
		returns early when nothing needs to change. When changes are applied, every
		managed effect is reported on its own line: green when enabled, red when
		disabled, yellow [skipped] when already at the configured value. Unknown
		keys are skipped with a warning.

	.EXAMPLE
		Set-VisualEffects
		Applies all effects configured in the VisualEffects section.
	#>
	Write-LogTitle "Setting Visual Effects"

	$desiredEffects = $Configuration.VisualEffects
	if (-not ($desiredEffects -is [hashtable]) -or $desiredEffects.Count -eq 0) {
		Write-LogWarning "VisualEffects is not configured - leaving visual effects as-is!"
		return
	}

	# One entry per checkbox in the Visual Effects dialog (alphabetical, like the dialog).
	# Registry entries cover the Explorer/DWM settings that have no SPI code; everything else
	# goes through SystemParametersInfo so it applies live and persists without a logoff.
	# ShowThumbnailsInsteadOfIcons maps to IconsOnly, so its On/Off values are inverted.
	$effectDefinitions = @(
		@{ Key = "AnimateControlsAndElementsInsideWindows"; Kind = "SpiParameter"; GetCode = 0x1042; SetCode = 0x1043 }
		@{ Key = "AnimateWindowsWhenMinimisingAndMaximising"; Kind = "SpiMinMaxAnimation" }
		@{ Key = "AnimationsInTheTaskbar"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAnimations"; OnValue = 1; OffValue = 0 }
		@{ Key = "EnablePeek"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\DWM"; Name = "EnableAeroPeek"; OnValue = 1; OffValue = 0 }
		@{ Key = "FadeOrSlideMenusIntoView"; Kind = "SpiParameter"; GetCode = 0x1002; SetCode = 0x1003 }
		@{ Key = "FadeOrSlideToolTipsIntoView"; Kind = "SpiParameter"; GetCode = 0x1016; SetCode = 0x1017 }
		@{ Key = "FadeOutMenuItemsAfterClicking"; Kind = "SpiParameter"; GetCode = 0x1014; SetCode = 0x1015 }
		@{ Key = "SaveTaskbarThumbnailPreviews"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\DWM"; Name = "AlwaysHibernateThumbnails"; OnValue = 1; OffValue = 0 }
		@{ Key = "ShowShadowsUnderMousePointer"; Kind = "SpiParameter"; GetCode = 0x101A; SetCode = 0x101B }
		@{ Key = "ShowShadowsUnderWindows"; Kind = "SpiParameter"; GetCode = 0x1024; SetCode = 0x1025 }
		@{ Key = "ShowThumbnailsInsteadOfIcons"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "IconsOnly"; OnValue = 0; OffValue = 1 }
		@{ Key = "ShowTranslucentSelectionRectangle"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ListviewAlphaSelect"; OnValue = 1; OffValue = 0 }
		@{ Key = "ShowWindowContentsWhileDragging"; Kind = "SpiUiParameter"; GetCode = 0x0026; SetCode = 0x0025 }
		@{ Key = "SlideOpenComboBoxes"; Kind = "SpiParameter"; GetCode = 0x1004; SetCode = 0x1005 }
		@{ Key = "SmoothEdgesOfScreenFonts"; Kind = "SpiFontSmoothing"; GetCode = 0x004A; SetCode = 0x004B }
		@{ Key = "SmoothScrollListBoxes"; Kind = "SpiParameter"; GetCode = 0x1006; SetCode = 0x1007 }
		@{ Key = "UseDropShadowsForIconLabelsOnTheDesktop"; Kind = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ListviewShadow"; OnValue = 1; OffValue = 0 }
	)

	# --- Typo protection: warn about configured keys that match no known effect ---
	$knownKeys = $effectDefinitions.Key
	foreach ($configuredKey in $desiredEffects.Keys) {
		if ($configuredKey -notin $knownKeys) {
			Write-LogWarning "Unknown VisualEffects key [$configuredKey] - skipping!"
		}
	}

	$applicableDefinitions = @($effectDefinitions | Where-Object { $desiredEffects.ContainsKey($_.Key) })
	if ($applicableDefinitions.Count -eq 0) {
		Write-LogWarning "VisualEffects contains no known effect keys - leaving visual effects as-is!"
		return
	}

	# SystemParametersInfo bridge - only compiled when an SPI-backed effect is configured
	$needsNativeMethods = @($applicableDefinitions | Where-Object { $_.Kind -ne "Registry" }).Count -gt 0
	if ($needsNativeMethods -and -not ([System.Management.Automation.PSTypeName]'VisualEffectsModule.NativeMethods').Type) {
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace VisualEffectsModule {
	public static class NativeMethods {
		[StructLayout(LayoutKind.Sequential)]
		public struct ANIMATIONINFO {
			public uint cbSize;
			public int iMinAnimate;
		}

		[DllImport("user32.dll", SetLastError = true)]
		private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref int pvParam, uint fWinIni);

		[DllImport("user32.dll", SetLastError = true)]
		private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

		[DllImport("user32.dll", SetLastError = true)]
		private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref ANIMATIONINFO pvParam, uint fWinIni);

		// SPIF_UPDATEINIFILE | SPIF_SENDCHANGE - persist to the user profile and broadcast the change
		private const uint SPIF_PERSIST = 0x01 | 0x02;

		// Effects reported through pvParam (SPI_GET* family)
		public static int GetParameter(uint getAction) {
			int value = 0;
			SystemParametersInfo(getAction, 0, ref value, 0);
			return value;
		}

		// Effects carried in pvParam (SPI_SET* family, e.g. menu animation, drop shadow)
		public static void SetParameter(uint setAction, int value) {
			SystemParametersInfo(setAction, 0, (IntPtr)value, SPIF_PERSIST);
		}

		// Effects carried in uiParam (SPI_SETDRAGFULLWINDOWS, SPI_SETFONTSMOOTHING)
		public static void SetUiParameter(uint setAction, int value) {
			SystemParametersInfo(setAction, (uint)value, IntPtr.Zero, SPIF_PERSIST);
		}

		// Min/max window animation uses the ANIMATIONINFO struct (SPI_GET/SETANIMATION)
		public static bool GetMinMaxAnimation() {
			ANIMATIONINFO info = new ANIMATIONINFO();
			info.cbSize = (uint)Marshal.SizeOf(typeof(ANIMATIONINFO));
			SystemParametersInfo(0x0048, info.cbSize, ref info, 0);
			return info.iMinAnimate != 0;
		}

		public static void SetMinMaxAnimation(bool enabled) {
			ANIMATIONINFO info = new ANIMATIONINFO();
			info.cbSize = (uint)Marshal.SizeOf(typeof(ANIMATIONINFO));
			info.iMinAnimate = enabled ? 1 : 0;
			SystemParametersInfo(0x0049, info.cbSize, ref info, SPIF_PERSIST);
		}
	}
}
"@
	}

	# --- Compare every configured effect against the current state ---
	$effectStates = @()
	foreach ($definition in $applicableDefinitions) {
		$desired = [bool]$desiredEffects[$definition.Key]

		$current = switch ($definition.Kind) {
			"Registry" {
				try {
					$currentRaw = Get-ItemPropertyValue -Path $definition.Path -Name $definition.Name -ErrorAction Stop
					$currentRaw -eq $definition.OnValue
				}
				catch {
					# Value or key missing - state unknown, force an explicit write
					$null
				}
			}
			"SpiParameter" { [VisualEffectsModule.NativeMethods]::GetParameter($definition.GetCode) -ne 0 }
			"SpiUiParameter" { [VisualEffectsModule.NativeMethods]::GetParameter($definition.GetCode) -ne 0 }
			"SpiFontSmoothing" { [VisualEffectsModule.NativeMethods]::GetParameter($definition.GetCode) -ne 0 }
			"SpiMinMaxAnimation" { [VisualEffectsModule.NativeMethods]::GetMinMaxAnimation() }
		}

		$effectStates += @{ Definition = $definition; Desired = $desired; NeedsChange = ($current -ne $desired) }
	}

	# The dialog's radio button: 0=LetWindowsChoose, 1=BestAppearance, 2=BestPerformance, 3=Custom
	$visualFxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
	try {
		$currentVisualFxSetting = Get-ItemPropertyValue -Path $visualFxPath -Name "VisualFXSetting" -ErrorAction Stop
	}
	catch {
		$currentVisualFxSetting = $null
	}

	$pendingChanges = @($effectStates | Where-Object { $_.NeedsChange })
	if ($pendingChanges.Count -eq 0 -and $currentVisualFxSetting -eq 3) {
		Write-LogWarning "Visual effects already configured!"
		return
	}

	# --- Apply every effect: green = enabled, red = disabled, yellow = already correct ---
	$registryChanges = 0
	foreach ($effectState in $effectStates) {
		$definition = $effectState.Definition
		$desired = $effectState.Desired

		if (-not $effectState.NeedsChange) {
			Write-LogStep " $($definition.Key) => [skipped]" -Style Warning
			continue
		}

		$stateLabel = if ($desired) { "enabled" } else { "disabled" }
		$rowStyle = if ($desired) { "Success" } else { "Error" }

		try {
			switch ($definition.Kind) {
				"Registry" {
					if (-not (Test-Path $definition.Path)) {
						New-Item -Path $definition.Path -Force | Out-Null
					}
					$targetValue = if ($desired) { $definition.OnValue } else { $definition.OffValue }
					Set-ItemProperty -Path $definition.Path -Name $definition.Name -Value $targetValue -Force
					$registryChanges++
				}
				"SpiParameter" {
					[VisualEffectsModule.NativeMethods]::SetParameter($definition.SetCode, [int]$desired)
				}
				"SpiUiParameter" {
					[VisualEffectsModule.NativeMethods]::SetUiParameter($definition.SetCode, [int]$desired)
				}
				"SpiFontSmoothing" {
					[VisualEffectsModule.NativeMethods]::SetUiParameter($definition.SetCode, [int]$desired)
					if ($desired) {
						# SPI_SETFONTSMOOTHINGTYPE => FE_FONTSMOOTHINGCLEARTYPE; without it,
						# enabling font smoothing falls back to legacy greyscale anti-aliasing
						[VisualEffectsModule.NativeMethods]::SetParameter(0x200B, 2)
					}
				}
				"SpiMinMaxAnimation" {
					[VisualEffectsModule.NativeMethods]::SetMinMaxAnimation($desired)
				}
			}
			Write-LogStep " $($definition.Key) => [$stateLabel]" -Style $rowStyle
		}
		catch {
			Write-LogError "Failed to set effect [$($definition.Key)]: $($_.Exception.Message)"
		}
	}

	# Managing individual effects is exactly what the dialog's "Custom" profile means
	if ($currentVisualFxSetting -ne 3) {
		try {
			if (-not (Test-Path $visualFxPath)) {
				New-Item -Path $visualFxPath -Force | Out-Null
			}
			Set-ItemProperty -Path $visualFxPath -Name "VisualFXSetting" -Value 3 -Force
		}
		catch {
			Write-LogError "Failed to set VisualFXSetting: $($_.Exception.Message)"
		}
	}

	# SPI-backed changes broadcast WM_SETTINGCHANGE themselves; only the Explorer/DWM
	# registry values need Explorer to reload them
	if ($registryChanges -gt 0) {
		Restart-Explorer
	}

	Write-LogSuccess "Visual effects configured!"
}
