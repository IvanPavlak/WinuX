function Get-DatabaseTypeFromProject {
	<#
	.SYNOPSIS
		Detect database type from .NET project metadata.

	.DESCRIPTION
		Analyzes project name, path, and/or EF Core snapshot to identify database type.
		Supports PostgreSQL, Oracle, SQL Server, and Unknown.

	.PARAMETER projectName
		Name of the project to analyze (contains database hints like 'Postgre', 'Oracle').

	.PARAMETER projectPath
		Path to project file (fallback for database hints).

	.PARAMETER snapshotContent
		EF Core ModelSnapshot file content for definitive type detection.

	.EXAMPLE
		$dbType = Get-DatabaseTypeFromProject -projectName "MyApp.Data.Postgres" -snapshotContent $snapshot
		Write-Host "Database: $dbType"  # Output: PostgreSQL
	#>
	param(
		[string]$projectName,
		[string]$projectPath,
		[string]$snapshotContent
	)

	if ($projectName -match "Postgre|NpgSql|Npgsql" -or $projectPath -match "Postgre|NpgSql|Npgsql") {
		return "PostgreSQL"
	}
	elseif ($projectName -match "Oracle" -or $projectPath -match "Oracle") {
		return "Oracle"
	}
	elseif ($projectName -match "SqlServer|MsSql" -or $projectPath -match "SqlServer|MsSql") {
		return "SqlServer"
	}
	elseif ($snapshotContent) {
		if ($snapshotContent -match "Npgsql|PostgreSQL") { return "PostgreSQL" }
		elseif ($snapshotContent -match "Oracle") { return "Oracle" }
		elseif ($snapshotContent -match "SqlServer") { return "SqlServer" }
	}
	return "Unknown"
}
