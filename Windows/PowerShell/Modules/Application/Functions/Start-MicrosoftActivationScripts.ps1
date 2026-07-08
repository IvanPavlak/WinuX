function Start-MicrosoftActivationScripts {
	<#
	.SYNOPSIS
		Runs the Microsoft Activation Scripts to activate Windows and Office.

	.DESCRIPTION
		Downloads and runs the Microsoft Activation Scripts (MAS) online activation method
		via `irm https://get.activated.win | iex`.

		With no arguments and `-Override` not set, checks whether Windows is already
		activated and skips if it is. Use `-Override` to force re-activation.

		Only called automatically during `Bootstrap -WithInitialSetup` (first-time provisioning).

	.PARAMETER Selection
		Pre-selects the activation method by name, bypassing the interactive menu.

	.PARAMETER Override
		Forces the activation script to run even if Windows appears to already be activated.

	.EXAMPLE
		Start-MicrosoftActivationScripts
		Checks activation status and runs MAS if Windows is not activated.

	.EXAMPLE
		Start-MicrosoftActivationScripts -Override
		Runs MAS regardless of current activation status.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Selection,

		[Parameter()]
		[switch]$Override
	)

	Write-LogTitle "Microsoft-Activation-Scripts"

	try {
		if (-not $Override) {
			$windowsActivated = $false
			$slmgrOutput = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr 2>&1 | Out-String

			if ($slmgrOutput -match "permanently activated|activated until") {
				$windowsActivated = $true
				Write-LogWarning "Windows is already activated!"
			}

			$officeInstalled = $false
			$registeredApps = Get-ItemProperty -Path "HKLM:\Software\RegisteredApplications" -ErrorAction SilentlyContinue
			if ($registeredApps) {
				$officeProduct = $registeredApps.PSObject.Properties.Name | Where-Object { $_ -match "Excel\.Application\." } | Select-Object -First 1
				if ($officeProduct) {
					$officeInstalled = $true
					$officeVersion = ($officeProduct -replace "Excel\.Application\.", "") + ".0"
					Write-LogWarning "Office version [$officeVersion] is already installed!" -NoLeadingNewline
				}
			}

			if ($windowsActivated -and $officeInstalled) {
				return
			}
		}

		$resolveParams = @{
			InputObject              = $Selection
			PromptMessage            = "Do you want to activate Windows and/or install Office with Microsoft Activation Scripts? (Press Enter for default => No)"
			HideMenuTitle            = $true
			AllowEmptyPromptResponse = $true
		}

		$resolvedSelection = Resolve-Selection @resolveParams

		if ($null -eq $resolvedSelection -or $resolvedSelection -eq "No") {
			Write-LogWarning "Windows Activation skipped!"
			return
		}
		elseif ($resolvedSelection -eq "Yes") {
			Invoke-RestMethod https://get.activated.win | Invoke-Expression
			Write-LogSuccess "Windows Activation completed"
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
