function Test-WSLDistributionInstalled {
	<#
	.SYNOPSIS
		Tests if the configured WSL distribution is installed.

	.DESCRIPTION
		Checks if the WSL distribution specified in Configuration.psd1 (DefaultWSLDistribution)
		is installed on the system.

	.EXAMPLE
		Test-WSLDistributionInstalled
		Returns $true if the configured distribution is installed, $false otherwise.
	#>

	try {
		$distroName = $Configuration.DefaultWSLDistribution
		if (-not $distroName) {
			Write-LogError "DefaultWSLDistribution not found in Configuration"
			return $false
		}

		# Get list of installed distributions
		$distributions = @(wsl -l)

		# Check each distribution
		for ($i = 1; $i -lt $distributions.Length; $i++) {
			$line = $distributions[$i].Trim()

			# Match the distribution name (with or without "(Default)" marker)
			if ($line -eq $distroName -or
				$line -eq "$distroName (Default)" -or
				$line -match "^$distroName\s+\(Default\)") {
				return $true
			}
		}

		return $false
	}
	catch {
		Write-LogError "Error checking WSL distribution installation: $_"
		Write-LogError "Exception details: $($_.Exception.Message)"
		return $false
	}
}
