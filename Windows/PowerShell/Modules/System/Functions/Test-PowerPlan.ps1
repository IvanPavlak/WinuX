function Test-PowerPlan {
	<#
	.SYNOPSIS
		Checks if the active power plan is set to the optimal performance mode for the current machine type.

	.DESCRIPTION
		Verifies that the power plan is set to Ultimate Performance for desktop PCs,
		or High Performance for laptops/portables. Uses WMI chassis type detection
		with chassis types defined in Configuration.LaptopChassisTypes.
		Outputs a warning if not optimally configured.

		The chassis type is read from the hardware once and cached in a small file
		(%LOCALAPPDATA%\WinuX\ChassisTypes.txt): the CIM query loads the CimCmdlets module and
		was the largest part of this check's cost on every shell start, and a machine does not
		change its chassis. -Refresh re-reads the hardware and rewrites the cache; a cache that
		cannot be written is simply not used, so the check still works without it.

	.PARAMETER Refresh
		Ignore the cached chassis type, query the hardware again and rewrite the cache.

	.PARAMETER CachePath
		Where the chassis type is cached. Defaults to %LOCALAPPDATA%\WinuX\ChassisTypes.txt.

	.EXAMPLE
		Test-PowerPlan
		Warns when the active plan is not the one this machine should run.

	.EXAMPLE
		Test-PowerPlan -Refresh
		The same check, after re-detecting the chassis type from the hardware.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$Refresh,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CachePath = (Join-Path $env:LOCALAPPDATA "WinuX\ChassisTypes.txt")
	)

	try {
		$activeSchemeOutput = powercfg /getactivescheme

		# Detect if machine is a laptop using WMI chassis type from configuration
		$laptopChassisTypes = @(Get-ConfigSetting -Path 'LaptopChassisTypes' -Default @())
		$chassisTypes = Get-ChassisType -Refresh:$Refresh -CachePath $CachePath
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
