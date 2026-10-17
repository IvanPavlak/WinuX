function Open-VSCode {
	<#
	.SYNOPSIS
		Opens a VS Code folder from the configured project list.

	.DESCRIPTION
		Opens one or more folder paths configured in `VSCodeProjects` in Configuration.psd1.
		Each entry maps a Name to a Path, a dot-notation reference into
		$global:MachineSpecificPaths (e.g. "Projects.Self.Root"). If a VS Code window for that
		folder is already open (detected by matching window title), it is skipped.

		When `-Folder` is omitted, shows an interactive selection menu. When nothing is selected,
		or `-Default` is specified, VS Code is launched without a folder (skipped if it is
		already running).

		VS Code is started through Start-VSCodeDetached, so it owns no console and never keeps the
		terminal tab open after a workspace closes its own tab.

	.PARAMETER Default
		Skips the menu (and ignores -Folder) and launches VS Code without a folder, unless a Code
		process is already running.

	.PARAMETER Folder
		One or more project names as defined in the `VSCodeProjects` configuration.
		Omit to show the interactive selection menu.

	.EXAMPLE
		Open-VSCode
		Shows the project selection menu.

	.EXAMPLE
		Open-VSCode -Folder "MyApp"
		Opens the MyApp project folder in VS Code.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$Default,

		[Parameter()]
		[string[]]$Folder
	)

	$vsCodeProjects = @(Get-ConfigSetting -Path 'VSCodeProjects' -Default @())
	if (-not $vsCodeProjects) {
		Write-LogError "Error: VSCodeProjects not found in configuration!"
		return
	}

	# Build lookup hashtable from ordered array
	$vsCodeMappings = @{}
	foreach ($entry in $vsCodeProjects) { $vsCodeMappings[$entry.Name] = $entry.Path }

	$resolveParams = @{
		InputObject              = $Folder
		OptionList               = $vsCodeProjects.Name
		MenuTitle                = "[Available VSCode Folders]"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}


	if (-not $Default) {
		$folders = Resolve-Selection @resolveParams
	}

	try {
		if (-not $folders) {
			Write-LogStep "Opening VSCode..."

			if (-not (Get-Process -Name "Code" -ErrorAction SilentlyContinue)) {
				Start-VSCodeDetached
				Write-LogSuccess "VSCode opened!"
			}
			else {
				Write-LogWarning "VSCode is already running!"
			}
		}
		else {
			foreach ($f in $folders) {
				if ($vsCodeMappings.ContainsKey($f)) {
					$folderPathString = $vsCodeMappings[$f]
					$folderPath = $null
					try {
						$folderPath = Invoke-Command -ScriptBlock ([scriptblock]::Create("`$global:MachineSpecificPaths.$folderPathString"))
					}
					catch {
						Write-LogError "Could not resolve path for folder [$f] using path string [$folderPathString]!"
						continue
					}

					if ([string]::IsNullOrWhiteSpace($folderPath) -or -not (Test-Path $folderPath)) {
						Write-LogError "Folder path not found for [$f] at resolved path: [$folderPath]!"
						continue
					}

					$folderName = Split-Path -Leaf $folderPath

					Write-LogStep "Opening VSCode with project [$f]..."

					$alreadyOpen = Test-ProjectAlreadyOpen -ProjectName $folderName -ProcessName "Code" -ApplicationName "VSCode"

					if (-not $alreadyOpen) {
						Start-VSCodeDetached -ArgumentList "-n", "`"$folderPath`""
						Write-LogSuccess "Opened project [$f] in VSCode!"
					}
				}
				else {
					Write-LogError "Error: Mapping for project [$f] not found in VSCodeProjects!"
				}
			}
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)"
	}
}
