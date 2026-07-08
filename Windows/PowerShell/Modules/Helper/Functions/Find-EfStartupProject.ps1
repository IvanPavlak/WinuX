function Find-EfStartupProject {
	<#
	.SYNOPSIS
		Resolves the best EF Core startup project for migration commands.

	.DESCRIPTION
		Selects a startup project (the one passed to `dotnet ef --startup-project`) from the
		solution's API/Web/Startup projects, using a layered strategy:
		1. An *.Api.* / *Api project that references EF Core Design.
		2. Any API/Web/Startup project that references EF Core Design.
		3. If none qualify but the migrations project has Design, use the migrations project.
		4. Last resort: any API/Web/Startup project, even without Design (with a warning).

		Accepts a pre-enumerated list of .csproj files so the solution tree is only walked once.

	.PARAMETER SolutionRoot
		Absolute path to the solution root (used to compute the relative startup path).

	.PARAMETER CsprojFiles
		Pre-enumerated collection of *.csproj FileInfo objects from the solution tree.

	.PARAMETER MigrationsProjectPath
		Relative path of the selected migrations project (fallback startup when it has Design).

	.PARAMETER MigrationsProjectFile
		Full path to the migrations .csproj (checked for the EF Core Design package).

	.OUTPUTS
		Hashtable with keys: StartupProject (FileInfo or $null) and StartupProjectPath
		(relative path string or $null).

	.EXAMPLE
		$startup = Find-EfStartupProject -SolutionRoot $root -CsprojFiles $csproj `
			-MigrationsProjectPath "src\Domain.PostgreMigrations" -MigrationsProjectFile $projFile
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$SolutionRoot,

		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[object[]]$CsprojFiles,

		[Parameter(Mandatory = $true)]
		[string]$MigrationsProjectPath,

		[Parameter(Mandatory = $true)]
		[string]$MigrationsProjectFile
	)

	Write-LogStep "  Searching for startup project..."

	$migrationsHasDesign = Test-HasEfCoreDesign $MigrationsProjectFile

	$potentialStartupProjects = $CsprojFiles |
		Where-Object {
			$_.Name -match "(\.Api\.|\.Web\.|\.WebApi\.|\.Startup\.)" -or
			$_.BaseName -match "(Api|Web|WebApi|Startup)$"
		}

	$startupProject = $null
	$startupProjectPath = $null

	if ($potentialStartupProjects) {
		# Strategy 1: Prefer API projects with EF Core Design
		$startupProject = $potentialStartupProjects |
			Where-Object { ($_.Name -match "\.Api\." -or $_.BaseName -match "Api$") -and (Test-HasEfCoreDesign $_.FullName) } |
			Select-Object -First 1

		# Strategy 2: Try any API/Web project with EF Core Design
		if (-not $startupProject) {
			$startupProject = $potentialStartupProjects | Where-Object { Test-HasEfCoreDesign $_.FullName } | Select-Object -First 1
		}

		# Strategy 3: If migrations project has Design, prefer it over API projects without Design
		if (-not $startupProject -and $migrationsHasDesign) {
			Write-LogWarning "No API/Web project with EF Core Design found." -NoLeadingNewline
			Write-LogWarning "Using migrations project as startup (has EF Core Design)" -NoLeadingNewline
			$startupProjectPath = $MigrationsProjectPath
		}

		# Strategy 4: Fall back to any API/Web project even without Design package (last resort)
		if (-not $startupProject -and -not $startupProjectPath) {
			$startupProject = $potentialStartupProjects | Select-Object -First 1
			if ($startupProject) {
				Write-LogWarning "Warning: Selected API project doesn't have EF Core Design package" -NoLeadingNewline
			}
		}
	}

	if ($startupProject) {
		$startupProjectPath = $startupProject.Directory.FullName.Replace("$SolutionRoot\", "")
		Write-LogSuccess "Found startup project => [$($startupProject.BaseName)]" -NoLeadingNewline
		Write-LogStep "  Startup project path => [$startupProjectPath]" -NoLeadingNewline

		$hasDesign = Test-HasEfCoreDesign $startupProject.FullName
		if ($hasDesign) {
			Write-LogSuccess "     Has EF Core Design package" -NoLeadingNewline
		}
		else {
			Write-LogWarning "     Missing EF Core Design package (commands may fail)" -NoLeadingNewline
		}
	}
	elseif (-not $startupProjectPath -and $migrationsHasDesign) {
		$startupProjectPath = $MigrationsProjectPath
		Write-LogWarning "Using migrations project as startup project (has EF Core Design)" -NoLeadingNewline
	}

	if (-not $startupProjectPath) {
		Write-LogError "No suitable startup project found. Commands will likely fail!" -NoLeadingNewline
		Write-LogWarning "     Consider adding Microsoft.EntityFrameworkCore.Design to your API or migrations project." -NoLeadingNewline
	}

	return @{
		StartupProject     = $startupProject
		StartupProjectPath = $startupProjectPath
	}
}
