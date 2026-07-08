function Open-VisualStudio {
	<#
	.SYNOPSIS
		Opens a Visual Studio solution from the configured solution list.

	.DESCRIPTION
		Opens one or more solutions configured in `VisualStudioSolutions` in Configuration.psd1.
		Each entry maps a name to a `.sln` file path. If a solution is already open (detected
		by matching window title), it is skipped.

		When `-Solution` is omitted, shows an interactive selection menu.
		When `-Default` is specified, opens the first solution in the list.

	.PARAMETER Default
		Opens the first solution defined in VisualStudioSolutions without showing a menu.

	.PARAMETER Solution
		One or more solution names as defined in the `VisualStudioSolutions` configuration.
		Omit to show the interactive selection menu.

	.EXAMPLE
		Open-VisualStudio
		Shows the solution selection menu.

	.EXAMPLE
		Open-VisualStudio -Solution "MyApp"
		Opens the MyApp solution.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$Default,

		[Parameter()]
		[string[]]$Solution
	)

	$vsSolutions = $Configuration.VisualStudioSolutions
	$vsExecutablePath = $Configuration.Universal.VisualStudio2026Exe

	if (-not $vsSolutions) {
		Write-LogError "VisualStudioSolutions not found in configuration!"
		return
	}

	# Build lookup hashtable from ordered array
	$vsSolutionMappings = @{}
	foreach ($entry in $vsSolutions) { $vsSolutionMappings[$entry.Name] = $entry.Solution }

	if (-not $vsExecutablePath) {
		Write-LogError "Visual Studio executable path not found in configuration!"
		return
	}

	if ([string]::IsNullOrWhiteSpace($vsExecutablePath) -or -not (Test-Path $vsExecutablePath)) {
		Write-LogError "Visual Studio executable not found at resolved path => [$vsExecutablePath]"
		return
	}

	$resolveParams = @{
		InputObject              = $Solution
		OptionList               = $vsSolutions.Name
		MenuTitle                = "[Available Solutions]"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}


	if (-not $Default) {
		$solutions = Resolve-Selection @resolveParams
	}

	try {
		if (-not $solutions) {
			Write-LogStep "Opening Visual Studio..."

			if (-not (Get-Process -Name "devenv" -ErrorAction SilentlyContinue)) {
				Start-Process -FilePath $vsExecutablePath -NoNewWindow -ErrorAction Stop
				Write-LogSuccess "Visual Studio opened!"
			}
			else {
				Write-LogWarning "Visual Studio is already running!"
			}
		}
		else {
			foreach ($sol in $solutions) {
				if ($vsSolutionMappings.ContainsKey($sol)) {
					$solutionPathString = $vsSolutionMappings[$sol]
					$solutionPath = $null
					try {
						$solutionPath = Invoke-Command -ScriptBlock ([scriptblock]::Create("`$global:MachineSpecificPaths.$solutionPathString"))
					}
					catch {
						Write-LogError "Could not resolve path for solution [$sol] using path string [$solutionPathString]!"
						continue
					}

					if ([string]::IsNullOrWhiteSpace($solutionPath) -or -not (Test-Path $solutionPath)) {
						Write-LogError "Solution file not found for [$sol] at resolved path: [$solutionPath]!"
						continue
					}

					$solutionFileName = Split-Path -Leaf $solutionPath
					$solutionNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($solutionFileName)

					Write-LogStep "Opening Visual Studio with project [$sol]..."

					$alreadyOpen = Test-ProjectAlreadyOpen -ProjectName $solutionNameWithoutExt -ProcessName "devenv" -ApplicationName "Visual Studio"

					if (-not $alreadyOpen) {
						Start-Process -FilePath $vsExecutablePath -ArgumentList $solutionPath -NoNewWindow -ErrorAction Stop
						Write-LogSuccess "Opened project [$sol] in Visual Studio!"
					}
				}
				else {
					Write-LogError "Error: Mapping for solution [$sol] not found in VisualStudioSolutions!"
				}
			}
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)"
	}
}
