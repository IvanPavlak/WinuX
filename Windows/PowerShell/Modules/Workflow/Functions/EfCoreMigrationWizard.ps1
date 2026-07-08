function EfCoreMigrationWizard {
	<#
	.SYNOPSIS
		Interactive EF Core migration manager - add, remove, redo, squash, and sync migrations.

	.DESCRIPTION
		Menu-driven wizard for managing Entity Framework Core migrations in a .NET solution.
		Searches upward and downward from the current directory to locate the nearest .sln file,
		then discovers migration projects (dedicated `*.Migrations` csproj files or any project
		containing a `*ModelSnapshot.cs` file).

		Discovery is delegated to focused helpers in the Helper module:
		- Find-EfMigrationProjects   - locates dedicated and legacy migration projects
		- Get-EfCurrentDatabaseType  - reads the active provider from appsettings
		- Find-EfStartupProject      - picks the startup project for dotnet ef
		- Resolve-EfMigrationDbContext - resolves the DbContext / --context decision
		- Get-EfMigrations           - lists migration files in chronological order

		DbContext resolution is optimized for the common case: when a migrations project has a
		single ModelSnapshot (i.e. a single DbContext), commands run without --context and the
		slow `dotnet ef dbcontext list` design-time build is skipped. Ambiguous/absent cases fall
		back to a source scan plus design-time discovery.

		Menu options:
		- Add migration - prompts for name, calls `dotnet ef migrations add`
		- Remove last migration - calls `dotnet ef migrations remove`
		- Redo last migration - removes then re-adds with the same name
		- Squash all migrations - removes all and adds a single "initial-migration"
		- Sync to database - calls `dotnet ef database update`
		Alias: efm

	.EXAMPLE
		EfCoreMigrationWizard
		Opens the migration wizard in the context of the nearest solution file.
	#>
	Write-LogTitle "EF Core Migration Wizard"

	# Find solution root
	$solutionFile = Find-Item -Pattern "*.sln" -SearchTarget "File" -MaxDownwardDepth 5 -MaxUpwardDepth 5 -SearchMessage "[Searching for solution file]" -SuccessMessage "Found solution [{0}] at [{1}]"

	if (-not $solutionFile) {
		Write-LogError "No solution file found!"
		return
	}

	$solutionRoot = $solutionFile.Path

	# Enumerate the solution's project files once and reuse across discovery steps.
	$allCsproj = @(Get-ChildItem -Path $solutionRoot -Recurse -Filter "*.csproj" -File -ErrorAction SilentlyContinue)

	# Discover migration projects (dedicated + legacy patterns)
	$migrationProjects = @(Find-EfMigrationProjects -SolutionRoot $solutionRoot -CsprojFiles $allCsproj)

	if (-not $migrationProjects -or $migrationProjects.Count -eq 0) {
		Write-LogError "No migration projects found!"
		Write-LogWarning "Looking for projects matching *Migrations* or Domain projects with Migrations folder." -NoLeadingNewline
		return
	}

	# Detect current database configuration from appsettings
	$currentDbType = Get-EfCurrentDatabaseType -SolutionRoot $solutionRoot

	if ($currentDbType) {
		Write-LogSuccess "Current database configuration: [$currentDbType]"
	}

	# Display found migration projects
	Write-LogStep "  Found $($migrationProjects.Count) migration project(s):`n"
	foreach ($proj in $migrationProjects) {
		$status = if ($proj.HasMigrations) { "Has migrations" } else { "Empty" }
		$current = if ($proj.DbType -eq $currentDbType) { " [ACTIVE]" } else { "" }
		$color = if ($proj.DbType -eq $currentDbType) { "Green" } else { "Gray" }
		Write-Host -ForegroundColor $color "    $($proj.DbType.PadRight(12)) => $($proj.Name) ($status)$current"
	}

	# Select migration project
	$selectedMigrationProject = $null
	if ($migrationProjects.Count -eq 1) {
		$selectedMigrationProject = $migrationProjects[0]
		Write-LogSuccess "Using migration project: [$($selectedMigrationProject.Name)]"
	}
	else {
		# Build options with database type indicator
		$projectOptions = $migrationProjects | ForEach-Object {
			$current = if ($_.DbType -eq $currentDbType) { " [ACTIVE]" } else { "" }
			"$($_.DbType) - $($_.Name)$current"
		}

		$selectedOption = Resolve-Selection -OptionList $projectOptions -MenuTitle "[Select Migration Project]" -PromptMessage "Choose migration project"

		if (-not $selectedOption) {
			Write-LogError "No migration project selected. Exiting..."
			return
		}

		$selectedIndex = [array]::IndexOf($projectOptions, $selectedOption)
		$selectedMigrationProject = $migrationProjects[$selectedIndex]
	}

	$migrationsProjectPath = $selectedMigrationProject.RelativePath

	Write-LogStep "  Selected project => [$($selectedMigrationProject.Name)]"
	Write-LogStep "  Database type => [$($selectedMigrationProject.DbType)]" -NoLeadingNewline
	Write-LogStep "  Project path => [$migrationsProjectPath]" -NoLeadingNewline

	# Find migrations folder within the selected project
	$selectedMigrationFolder = $null
	if ($selectedMigrationProject.MigrationsSubfolder) {
		$selectedMigrationFolder = Get-Item -Path (Join-Path $selectedMigrationProject.Path $selectedMigrationProject.MigrationsSubfolder)
	}
	elseif ($selectedMigrationProject.SnapshotFile) {
		$selectedMigrationFolder = $selectedMigrationProject.SnapshotFile.Directory
	}
	else {
		# For empty dedicated projects, default to project root
		$selectedMigrationFolder = Get-Item -Path $selectedMigrationProject.Path
	}

	# Display the DbContext detected from the ModelSnapshot (resolution happens after startup search)
	if ($selectedMigrationProject.SnapshotFile) {
		$detectedContext = Get-DbContextFromSnapshot -SnapshotPath $selectedMigrationProject.SnapshotFile.FullName
		if ($detectedContext) {
			Write-LogStep "  Detected DbContext => [$detectedContext]" -NoLeadingNewline
		}
	}

	# Find startup project
	$startup = Find-EfStartupProject -SolutionRoot $solutionRoot -CsprojFiles $allCsproj -MigrationsProjectPath $migrationsProjectPath -MigrationsProjectFile $selectedMigrationProject.ProjectFile
	$startupProject = $startup.StartupProject
	$startupProjectPath = $startup.StartupProjectPath

	# Resolve the startup project directory for source-based context discovery
	$startupProjectDirectory = $null
	if ($startupProject) {
		$startupProjectDirectory = $startupProject.Directory.FullName
	}
	elseif ($startupProjectPath) {
		$startupProjectDirectory = Join-Path $solutionRoot $startupProjectPath
	}

	# Resolve DbContext (fast path skips the design-time build when the context is unambiguous)
	$contextResolution = Resolve-EfMigrationDbContext -MigrationProject $selectedMigrationProject -StartupProjectDirectory $startupProjectDirectory -MigrationsProjectPath $migrationsProjectPath -StartupProjectPath $startupProjectPath -SolutionRoot $solutionRoot
	$contextName = $contextResolution.ContextName
	$useExplicitContext = $contextResolution.UseExplicitContext

	# List existing migrations
	$allMigrations = @(Get-EfMigrations -MigrationFolderPath $selectedMigrationFolder.FullName)

	if ($allMigrations.Count -ge 2) {
		$lastMigration = $allMigrations[-1]
		$nextToLastMigration = $allMigrations[-2]
		Write-LogSuccess "Next to last migration => [$($nextToLastMigration.BaseName)]"
		Write-LogSuccess "Last migration => [$($lastMigration.BaseName)]" -NoLeadingNewline
	}
	elseif ($allMigrations.Count -eq 1) {
		Write-LogSuccess "Last migration => [$($allMigrations[0].BaseName)]"
		Write-LogWarning "No next to last migration found!" -NoLeadingNewline
	}
	else {
		Write-LogWarning "No migrations found in this project!"
	}

	# Build available actions based on context
	$availableActions = @("Add new migration")

	if ($allMigrations.Count -ge 2) {
		$availableActions += "Redo last migration"
	}

	if ($allMigrations.Count -ge 1) {
		$availableActions += "Remove last migration"
		$availableActions += "Squash all migrations"
	}

	# Add multi-database sync option if multiple migration projects exist
	if ($migrationProjects.Count -gt 1) {
		$availableActions += "Sync migration to other database(s)"
	}

	$availableActions += "Exit"

	$action = Resolve-Selection -OptionList $availableActions -PromptMessage "Select an option"

	Push-Location $solutionRoot
	try {
		$startupParam = if ($startupProjectPath) { " --startup-project `"$startupProjectPath`"" } else { "" }
		$contextParam = if ($useExplicitContext -and $contextName) { " --context $contextName" } else { "" }

		switch ($action) {
			"Add new migration" {
				$migrationName = Custom-ReadHost -PromptMessage "Enter the name for the new migration: "

				$efCommand = "dotnet ef migrations add $migrationName --project `"$migrationsProjectPath`"$startupParam$contextParam"

				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand

				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "Successfully added migration [$migrationName]"
				}
				else {
					Write-LogError "Failed to add migration. Please check the output above for errors!"
				}
			}

			"Redo last migration" {
				Write-LogStep "  Validating migration requirements for redo operation..."

				$updateTarget = $allMigrations[-2].BaseName
				$reAddName = $allMigrations[-1].BaseName -replace '^\d{14}_'

				Write-LogSuccess "Re-add name will be => [$reAddName]"

				Write-LogTitle "Step 1/3 - Reverting database to previous migration..."
				$efCommand = "dotnet ef database update $updateTarget --project `"$migrationsProjectPath`"$startupParam$contextParam"
				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand
				if ($LASTEXITCODE -ne 0) { Write-LogError "Step 1 FAILED!" -BlankLineAfter; Write-LogError "Aborting!"; return }

				Write-LogTitle "Step 2/3 - Removing last migration from the project..."
				$efCommand = "dotnet ef migrations remove --project `"$migrationsProjectPath`"$startupParam$contextParam"
				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand
				if ($LASTEXITCODE -ne 0) { Write-LogError "Step 2 FAILED!" -BlankLineAfter; Write-LogError "Aborting!"; return }

				Write-LogTitle "Step 3/3 - Re-adding the migration..."
				$efCommand = "dotnet ef migrations add $reAddName --project `"$migrationsProjectPath`"$startupParam$contextParam"
				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand
				if ($LASTEXITCODE -ne 0) { Write-LogError "Step 3 FAILED!" -BlankLineAfter; Write-LogError "Please check the output for errors!"; return }

				Write-LogSuccess "Successfully redone the last migration as [$reAddName]"
			}

			"Remove last migration" {
				Write-LogStep "  Validating migration requirements for remove operation..."

				$updateTarget = $null
				if ($allMigrations.Count -ge 2) {
					$updateTarget = $allMigrations[-2].BaseName
					Write-LogStep "  Database will be reverted to migration [$updateTarget]"
				}
				else {
					$updateTarget = "0"
					Write-LogStep "  Database will be reverted to its initial state (no migrations)."
				}

				Write-LogTitle "Step 1/2 - Reverting database to previous migration..."
				$efCommand = "dotnet ef database update $updateTarget --project `"$migrationsProjectPath`"$startupParam$contextParam"
				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand
				if ($LASTEXITCODE -ne 0) {
					Write-LogError "Step 1 FAILED! Could not revert database." -BlankLineAfter
					Write-LogError "Aborting!"
					return
				}

				Write-LogTitle "Step 2/2 - Removing last migration from the project..."
				$efCommand = "dotnet ef migrations remove --project `"$migrationsProjectPath`"$startupParam$contextParam"
				Write-LogStep "  Running [$efCommand]`n"
				Invoke-Expression $efCommand
				if ($LASTEXITCODE -ne 0) {
					Write-LogError "Step 2 FAILED! Could not remove migration files." -BlankLineAfter
					Write-LogError "Please check the output for errors!"
					return
				}

				Write-LogSuccess "Successfully removed the last migration and reverted the database."
			}

			"Squash all migrations" {
				Write-Host -ForegroundColor Red "`n[WARNING]`n This operation will:"
				Write-Host -ForegroundColor Red "   1. Delete ALL migration files from [$($selectedMigrationFolder.FullName)]"
				Write-Host -ForegroundColor Red "   2. Create a fresh migration named [initial-migration]"
				Write-LogError " This should ONLY be used before an app is in production!"

				$confirmation = Resolve-Selection -PromptMessage "Are you sure you want to squash all migrations?"

				if ($confirmation -ne "Yes") {
					Write-LogWarning "Squash all migrations cancelled!"
					return
				}

				Write-LogTitle "Step 1/2 - Deleting all migration files..." -BlankLineAfter

				$filesToDelete = Get-ChildItem -Path $selectedMigrationFolder.FullName -Filter "*.cs" -File
				foreach ($file in $filesToDelete) {
					Remove-Item -Path $file.FullName -Force
					Write-Host -ForegroundColor Yellow "  Deleted => $($file.Name)"
				}

				Write-LogSuccess "Deleted $($filesToDelete.Count) file(s)"

				Write-LogTitle "Step 2/2 - Creating initial migration..."

				$migrationCommand = "dotnet ef migrations add initial-migration --project `"$migrationsProjectPath`"$startupParam$contextParam"

				Write-LogStep "  Running [$migrationCommand]`n"
				Invoke-Expression $migrationCommand

				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "Successfully squashed all migrations into [initial-migration]"
				}
				else {
					Write-LogError "Failed to create initial migration! Check the output above for errors!"
				}
			}

			"Sync migration to other database(s)" {
				Write-LogStep "  This will help generate equivalent migrations in other database projects."

				$otherProjects = $migrationProjects | Where-Object { $_.Path -ne $selectedMigrationProject.Path }

				if ($otherProjects.Count -eq 0) {
					Write-LogError "No other migration projects found!"
					return
				}

				# Get migration name
				$migrationName = $null
				if ($allMigrations.Count -gt 0) {
					$lastMigrationName = $allMigrations[-1].BaseName -replace '^\d{14}_'
					Write-LogStep "  Last migration name: [$lastMigrationName]"
					$useLastName = Resolve-Selection -OptionList @("Yes", "No") -PromptMessage "Use this name for sync?"
					if ($useLastName -eq "Yes") {
						$migrationName = $lastMigrationName
					}
				}

				if (-not $migrationName) {
					$migrationName = Custom-ReadHost -PromptMessage "Enter migration name"
				}

				if (-not $migrationName) {
					$migrationName = "initial-migration"
				}

				# Select target projects
				$targetOptions = @($otherProjects | ForEach-Object { "$($_.DbType) - $($_.Name)" })
				if ($otherProjects.Count -gt 1) {
					$targetOptions += "All other projects"
				}

				$targetSelection = Resolve-Selection -OptionList $targetOptions -MenuTitle "[Select Target Project(s)]" -PromptMessage "Choose target for migration sync"

				$targetProjects = @()
				if ($targetSelection -eq "All other projects") {
					$targetProjects = @($otherProjects)
				}
				else {
					$selectedIndex = [array]::IndexOf($targetOptions, $targetSelection)
					$targetProjects = @($otherProjects[$selectedIndex])
				}

				Write-Host -ForegroundColor Yellow "`n[IMPORTANT] Database-specific migrations require the correct provider to be active."
				Write-Host -ForegroundColor Yellow "   The wizard will attempt to run migrations, but you may need to:"
				Write-Host -ForegroundColor Yellow "   1. Update appsettings.Development.json to enable the target database provider"
				Write-Host -ForegroundColor Yellow "   2. Ensure the target database is accessible`n"

				foreach ($target in $targetProjects) {
					$targetPath = if ($target.RelativePath) { $target.RelativePath } else { $target.Path }

					Write-LogStep "  Processing $($target.DbType) ($($target.Name))..."

					# Detect DbContext for target project
					$targetContextParam = ""
					$targetDiscoveredContexts = @(Get-DbContextsFromProject -ProjectPath $target.Path)
					$targetSimpleContexts = @($targetDiscoveredContexts | ForEach-Object { $_.Split('.')[-1] } | Sort-Object -Unique)
					if ($targetSimpleContexts.Count -gt 1) {
						$targetContextName = $null
						if ($target.SnapshotFile) {
							$targetContextName = Get-DbContextFromSnapshot -SnapshotPath $target.SnapshotFile.FullName
						}

						if (-not $targetContextName -or ($targetSimpleContexts -notcontains $targetContextName.Split('.')[-1])) {
							$targetContextName = Resolve-Selection -OptionList $targetSimpleContexts -MenuTitle "[Select DbContext for $($target.DbType)]" -PromptMessage "Choose DbContext"
						}

						if ($targetContextName) {
							$targetContextParam = " --context $($targetContextName.Split('.')[-1])"
						}
					}

					# Determine which flag to set
					$dbFlag = switch ($target.DbType) {
						"PostgreSQL" { "UseNpgSql" }
						"Oracle" { "UseOracle" }
						"SqlServer" { "UseSqlServer" }
						default { $null }
					}

					if ($dbFlag) {
						Write-LogStep "     Requires: $dbFlag = true in appsettings.Development.json" -NoLeadingNewline
					}

					$runNow = Resolve-Selection -OptionList @("Yes", "No, just show command") -PromptMessage "Run migration for $($target.DbType) now?"

					$efCommand = "dotnet ef migrations add $migrationName --project `"$targetPath`"$startupParam$targetContextParam"

					if ($runNow -eq "Yes") {
						Write-LogStep "  Running [$efCommand]`n"
						Invoke-Expression $efCommand

						if ($LASTEXITCODE -eq 0) {
							Write-LogSuccess "Successfully added migration [$migrationName] to $($target.DbType)" -NoLeadingNewline
						}
						else {
							Write-LogError "Failed! Check if $dbFlag is enabled in appsettings" -NoLeadingNewline
						}
					}
					else {
						Write-LogStep "  Command to run manually:"
						Write-LogStep "  $efCommand" -NoLeadingNewline
					}
				}
			}

			"Exit" {
				Write-LogWarning "Exiting..."
				return
			}
		}
	}
	finally {
		Pop-Location
	}
}
