function Restart-Machine {
	<#
    .SYNOPSIS
        Prompts for confirmation and restarts the machine.

    .DESCRIPTION
        Shows a Yes/No confirmation prompt via Resolve-Selection.
        If confirmed, displays a 5-second countdown then calls `Restart-Computer`.

    .PARAMETER Selection
        Pre-selected answer ("Yes" or "No") to skip the interactive prompt.

    .EXAMPLE
        Restart-Machine
        Shows the confirmation prompt.

    .EXAMPLE
        Restart-Machine -Selection "Yes"
        Restarts immediately without prompting.
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Selection
	)

	try {
		$resolveParams = @{
			InputObject              = $Selection
			MenuTitle                = "[Restart Machine]"
			PromptMessage            = "Do you want to restart the machine? (Press Enter for default => No)"
			AllowEmptyPromptResponse = $true
		}

		$resolvedSelection = Resolve-Selection @resolveParams

		if ($resolvedSelection -eq "Yes") {
			Write-LogStep "Machine will restart in:"
			Countdown -Seconds 5
			Restart-Computer
		}
		elseif ($resolvedSelection -eq "No" -or $null -eq $resolvedSelection) {
			Write-LogError "Restart cancelled"
		}
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
