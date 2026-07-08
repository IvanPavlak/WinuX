function Find-EfMigrationProjects {
	<#
	.SYNOPSIS
		Discovers EF Core migration projects within a solution.

	.DESCRIPTION
		Identifies migration projects using two patterns:
		1. Dedicated migration projects whose name or directory matches *Migrations*
		   (e.g. Domain.PostgreMigrations, Seup.Domain.SqlServerMigrations).
		2. Legacy layout where a Domain project contains a `Migrations` folder.

		For each candidate it resolves the database type (via Get-DatabaseTypeFromProject),
		locates the ModelSnapshot file, and returns a descriptor object used by the wizard.

		Accepts a pre-enumerated list of .csproj files so the caller can enumerate the solution
		tree once and reuse it across discovery steps.

	.PARAMETER SolutionRoot
		Absolute path to the solution root (used to compute relative project paths).

	.PARAMETER CsprojFiles
		Pre-enumerated collection of *.csproj FileInfo objects from the solution tree.

	.EXAMPLE
		$csproj = Get-ChildItem -Path $root -Recurse -Filter "*.csproj" -File
		$projects = Find-EfMigrationProjects -SolutionRoot $root -CsprojFiles $csproj
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$SolutionRoot,

		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[object[]]$CsprojFiles
	)

	Write-LogStep "  Searching for migration projects..."

	$migrationProjects = @()

	# Pattern 1: Dedicated migration projects (e.g., Domain.PostgreMigrations, Seup.Domain.SqlServerMigrations)
	$dedicatedMigrationProjects = $CsprojFiles |
		Where-Object { $_.Name -match "Migrations?" -or $_.Directory.Name -match "Migrations?" }

	foreach ($proj in $dedicatedMigrationProjects) {
		$projectDir = $proj.Directory
		$snapshotFile = Get-ChildItem -Path $projectDir.FullName -Recurse -Filter "*ModelSnapshot.cs" -File -ErrorAction SilentlyContinue | Select-Object -First 1
		$snapshotContent = if ($snapshotFile) { Get-Content -Path $snapshotFile.FullName -Raw -ErrorAction SilentlyContinue } else { $null }

		$dbType = Get-DatabaseTypeFromProject -projectName $proj.BaseName -projectPath $projectDir.FullName -snapshotContent $snapshotContent

		$migrationProjects += [PSCustomObject]@{
			Name                = $proj.BaseName
			Path                = $projectDir.FullName
			ProjectFile         = $proj.FullName
			DbType              = $dbType
			HasMigrations       = $null -ne $snapshotFile
			SnapshotFile        = $snapshotFile
			RelativePath        = $projectDir.FullName.Replace("$SolutionRoot\", "")
			MigrationsSubfolder = $null
			IsDedicatedProject  = $true
		}
	}

	# Pattern 2: Legacy structure (migrations folder inside Domain project)
	$domainProjects = $CsprojFiles |
		Where-Object { $_.Name -match "Domain" -and $_.Name -notmatch "Migrations" }

	foreach ($domainProject in $domainProjects) {
		$migrationsFolder = Get-ChildItem -Path $domainProject.Directory.FullName -Recurse -Directory -Filter "Migrations" -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($migrationsFolder) {
			$snapshotFile = Get-ChildItem -Path $migrationsFolder.FullName -Filter "*ModelSnapshot.cs" -File -ErrorAction SilentlyContinue | Select-Object -First 1

			# Only add if not already covered by a dedicated migrations project
			$alreadyCovered = $migrationProjects | Where-Object {
				$_.Path -eq $domainProject.Directory.FullName -or
				$_.SnapshotFile.FullName -eq $snapshotFile.FullName
			}

			if ($snapshotFile -and -not $alreadyCovered) {
				$snapshotContent = Get-Content -Path $snapshotFile.FullName -Raw -ErrorAction SilentlyContinue
				$dbType = Get-DatabaseTypeFromProject -projectName $domainProject.BaseName -projectPath $migrationsFolder.FullName -snapshotContent $snapshotContent

				$migrationProjects += [PSCustomObject]@{
					Name                = "$($domainProject.BaseName) (Legacy)"
					Path                = $domainProject.Directory.FullName
					ProjectFile         = $domainProject.FullName
					DbType              = $dbType
					HasMigrations       = $true
					SnapshotFile        = $snapshotFile
					RelativePath        = $domainProject.Directory.FullName.Replace("$SolutionRoot\", "")
					MigrationsSubfolder = $migrationsFolder.FullName.Replace($domainProject.Directory.FullName, "").TrimStart('\', '/')
					IsDedicatedProject  = $false
				}
			}
		}
	}

	return $migrationProjects
}
