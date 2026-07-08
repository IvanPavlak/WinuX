function Resolve-Selection {
	<#
	.SYNOPSIS
		Presents an interactive menu for user selection, supporting single/multiple selections and hierarchical navigation.

	.DESCRIPTION
		The canonical menu selection function used throughout the system. Displays a numbered menu and returns the
		selected option(s). Supports two modes:

		1. FLAT MODE: Simple Yes/No or custom option list. User selects by number or text.
		2. HIERARCHICAL MODE: When `-GroupsConfig` is provided, navigates nested groups (e.g., browser URL groups).
		   Supports dot-notation for nested selection ("Work.Backend"), automatic expansion of parent groups,
		   and parent/child navigation in the display.

		Used by Open-Browser, Open-Project, Set-Locale, Set-DisplayLanguage, Configure-NerdFont, and others.

	.PARAMETER OptionList
		Flat list of options to display. Defaults to @("Yes", "No"). Ignored when GroupsConfig is provided.

	.PARAMETER InputObject
		Pre-selected option(s) from pipeline. Skips the interactive menu if provided.

	.PARAMETER MenuTitle
		Title displayed at the top of the menu. Defaults to "[Available Options]".

	.PARAMETER HideMenuTitle
		Suppresses the menu title.

	.PARAMETER HideSelection
		Hides the final selection echo.

	.PARAMETER PromptMessage
		Prompt text shown before the menu. If omitted, a generic prompt is used.

	.PARAMETER HidePromptMessage
		Suppresses the prompt message.

	.PARAMETER AllowEmptyPromptResponse
		When true, pressing Enter with no input returns `$null` instead of re-prompting.

	.PARAMETER AllowMultipleSelections
		When true, allows comma-separated numbers or names to select multiple items.

	.PARAMETER DefaultOptionIndex
		Zero-based index of the default option (returned if user presses Enter with no input). Defaults to 0.

	.PARAMETER GroupsConfig
		For hierarchical mode: hashtable of nested group definitions. Enables parent/child navigation and
		expansion. Required to unlock hierarchical menu functionality.

	.EXAMPLE
		Resolve-Selection -OptionList @("English", "Español", "Français") -PromptMessage "Select a language"
		Shows a 3-item menu and returns the selected option.

	.EXAMPLE
		Resolve-Selection -GroupsConfig $Configuration.BrowserGroups -AllowMultipleSelections
		Shows a hierarchical browser group menu with multi-select support.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string[]]$OptionList = @("Yes", "No"),

		[Parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[string[]]$InputObject,

		[Parameter(Mandatory = $false)]
		[string]$MenuTitle = "[Available Options]",

		[Parameter(Mandatory = $false)]
		[switch]$HideMenuTitle,

		[Parameter(Mandatory = $false)]
		[switch]$HideSelection,

		[Parameter(Mandatory = $false)]
		[string]$PromptMessage,

		[Parameter(Mandatory = $false)]
		[switch]$HidePromptMessage,

		[Parameter(Mandatory = $false)]
		[switch]$AllowEmptyPromptResponse = $false,

		[Parameter(Mandatory = $false)]
		[switch]$AllowMultipleSelections = $false,

		[Parameter(Mandatory = $false)]
		[int]$DefaultOptionIndex = 0,

		[Parameter(Mandatory = $false)]
		$GroupsConfig
	)

	$useHierarchical = $null -ne $GroupsConfig -and $GroupsConfig.Count -gt 0

	if ($useHierarchical) {
		$displayItems = [System.Collections.ArrayList]::new()
		$lookupMap = @{}
		$groupIndex = 1

		foreach ($groupItem in $GroupsConfig) {
			$groupName = @($groupItem.Keys)[0]
			$groupValue = $groupItem[$groupName]
			$indexPath = "$groupIndex"
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add($groupName) | Out-Null

			ProcessGroupRecursive `
				-GroupValue $groupValue `
				-IndexPath $indexPath `
				-DisplayItems $displayItems `
				-LookupMap $lookupMap `
				-PathNames $pathNames `
				-Depth 0

			$groupIndex++
		}
	}

	if ($InputObject) {
		$validInputs = $InputObject | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

		if ($validInputs.Count -eq 0) {
			return $null
		}

		if ($useHierarchical) {
			$resolved = @()
			$invalidSelections = @()

			foreach ($item in $validInputs) {
				$trimmedItem = $item.Trim()

				if ($lookupMap.ContainsKey($trimmedItem)) {
					$resolved += $lookupMap[$trimmedItem]
				}
				else {
					$invalidSelections += $item
				}
			}

			if ($invalidSelections.Count -gt 0) {
				$caller = (Get-PSCallStack)[1].Command
				Write-Host -ForegroundColor Red "`n=> The following selection(s) were invalid in [$caller] => $($invalidSelections -join "', '")"
				break
			}

			$expanded = @()
			foreach ($item in $resolved) {
				if ($item.StructureType -eq "NestedHashtables" -and $item.DirectChildren.Count -gt 0) {
					foreach ($childPath in $item.DirectChildren) {
						$expanded += $lookupMap[$childPath]
					}
				}
				else {
					$expanded += $item
				}
			}

			return $expanded
		}
		else {
			$resolved = @()
			$invalidSelections = @()
			foreach ($item in $validInputs) {
				$trimmedItem = $item.Trim()
				if ($trimmedItem -match '^\d+$' -and [int]$trimmedItem -ge 1 -and [int]$trimmedItem -le $OptionList.Count) {
					$resolved += $OptionList[[int]$trimmedItem - 1]
				}
				elseif ($OptionList -icontains $trimmedItem) {
					$resolved += $OptionList | Where-Object { $_ -eq $trimmedItem }
				}
				else {
					$invalidSelections += $item
				}
			}
			if ($invalidSelections.Count -gt 0) {
				$caller = (Get-PSCallStack)[1].Command
				Write-Host -ForegroundColor Yellow "`n The following selections were invalid in [$caller] and have been ignored => $($invalidSelections -join "', '")"
			}
			return $resolved | Select-Object -Unique
		}
	}

	if (-not $HideMenuTitle) {
		if ($HideSelection) {
			Write-Host -ForegroundColor DarkCyan "`n$MenuTitle"
		}
		else {
			Write-Host -ForegroundColor DarkCyan "`n$MenuTitle`n"
		}
	}
	else {
		Write-Host ""
	}

	if (-not $HideSelection) {
		if ($useHierarchical) {
			foreach ($item in $displayItems) {
				$indent = "  " * $item.Depth

				Write-Host -ForegroundColor DarkCyan -NoNewline " $indent["
				Write-Host -ForegroundColor Green -NoNewline $item.IndexPath
				Write-Host -ForegroundColor DarkCyan ("] {0}" -f $item.Text)
			}
		}
		else {
			for ($i = 0; $i -lt $OptionList.Count; $i++) {
				Write-Host -ForegroundColor DarkCyan -NoNewline " ["
				Write-Host -ForegroundColor Green -NoNewline ($i + 1)
				Write-Host -ForegroundColor DarkCyan ("] {0}" -f $OptionList[$i])
			}
		}
	}

	$hasDefault = $DefaultOptionIndex -ge 1 -and $DefaultOptionIndex -le $OptionList.Count
	$defaultLabel = if ($hasDefault) { $OptionList[$DefaultOptionIndex - 1] } else { $null }

	if (-not $PSBoundParameters.ContainsKey('PromptMessage')) {
		$PromptMessage = if ($AllowMultipleSelections) {
			"Enter selection(s) by number or name"
		}
		else {
			"Enter selection by number or name"
		}
	}

	do {
		if ($HideSelection) {
			$promptSuffix = ""
			$promptPrefix = "`n"
		}
		else {
			$promptSuffix = if ($AllowMultipleSelections) { " (space/comma-separated): " } else { ": " }
			$promptPrefix = "`n"
		}

		$defaultHint = if ($hasDefault) { " (default: $defaultLabel)" } else { "" }
		$displayPrompt = if ($HidePromptMessage) { "$promptPrefix$promptSuffix" } else { "$promptPrefix$($PromptMessage)$defaultHint$promptSuffix" }
		$userInput = Custom-ReadHost $displayPrompt -AddNewLine:$false
		if ([string]::IsNullOrWhiteSpace($userInput)) {
			if ($hasDefault) {
				return $defaultLabel
			}
			if ($AllowEmptyPromptResponse) {
				return $null
			}
			Write-Host -ForegroundColor Red "`n=> Empty input is not allowed. Make a selection!"
			continue
		}
		$currentInputs = $userInput -split '[\s,]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

		if ($useHierarchical) {
			$resolved = @()
			$errorMessages = @()

			foreach ($item in $currentInputs) {
				if ($lookupMap.ContainsKey($item)) {
					$resolved += $lookupMap[$item]
				}
				else {
					$errorMessages += "`n=> Invalid selection => [$item]"
				}
			}

			if ($errorMessages.Count -gt 0) {
				$errorMessages | ForEach-Object { Write-Host -ForegroundColor Red $_ }
				Write-Host -ForegroundColor DarkCyan "`n  Please try again!"
			}
			else {
				$expanded = @()
				foreach ($item in $resolved) {
					if ($item.StructureType -eq "NestedHashtables" -and $item.DirectChildren.Count -gt 0) {
						foreach ($childPath in $item.DirectChildren) {
							$expanded += $lookupMap[$childPath]
						}
					}
					else {
						$expanded += $item
					}
				}
				return $expanded
			}
		}
		else {
			$resolved = @()
			$errorMessages = @()
			foreach ($item in $currentInputs) {
				if ($item -match '^\d+$' -and [int]$item -ge 1 -and [int]$item -le $OptionList.Count) {
					$resolved += $OptionList[[int]$item - 1]
				}
				elseif ($OptionList -icontains $item) {
					$resolved += $OptionList | Where-Object { $_ -eq $item }
				}
				else {
					$errorMessages += "`n=> Invalid selection => [$item]"
				}
			}
			if ($errorMessages.Count -gt 0) {
				$errorMessages | ForEach-Object { Write-Host -ForegroundColor Red $_ }
				Write-Host -ForegroundColor DarkCyan "`n  Try again!"
			}
			else {
				return $resolved | Select-Object -Unique
			}
		}
	} while ($true)
}
