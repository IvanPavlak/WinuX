# Add to docs and readme
function Get-DbContextFromSnapshot {
	<#
	.SYNOPSIS
		Extracts the DbContext class name from a ModelSnapshot file.

	.DESCRIPTION
		Parses an EF Core ModelSnapshot .cs file to find the DbContext type attribute.
		Returns the class name used in the DbContext attribute so it can be passed to
		dotnet ef via --context.

	.PARAMETER SnapshotPath
		Full path to the *ModelSnapshot.cs file.

	.EXAMPLE
		Get-DbContextFromSnapshot -SnapshotPath "C:\src\Migrations\AppDbContextModelSnapshot.cs"
		Returns "AppDbContext" or $null if detection fails.
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$SnapshotPath
	)

	if (-not (Test-Path $SnapshotPath)) { return $null }

	$snapshotContent = Get-Content -Path $SnapshotPath -Raw -ErrorAction SilentlyContinue
	if (-not $snapshotContent) { return $null }

	if ($snapshotContent -match '\[DbContext\(typeof\(([^)]+)\)\)\]') {
		$contextName = $matches[1]

		# dotnet ef resolves DbContext names more reliably with simple class names.
		if ($contextName -match '\.') {
			$contextName = $contextName.Split('.')[-1]
		}

		return $contextName
	}

	return $null
}
