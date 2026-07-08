function Get-EfCurrentDatabaseType {
	<#
	.SYNOPSIS
		Detects the active database provider from a solution's appsettings.

	.DESCRIPTION
		Locates the API/Web/Startup appsettings file (preferring appsettings.Development.json,
		then appsettings.json) and reads the `DatabaseConfiguration` section to determine which
		provider is enabled. Returns "PostgreSQL", "Oracle", "SqlServer", or $null when it cannot
		be determined.

	.PARAMETER SolutionRoot
		Absolute path to the solution root to search for appsettings files.

	.EXAMPLE
		$active = Get-EfCurrentDatabaseType -SolutionRoot "C:\src\MySolution"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$SolutionRoot
	)

	$apiSettingsFile = Get-ChildItem -Path $SolutionRoot -Recurse -Filter "appsettings*.json" -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Directory.Name -match "Api|Web|Startup" } |
		Sort-Object { if ($_.Name -eq "appsettings.Development.json") { 0 } elseif ($_.Name -eq "appsettings.json") { 1 } else { 2 } } |
		Select-Object -First 1

	if (-not $apiSettingsFile) {
		return $null
	}

	try {
		$appsettingsContent = Get-Content -Path $apiSettingsFile.FullName -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
		$dbConfig = $appsettingsContent.DatabaseConfiguration
		if ($dbConfig) {
			if ($dbConfig.UseNpgSql -eq $true) { return "PostgreSQL" }
			elseif ($dbConfig.UseOracle -eq $true) { return "Oracle" }
			elseif ($dbConfig.UseSqlServer -eq $true) { return "SqlServer" }
		}
	}
	catch {
		Write-LogWarning "Could not parse appsettings to detect database type" -NoLeadingNewline
	}

	return $null
}
