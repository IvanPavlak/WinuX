# TODO: Separate the recent section from the available groups visually
function Open-Acrobat {
	<#
    .SYNOPSIS
        Opens Adobe Acrobat with one or more PDF groups from the configuration.

    .DESCRIPTION
        Opens PDFs configured in `AcrobatPdfGroups` in Configuration.psd1.
        When a PDF key is provided, opens the corresponding file directly.
        When multiple keys are provided, opens all of them.
        When called without arguments or with an empty `-Pdf`, shows an interactive menu
        of the PDF groups defined in `AcrobatGroups`.

    .PARAMETER Pdf
        One or more PDF group key names as defined in `AcrobatPdfGroups` in Configuration.psd1.
        Omit or pass empty to show the interactive selection menu.

    .EXAMPLE
        Open-Acrobat
        Shows the PDF group selection menu.

    .EXAMPLE
        Open-Acrobat -Pdf "ExampleCharacter"
        Opens the PDF configured under the "ExampleCharacter" key in AcrobatPdfGroups.
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Pdf
	)

	$pdfGroupsConfig = $Configuration.AcrobatPdfGroups
	if (-not $pdfGroupsConfig) {
		Write-LogError "Error: AcrobatPdfGroups not found in configuration."
		return
	}

	try {
		Write-LogStep "Opening Adobe Acrobat..."

		if (-not $PSBoundParameters.ContainsKey('Pdf')) {
			if (-not (Get-Process -Name "Acrobat" -ErrorAction SilentlyContinue)) {
				Start-Process "Acrobat" -ErrorAction Stop
				Write-LogSuccess "Adobe Acrobat opened!"
			}
			else {
				Write-LogWarning "Adobe Acrobat is already running!"
			}
			return
		}

		$validPdfGroups = $Configuration.AcrobatGroups
		if (-not $validPdfGroups) {
			Write-LogError "Error: AcrobatGroups not found in configuration."
			return
		}

		$recentLimit = 10
		$recentPdfEntries = @()
		$recentPdfMap = @{}
		$seenRecentPaths = @{}

		$acrobatRecentBase = 'HKCU:\Software\Adobe\Adobe Acrobat\DC\AVGeneral\cRecentFiles'
		$acrobatRecentKeys = @(
			Get-ChildItem -Path $acrobatRecentBase -ErrorAction SilentlyContinue |
				Where-Object { $_.PSChildName -match '^c\d+$' } |
				Sort-Object { [int]($_.PSChildName -replace '^c', '') }
		)

		foreach ($recentKey in $acrobatRecentKeys) {
			if ($recentPdfEntries.Count -ge $recentLimit) {
				break
			}

			$recentProperties = Get-ItemProperty -Path $recentKey.PSPath -ErrorAction SilentlyContinue
			$rawPath = $recentProperties.tDIText
			if ([string]::IsNullOrWhiteSpace($rawPath)) {
				continue
			}

			$normalizedPath = $rawPath -replace '/', '\'
			if ($normalizedPath -match '^\\([A-Za-z])\\(.+)$') {
				$normalizedPath = "{0}:\{1}" -f $Matches[1], $Matches[2]
			}

			if (-not $normalizedPath.ToLowerInvariant().EndsWith('.pdf')) {
				continue
			}

			$pathKey = $normalizedPath.ToLowerInvariant()
			if ($seenRecentPaths.ContainsKey($pathKey)) {
				continue
			}

			$seenRecentPaths[$pathKey] = $true
			$recentLabel = "Recent => $([System.IO.Path]::GetFileNameWithoutExtension($normalizedPath))"
			$suffix = 2
			while ($recentPdfMap.ContainsKey($recentLabel)) {
				$recentLabel = "Recent => $([System.IO.Path]::GetFileNameWithoutExtension($normalizedPath)) ($suffix)"
				$suffix++
			}

			$recentPdfEntries += [PSCustomObject]@{
				Label = $recentLabel
				Path  = $normalizedPath
			}

			$recentPdfMap[$recentLabel] = $normalizedPath
		}

		$recentFolder = [Environment]::GetFolderPath('Recent')
		if ($recentPdfEntries.Count -lt $recentLimit -and -not [string]::IsNullOrWhiteSpace($recentFolder) -and (Test-Path $recentFolder)) {
			$shortcutFiles = @(
				Get-ChildItem -Path $recentFolder -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue |
					Sort-Object -Property LastWriteTime -Descending
			)

			if ($shortcutFiles.Count -gt 0) {
				$wshShell = $null
				try {
					$wshShell = New-Object -ComObject WScript.Shell
				}
				catch {
					$wshShell = $null
				}

				if ($wshShell) {
					try {
						foreach ($shortcut in $shortcutFiles) {
							if ($recentPdfEntries.Count -ge $recentLimit) {
								break
							}

							$targetPath = $null
							try {
								$targetPath = $wshShell.CreateShortcut($shortcut.FullName).TargetPath
							}
							catch {
								continue
							}

							if ([string]::IsNullOrWhiteSpace($targetPath)) {
								continue
							}

							if (-not $targetPath.ToLowerInvariant().EndsWith('.pdf')) {
								continue
							}

							$pathKey = $targetPath.ToLowerInvariant()
							if ($seenRecentPaths.ContainsKey($pathKey)) {
								continue
							}

							$seenRecentPaths[$pathKey] = $true
							$recentLabel = "Recent => $([System.IO.Path]::GetFileNameWithoutExtension($targetPath))"
							$suffix = 2
							while ($recentPdfMap.ContainsKey($recentLabel)) {
								$recentLabel = "Recent => $([System.IO.Path]::GetFileNameWithoutExtension($targetPath)) ($suffix)"
								$suffix++
							}

							$recentPdfEntries += [PSCustomObject]@{
								Label = $recentLabel
								Path  = $targetPath
							}

							$recentPdfMap[$recentLabel] = $targetPath
						}
					}
					finally {
						if ([System.Runtime.InteropServices.Marshal]::IsComObject($wshShell)) {
							[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshShell)
						}
					}
				}
			}
		}

		$pdfOptions = @($validPdfGroups)
		if ($recentPdfEntries.Count -gt 0) {
			$pdfOptions += $recentPdfEntries.Label
		}

		$resolveParams = @{
			OptionList               = $pdfOptions
			MenuTitle                = "[Available PDF Groups and Recent PDFs]"
			PromptMessage            = "Select one or more PDF groups/recent PDFs to open"
			AllowEmptyPromptResponse = $true
			AllowMultipleSelections  = $true
		}

		$validInputSelection = @($Pdf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		if ($validInputSelection.Count -gt 0) {
			$resolveParams['InputObject'] = $validInputSelection
		}

		$selectedPdfs = Resolve-Selection @resolveParams

		if (-not $selectedPdfs) {
			Write-LogWarning "No selection made. Aborting."
			return
		}

		$allSuccessful = $true
		foreach ($selection in $selectedPdfs) {
			if ($validPdfGroups -contains $selection) {
				$pathStrings = $pdfGroupsConfig[$selection]
				foreach ($pathString in $pathStrings) {
					$resolvedPath = $null
					try {
						$resolvedPath = Invoke-Command -ScriptBlock ([scriptblock]::Create("`$global:MachineSpecificPaths.$pathString"))
					}
					catch {
						Write-LogError "Could not resolve path [$pathString] for group [$selection]. Check the Configuration.ps1 file!"
						$allSuccessful = $false; break
					}

					if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
						Write-LogError "PDF path is null or empty for [$selection] (Path => [$pathString])"
						$allSuccessful = $false; break
					}

					if (Test-Path $resolvedPath) {
						Start-Process $resolvedPath -ErrorAction Stop
						Write-LogStep "  Opened PDF for [$selection] from [$resolvedPath]"
					}
					else {
						Write-LogError "PDF not found at configured path => [$resolvedPath]"
						$allSuccessful = $false; break
					}
				}

				if (-not $allSuccessful) { break }
			}
			elseif ($recentPdfMap.ContainsKey($selection)) {
				$recentPdfPath = $recentPdfMap[$selection]
				if (Test-Path $recentPdfPath) {
					Start-Process $recentPdfPath -ErrorAction Stop
					Write-LogStep "  Opened recent PDF [$selection] from [$recentPdfPath]"
				}
				else {
					Write-LogError "Recent PDF not found at path => [$recentPdfPath]"
					$allSuccessful = $false
					break
				}
			}
			else {
				Write-LogError "Invalid PDF group/selection => [$selection]"
				Write-LogError "Valid options are: $($pdfOptions -join ', ')"
				return
			}
		}

		if ($allSuccessful) {
			Write-LogSuccess "All requested PDFs opened successfully!"
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
