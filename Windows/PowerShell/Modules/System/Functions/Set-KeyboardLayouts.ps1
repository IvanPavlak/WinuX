function Set-KeyboardLayouts {
	<#
	.SYNOPSIS
		Configures keyboard layouts from predefined layout sets.

	.DESCRIPTION
		Reads layout sets from `KeyboardLayoutSets` in Configuration.psd1 (e.g. "Gaming", "Development").
		Each set is a named collection of keyboard layout codes to install.
		When called with a layout set name, installs all layouts in that set.
		When called without arguments, shows an interactive menu of available layout sets.

	.PARAMETER LayoutSet
		Name of the layout set to install (e.g. "Gaming"). Omit to show the interactive menu.

	.PARAMETER Override
		Force reconfiguration even if the layout set is already active.

	.EXAMPLE
		Set-KeyboardLayouts
		Shows the layout set selection menu.

	.EXAMPLE
		Set-KeyboardLayouts -LayoutSet "Gaming"
		Installs the Gaming layout set.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[string]$LayoutSet,

		[Parameter(Mandatory = $false)]
		[switch]$Override
	)

	$layoutSets = $Configuration.KeyboardLayoutSets
	$allLayouts = $Configuration.KeyboardLayouts
	$defaultSetName = $Configuration.DefaultKeyboardLayoutSet
	$targetSetName = ""

	if (-not [string]::IsNullOrWhiteSpace($LayoutSet)) {
		if ($layoutSets.ContainsKey($LayoutSet)) {
			$targetSetName = $LayoutSet
		}
		else {
			Write-LogError "Error: Layout set [$LayoutSet] not found in configuration!"
			return
		}
	}
 else {
		$layoutSetOptions = $layoutSets.Keys
		$resolveParams = @{
			OptionList               = $layoutSetOptions
			MenuTitle                = "[Available Keyboard Layout Sets]"
			PromptMessage            = "Select a layout set (or press Enter for default [$defaultSetName])"
			AllowEmptyPromptResponse = $true
		}

		$selectedSetName = Resolve-Selection @resolveParams

		if ([string]::IsNullOrWhiteSpace($selectedSetName)) {
			$targetSetName = $defaultSetName
		}
		else {
			$targetSetName = $selectedSetName
		}
	}

	if (-not $layoutSets.ContainsKey($targetSetName)) {
		Write-LogError "Error: Layout set [$targetSetName] not found in configuration."
		return
	}

	$targetLayoutNames = $layoutSets[$targetSetName]
	$targetLayoutCodes = $targetLayoutNames | ForEach-Object { $allLayouts[$_] }

	Write-LogTitle "Setting Keyboard Layouts to [$($targetLayoutNames -join ', ')]" -BlankLineAfter

	# Detect current layouts from the actual Windows input system (not the legacy registry)
	$currentLayoutCodes = @()
	foreach ($lang in (Get-WinUserLanguageList)) {
		foreach ($tip in $lang.InputMethodTips) {
			$parts = $tip -split ':'
			if ($parts.Count -ge 2) {
				$currentLayoutCodes += $parts[1]
			}
		}
	}

	$isAlreadyConfigured = $false
	$currentJoined = ($currentLayoutCodes -join ',')
	$targetJoined = ($targetLayoutCodes -join ',')
	if ($currentJoined -eq $targetJoined) {
		$isAlreadyConfigured = $true
	}

	if ($isAlreadyConfigured -and -not $Override) {
		Write-LogWarning "Keyboard layouts already configured to the '$targetSetName' set" -NoLeadingNewline
	}
 else {
		try {
			# Build input method tip map: LanguageTag -> InputMethodTips
			$tipMap = [ordered]@{}
			foreach ($layoutCode in $targetLayoutCodes) {
				$lcidHex = $layoutCode.Substring(4)
				$lcid = [int]"0x$lcidHex"
				$culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcid)
				$langTag = $culture.Name
				$inputMethodTip = "${lcidHex}:${layoutCode}"

				if (-not $tipMap.Contains($langTag)) {
					$tipMap[$langTag] = @()
				}
				$tipMap[$langTag] += $inputMethodTip
			}

			# Update the existing language list to set input methods
			$langList = Get-WinUserLanguageList

			foreach ($entry in $tipMap.GetEnumerator()) {
				$existingLang = $langList | Where-Object { $_.LanguageTag -eq $entry.Key }
				if ($existingLang) {
					$existingLang.InputMethodTips.Clear()
					foreach ($tip in $entry.Value) {
						$existingLang.InputMethodTips.Add($tip)
					}
				}
				else {
					$langList.Add($entry.Key)
					$addedLang = $langList[$langList.Count - 1]
					$addedLang.InputMethodTips.Clear()
					foreach ($tip in $entry.Value) {
						$addedLang.InputMethodTips.Add($tip)
					}
				}
			}

			# Remove stale input methods from languages not in the target set
			foreach ($lang in $langList) {
				if (-not $tipMap.Contains($lang.LanguageTag) -and $lang.InputMethodTips.Count -gt 0) {
					$lang.InputMethodTips.Clear()
				}
			}

			# Reorder language list so the first target layout's language comes first
			$orderedTags = @()
			foreach ($layoutCode in $targetLayoutCodes) {
				$lcidHex = $layoutCode.Substring(4)
				$lcid = [int]"0x$lcidHex"
				$culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcid)
				if ($orderedTags -notcontains $culture.Name) {
					$orderedTags += $culture.Name
				}
			}

			$reorderedList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]
			foreach ($tag in $orderedTags) {
				$match = $langList | Where-Object { $_.LanguageTag -eq $tag }
				if ($match) { $reorderedList.Add($match) }
			}
			# Append any remaining languages not in the target set
			foreach ($lang in $langList) {
				if ($orderedTags -notcontains $lang.LanguageTag) {
					$reorderedList.Add($lang)
				}
			}
			$langList = $reorderedList

			Write-LogStep " Applying new keyboard layout configuration..."
			Set-WinUserLanguageList $langList -Force

			# Also update the Preload registry for legacy application compatibility
			$preloadPath = "HKCU:\Keyboard Layout\Preload"
			if (-not (Test-Path $preloadPath)) {
				New-Item -Path $preloadPath -Force | Out-Null
			}

			$existingPreload = Get-ItemProperty -Path $preloadPath -ErrorAction SilentlyContinue
			$existingPreload.PSObject.Properties |
				Where-Object { $_.Name -match '^\d+$' } |
				ForEach-Object {
					Remove-ItemProperty -Path $preloadPath -Name $_.Name -Force
				}

			for ($i = 0; $i -lt $targetLayoutCodes.Count; $i++) {
				$regName = ($i + 1).ToString()
				$regValue = $targetLayoutCodes[$i]
				Set-ItemProperty -Path $preloadPath -Name $regName -Value $regValue -Force
			}

			# Verify configuration from the actual Windows input system
			$verifiedLangs = Get-WinUserLanguageList
			Write-LogTitle "Final Configuration" -BlankLineAfter
			$layoutIndex = 1
			foreach ($lang in $verifiedLangs) {
				foreach ($tip in $lang.InputMethodTips) {
					$parts = $tip -split ':'
					$layoutCode = if ($parts.Count -ge 2) { $parts[1] } else { $tip }
					$layoutName = ($allLayouts.GetEnumerator() | Where-Object { $_.Value -eq $layoutCode }).Name
					if (-not $layoutName) { $layoutName = "Unknown" }
					Write-LogStep " ${layoutIndex}: $layoutCode ($layoutName)" -NoLeadingNewline
					$layoutIndex++
				}
			}

			Write-LogSuccess "Keyboard layouts configured successfully!"
			Write-LogWarning "You may need to log off and back on for changes to take effect"
		}
		catch {
			Write-LogError "An error occurred while configuring keyboard layouts: $_"
		}
	}
}
