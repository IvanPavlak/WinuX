function Get-EfMigrations {
	<#
	.SYNOPSIS
		Lists the migration files in a migrations folder, ordered chronologically.

	.DESCRIPTION
		Returns the migration `.cs` files in the given folder (excluding the generated
		`*.Designer.cs` and `*Snapshot.cs` files), sorted by name. Because EF Core migration
		files are timestamp-prefixed, name order is chronological order. Returns an empty array
		when the folder is missing or contains no migrations.

	.PARAMETER MigrationFolderPath
		Full path to the folder that holds the migration files.

	.EXAMPLE
		$migrations = Get-EfMigrations -MigrationFolderPath "C:\src\Domain.PostgreMigrations\Migrations"
		$last = $migrations[-1]
	#>
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$MigrationFolderPath
	)

	if (-not $MigrationFolderPath -or -not (Test-Path -Path $MigrationFolderPath)) {
		return @()
	}

	# Wrap the pipeline in @() so an empty result is a 0-length array, not @($null).
	$migrations = @(
		Get-ChildItem -Path $MigrationFolderPath -Filter "*.cs" -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -notlike "*.Designer.cs" -and $_.Name -notlike "*Snapshot.cs" } |
			Sort-Object Name
	)

	return $migrations
}
