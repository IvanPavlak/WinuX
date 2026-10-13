function Open-VisualStudio {
	<#
	.SYNOPSIS
		Opens a Visual Studio solution from the configured solution list.

	.DESCRIPTION
		Opens one or more solutions configured in `VisualStudioSolutions` in Configuration.psd1.
		Each entry maps a Name to a Solution, a dot-notation reference into
		$global:MachineSpecificPaths (e.g. "Projects.MyProject.Solution") that resolves to a
		`.sln` file. If a solution is already open (detected by matching window title), it is
		skipped. The executable is `Universal.VisualStudio2026Exe`, which must be set and exist.

		When `-Solution` is omitted, shows an interactive selection menu. When nothing is
		selected, or `-Default` is specified, Visual Studio is launched without a solution
		(skipped if it is already running).

	.PARAMETER Default
		Skips the menu (and ignores -Solution) and launches Visual Studio without a solution,
		unless a devenv process is already running.

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

	$vsSolutions = @(Get-ConfigSetting -Path 'VisualStudioSolutions' -Default @())
	$vsExecutablePath = Get-ConfigSetting -Path 'Universal.VisualStudio2026Exe'

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
