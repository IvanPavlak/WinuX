function Test-PowerPlan {
	<#
    .SYNOPSIS
        Checks if the active power plan is set to the optimal performance mode for the current machine type.

    .DESCRIPTION
        Verifies that the power plan is set to Ultimate Performance for desktop PCs,
        or High Performance for laptops/portables. Uses WMI chassis type detection
        with chassis types defined in Configuration.LaptopChassisTypes.
        Outputs a warning if not optimally configured.
    #>

	try {
		$activeSchemeOutput = powercfg /getactivescheme

		# Detect if machine is a laptop using WMI chassis type from configuration
		$laptopChassisTypes = $global:Configuration.LaptopChassisTypes
		$chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
		$isLaptop = $chassisTypes | Where-Object { $laptopChassisTypes -contains $_ }

		if ($isLaptop) {
			# Laptop should use High Performance
			if ($activeSchemeOutput -notmatch "High performance") {
				Write-LogWarning " [Power Plan] Not set to High Performance - run [Set-PowerPlan -Auto] to fix!" -BlankLineAfter
			}
		}
		else {
			# Desktop PC should use Ultimate Performance
			if ($activeSchemeOutput -notmatch "Ultimate performance") {
				Write-LogWarning " [Power Plan] Not set to Ultimate Performance - run [Set-PowerPlan -Auto] to fix!" -BlankLineAfter
			}
		}
	}
	catch {
		Write-LogError " [Power Plan] Failed to check power plan: $_"
	}
}
