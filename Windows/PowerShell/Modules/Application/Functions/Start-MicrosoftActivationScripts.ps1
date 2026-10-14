function Start-MicrosoftActivationScripts {
	<#
	.SYNOPSIS
		Runs the Microsoft Activation Scripts to activate Windows and Office.

	.DESCRIPTION
		Downloads and runs the Microsoft Activation Scripts (MAS) online activation method
		via `irm https://get.activated.win | iex`.

		Without `-Override`, checks whether Windows is already activated (slmgr.vbs /xpr) and
		whether Office is installed (an Excel.Application entry under
		HKLM:\Software\RegisteredApplications), and returns without prompting when both are true.
		Otherwise it asks a Yes/No question (Enter = No) and runs MAS only on Yes. Use `-Override`
		to skip the check.

		Only called automatically during `Bootstrap -WithInitialSetup` (first-time provisioning),
		and only when BootstrapConfig.Steps.MicrosoftActivationScripts is on (off by default).

	.PARAMETER Selection
		Pre-answers the Yes/No prompt, bypassing it: "Yes" runs MAS, "No" skips.

	.PARAMETER Override
		Forces the activation script to run even if Windows appears to already be activated.

	.EXAMPLE
		Start-MicrosoftActivationScripts
		Checks activation status and asks whether to run MAS unless Windows is activated and Office installed.

	.EXAMPLE
		Start-MicrosoftActivationScripts -Override
		Asks whether to run MAS regardless of current activation status.

	.EXAMPLE
		Start-MicrosoftActivationScripts -Selection Yes
		Runs MAS without prompting (unless Windows is activated and Office installed).
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
