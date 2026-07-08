function Resolve-EfMigrationDbContext {
	<#
	.SYNOPSIS
		Resolves which DbContext (if any) to pass to dotnet ef migration commands.

	.DESCRIPTION
		Determines the DbContext name and whether an explicit `--context` flag is required.

		Fast path: a migrations assembly has exactly one `*ModelSnapshot.cs` per DbContext, so a
		single snapshot means a single context. In that case dotnet ef resolves the context without
		`--context`, so this function returns immediately - skipping both the project-wide source
		scan (Get-DbContextsFromProject) and the design-time build (Get-EfCoreDbContexts /
		`dotnet ef dbcontext list`). This is the common case and avoids a multi-second build.

		Fallback path (zero or multiple snapshots = ambiguous/absent): scans the migration and
		startup project sources for DbContext classes and then uses `dotnet ef dbcontext list` as
		the authority, prompting the user when more than one context is present.

	.PARAMETER MigrationProject
		Selected migration-project descriptor (from Find-EfMigrationProjects). Uses .Path and
		.SnapshotFile.

	.PARAMETER StartupProjectDirectory
		Full path to the startup project directory (for source-scan disambiguation). Optional.

	.PARAMETER MigrationsProjectPath
		Relative migrations project path passed to dotnet ef (--project).

	.PARAMETER StartupProjectPath
		Relative startup project path passed to dotnet ef (--startup-project). Optional.

	.PARAMETER SolutionRoot
		Working directory for the dotnet ef invocation (solution root).

	.OUTPUTS
		Hashtable with keys: ContextName (string or $null) and UseExplicitContext (bool).

	.EXAMPLE
		$ctx = Resolve-EfMigrationDbContext -MigrationProject $proj -StartupProjectDirectory $dir `
			-MigrationsProjectPath "src\Domain.PostgreMigrations" -StartupProjectPath "src\Api" -SolutionRoot $root
	#>
	param(
		[Parameter(Mandatory = $true)]
		[object]$MigrationProject,

		[Parameter(Mandatory = $false)]
		[string]$StartupProjectDirectory,

		[Parameter(Mandatory = $true)]
		[string]$MigrationsProjectPath,

		[Parameter(Mandatory = $false)]
		[string]$StartupProjectPath,

		[Parameter(Mandatory = $true)]
		[string]$SolutionRoot
	)

	$contextName = $null
	$useExplicitContext = $false

	# Fast path: a single ModelSnapshot means a single DbContext. dotnet ef resolves a lone
	# context without --context, so skip the source scan and the design-time build entirely.
	$snapshotFiles = @()
	if ($MigrationProject.Path -and (Test-Path -Path $MigrationProject.Path -PathType Container)) {
		$snapshotFiles = @(Get-ChildItem -Path $MigrationProject.Path -Recurse -Filter "*ModelSnapshot.cs" -File -ErrorAction SilentlyContinue)
	}

	if ($snapshotFiles.Count -eq 1) {
		$snapshotContext = Get-DbContextFromSnapshot -SnapshotPath $snapshotFiles[0].FullName
		if ($snapshotContext) {
			$contextName = $snapshotContext.Split('.')[-1]
		}
		Write-LogStep "  Single DbContext detected => skipping design-time discovery (running without --context)" -NoLeadingNewline
		return @{ ContextName = $contextName; UseExplicitContext = $false }
	}

	# Fallback path: ambiguous (multiple) or absent snapshots - fall back to full discovery.
	# The snapshot context name was already displayed by the caller; here we only resolve it.
	if ($MigrationProject.SnapshotFile) {
		$contextName = Get-DbContextFromSnapshot -SnapshotPath $MigrationProject.SnapshotFile.FullName
	}

	# Validate/resolve DbContext against actual project sources
	$discoveredContexts = @()
	$discoveredContexts += @(Get-DbContextsFromProject -ProjectPath $MigrationProject.Path)
	if ($StartupProjectDirectory -and $StartupProjectDirectory -ne $MigrationProject.Path) {
		$discoveredContexts += @(Get-DbContextsFromProject -ProjectPath $StartupProjectDirectory)
	}
	$discoveredContexts = @($discoveredContexts | Where-Object { $_ } | Sort-Object -Unique)

	if ($discoveredContexts.Count -gt 0) {
		$candidateSimpleNames = @($discoveredContexts | ForEach-Object { $_.Split('.')[-1] } | Sort-Object -Unique)

		if ($contextName) {
			$contextSimpleName = $contextName.Split('.')[-1]
			if ($candidateSimpleNames -notcontains $contextSimpleName) {
				Write-Host -ForegroundColor Yellow "  => Snapshot DbContext [$contextName] is not present in project sources."

				if ($candidateSimpleNames.Count -eq 1) {
					$contextName = $candidateSimpleNames[0]
					Write-Host -ForegroundColor Green "  => Using discovered DbContext => [$contextName]"
				}
				else {
					$contextChoice = Resolve-Selection -OptionList $candidateSimpleNames -MenuTitle "[Select DbContext]" -PromptMessage "Choose DbContext"
					if ($contextChoice) {
						$contextName = $contextChoice
						Write-Host -ForegroundColor Green "  => Selected DbContext => [$contextName]"
					}
					else {
						$contextName = $null
						Write-Host -ForegroundColor Yellow "  => No DbContext selected. Commands will run without --context."
					}
				}
			}
			else {
				$contextName = $contextSimpleName
			}
		}
		elseif ($candidateSimpleNames.Count -eq 1) {
			$contextName = $candidateSimpleNames[0]
			Write-LogStep "  Auto-detected DbContext => [$contextName]" -NoLeadingNewline
		}

		# Prefer running without --context when DbContext is unambiguous.
		if ($candidateSimpleNames.Count -gt 1 -and $contextName) {
			$useExplicitContext = $true
		}
	}

	# Final DbContext validation from dotnet ef design-time discovery
	if ($StartupProjectPath) {
		$cliContexts = Get-EfCoreDbContexts -ProjectPath $MigrationsProjectPath -StartupProjectPath $StartupProjectPath -WorkingDirectory $SolutionRoot
		$cliSimpleNames = @($cliContexts | ForEach-Object { $_.Split('.')[-1] } | Sort-Object -Unique)

		if ($cliSimpleNames.Count -gt 0) {
			Write-LogStep "  EF CLI contexts => [$($cliSimpleNames -join ', ')]" -NoLeadingNewline

			if ($cliSimpleNames.Count -eq 1) {
				$contextName = $cliSimpleNames[0]
				$useExplicitContext = $false
				Write-LogStep "  Using EF CLI detected context => [$contextName] (without --context)" -NoLeadingNewline
			}
			else {
				$chosenContext = $contextName
				if (-not $chosenContext -or ($cliSimpleNames -notcontains $chosenContext.Split('.')[-1])) {
					$chosenContext = Resolve-Selection -OptionList $cliSimpleNames -MenuTitle "[Select DbContext]" -PromptMessage "Choose DbContext"
				}

				if ($chosenContext) {
					$contextName = $chosenContext.Split('.')[-1]
					$useExplicitContext = $true
					Write-Host -ForegroundColor Green "  => Selected EF CLI context => [$contextName]"
				}
				else {
					$contextName = $null
					$useExplicitContext = $false
					Write-Host -ForegroundColor Yellow "  => No DbContext selected. Commands will run without --context."
				}
			}
		}
	}

	return @{ ContextName = $contextName; UseExplicitContext = $useExplicitContext }
}
