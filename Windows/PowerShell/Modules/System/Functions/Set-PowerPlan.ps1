# List all available plans with => powercfg /list
# Delete duplicates with => powercfg -delete <GUID>
function Set-PowerPlan {
	<#
	.SYNOPSIS
		Sets the Windows power plan to Balanced, HighPerformance, or UltimatePerformance.

	.DESCRIPTION
		With `-Auto`, reads the power plan for the current machine type from
		`PowerPlans[MachineType]` in Configuration.psd1 and applies it.
		Without `-Auto`, accepts a `-Mode` parameter (Balanced, HighPerformance, UltimatePerformance).
		Requires administrator privileges.

	.PARAMETER Auto
		Reads the power plan for the current machine type from configuration.

	.PARAMETER Mode
		Power plan mode: "Balanced", "HighPerformance", or "UltimatePerformance".
		Ignored if `-Auto` is set.

	.EXAMPLE
		Set-PowerPlan -Auto
		Applies the configured power plan for the machine type.

	.EXAMPLE
		Set-PowerPlan -Mode "HighPerformance"
		Sets the power plan to High Performance.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Auto,

		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Balanced", "HighPerformance", "UltimatePerformance")]
		[string]$Mode
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting Performance Mode"

	# --- Resolve mode from configuration, parameter, or interactive selection ---
	if ($Auto) {
		$MachineType = DetermineMachineType
		Write-LogStep " Machine type => [$MachineType]"

		if (-not $PSBoundParameters.ContainsKey('Mode')) {
			$configMode = $Configuration.PowerPlans[$MachineType]

			if ($configMode) {
				$Mode = $configMode
				Write-LogStep " Power plan from configuration => [$Mode]"
			}
			else {
				Write-LogWarning "No configuration found for machine type [$MachineType], defaulting to Balanced!"
				$Mode = "Balanced"
			}
		}
	}
	elseif (-not $Mode) {
		$selection = Resolve-Selection `
			-OptionList @("Balanced", "HighPerformance", "UltimatePerformance") `
			-PromptMessage "Select power plan mode (or press Enter for default => Balanced)" `
			-HideMenuTitle `
			-AllowEmptyPromptResponse:$true

		if ($selection) {
			$Mode = $selection
		}
		else {
			$Mode = "Balanced"
		}
	}

	# --- Map mode names to powercfg match patterns ---
	$modeMatchMap = @{
		"Balanced"            = "Balanced"
		"HighPerformance"     = "High performance"
		"UltimatePerformance" = "Ultimate performance"
	}

	try {
		$activeSchemeOutput = powercfg /getactivescheme
		$matchPattern = $modeMatchMap[$Mode]

		# --- Idempotency check ---
		if ($activeSchemeOutput -match $matchPattern) {
			Write-LogWarning "Power plan already activated => [$matchPattern]"
			return
		}

		Write-LogTitle "Configuring $matchPattern Mode"

		if ($Mode -eq "UltimatePerformance") {
			$allSchemes = powercfg /list
			$perfScheme = $allSchemes | Where-Object { $_ -match "(Ultimate performance|Ultimate Performance)" } | Select-Object -First 1

			if (-not $perfScheme) {
				Write-LogStep " Duplicating Ultimate Performance scheme..."
				powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null

				if ($LASTEXITCODE -ne 0) {
					throw "Failed to duplicate Ultimate Performance scheme"
				}

				$allSchemes = powercfg /list
				$perfScheme = $allSchemes | Where-Object { $_ -match "Ultimate Performance" } | Select-Object -First 1
			}

			if ($perfScheme -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
				powercfg /s $matches[1]

				if ($LASTEXITCODE -ne 0) {
					throw "Failed to activate Ultimate performance mode"
				}
			}
			else {
				throw "Could not find Ultimate Performance scheme GUID"
			}
		}
		elseif ($Mode -eq "HighPerformance") {
			powercfg /s SCHEME_MIN

			if ($LASTEXITCODE -ne 0) {
				throw "Failed to activate High performance mode!"
			}
		}
		elseif ($Mode -eq "Balanced") {
			powercfg /s SCHEME_BALANCED

			if ($LASTEXITCODE -ne 0) {
				throw "Failed to activate Balanced mode!"
			}
		}

		Write-LogSuccess "Performance mode set to [$matchPattern]"
		Write-Host -ForegroundColor Green "`nCurrent active power plan => " -NoNewLine
		powercfg /getactivescheme
	}
	catch {
		Write-LogError " Error => [$($_.Exception.Message)]"
		return
	}
}
