#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\EfCoreMigrationWizard.ps1"

	# Real discovery helpers (driven by the Get-ChildItem/Get-Content mocks below).
	. "$HelperFunctionsPath\Find-EfMigrationProjects.ps1"
	. "$HelperFunctionsPath\Get-EfCurrentDatabaseType.ps1"
	. "$HelperFunctionsPath\Find-EfStartupProject.ps1"
	. "$HelperFunctionsPath\Resolve-EfMigrationDbContext.ps1"
	. "$HelperFunctionsPath\Get-EfMigrations.ps1"

	function Find-Item {
		param($Pattern, $SearchTarget, $MaxDownwardDepth, $MaxUpwardDepth, $SearchMessage, $SuccessMessage)
		[PSCustomObject]@{ Path = 'C:\Repo' }
	}

	function Get-DatabaseTypeFromProject { 'PostgreSQL' }
	function Test-HasEfCoreDesign { $true }
	function Get-DbContextFromSnapshot { 'AppDbContext' }
	function Get-DbContextsFromProject { @('AppDbContext') }
	function Get-EfCoreDbContexts { @('AppDbContext') }
	function Resolve-Selection {
		param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
		if ($InputObject) { return $InputObject }
		if ($OptionList -contains 'Add new migration') { return 'Add new migration' }
		if ($OptionList -contains 'Exit') { return 'Exit' }
		if ($OptionList -contains 'Yes') { return 'Yes' }
		return $OptionList | Select-Object -First 1
	}
	function Custom-ReadHost { 'TestMigration' }
}

Describe "EfCoreMigrationWizard" {
	BeforeEach {
		$script:invokeExpressions = @()
		$script:pushLocationPath = $null
		$script:popLocationCount = 0

		Mock Write-Host { }
		Mock Find-Item { [PSCustomObject]@{ Path = 'C:\Repo' } }
		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($InputObject) { return $InputObject }
			if ($OptionList -contains 'Add new migration') { return 'Add new migration' }
			if ($OptionList -contains 'Exit') { return 'Exit' }
			if ($OptionList -contains 'Yes') { return 'Yes' }
			$OptionList | Select-Object -First 1
		}
		Mock Custom-ReadHost { 'TestMigration' }
		Mock Get-DatabaseTypeFromProject { 'PostgreSQL' }
		Mock Test-HasEfCoreDesign { $true }
		Mock Get-DbContextFromSnapshot { 'AppDbContext' }
		Mock Get-DbContextsFromProject { @('AppDbContext') }
		Mock Get-EfCoreDbContexts { @('AppDbContext') }
		Mock Push-Location { param($Path) $script:pushLocationPath = $Path }
		Mock Pop-Location { $script:popLocationCount++ }
		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{
							Name      = 'App.PostgreMigrations.csproj'
							BaseName  = 'App.PostgreMigrations'
							FullName  = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' }
						},
						[PSCustomObject]@{
							Name      = 'App.Api.csproj'
							BaseName  = 'App.Api'
							FullName  = 'C:\Repo\src\App.Api\App.Api.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						}
					)
				}
				'*ModelSnapshot.cs' {
					@([PSCustomObject]@{
							FullName  = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'
							Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' }
						})
				}
				'appsettings*.json' {
					@([PSCustomObject]@{
							Name      = 'appsettings.Development.json'
							FullName  = 'C:\Repo\src\App.Api\appsettings.Development.json'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						})
				}
				'*.cs' {
					@([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' })
				}
				default { @() }
			}
		}

		Mock Get-Content {
			param($Path, [switch]$Raw)
			if ($Path -like '*appsettings*') {
				'{"DatabaseConfiguration":{"UseNpgSql":true}}'
			}
			elseif ($Path -like '*Snapshot.cs') {
				'public class AppDbContextModelSnapshot : ModelSnapshot { }'
			}
			else {
				''
			}
		}
		Mock ConvertFrom-Json {
			param($InputObject)
			[PSCustomObject]@{
				DatabaseConfiguration = [PSCustomObject]@{
					UseNpgSql    = $true
					UseOracle    = $false
					UseSqlServer = $false
				}
			}
		}
		Mock Test-Path { $true }
		Mock Get-Item {
			param($Path)
			[PSCustomObject]@{ FullName = $Path }
		}
	}

	It "returns early when no solution file is found" {
		Mock Find-Item { $null }

		EfCoreMigrationWizard

		Should -Invoke Push-Location -Times 0
		$script:invokeExpressions.Count | Should -Be 0
	}

	It "builds and executes add migration command with project and startup paths" {
		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Match 'dotnet ef migrations add TestMigration'
		$script:invokeExpressions[0] | Should -Match '--project\s+"src\\App.PostgreMigrations"'
		$script:invokeExpressions[0] | Should -Match '--startup-project\s+"src\\App.Api"'
		$script:invokeExpressions[0] | Should -Not -Match '--context'
	}

	It "keeps --context when multiple CLI contexts are detected" {
		# Two ModelSnapshots => more than one DbContext => fall back to design-time discovery,
		# which here reports multiple contexts and forces an explicit --context.
		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' {
					@(
						[PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } },
						[PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\ReportingDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }
					)
				}
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' { @([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' }) }
				default { @() }
			}
		}

		Mock Get-EfCoreDbContexts { @('AppDbContext', 'ReportingDbContext') }

		EfCoreMigrationWizard

		Should -Invoke Get-EfCoreDbContexts -Exactly -Times 1
		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Match '--context\s+AppDbContext'
	}

	It "skips the design-time build when a single DbContext is present" {
		EfCoreMigrationWizard

		# Single ModelSnapshot => fast path => no `dotnet ef dbcontext list`, no --context.
		Should -Invoke Get-EfCoreDbContexts -Exactly -Times 0
		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Not -Match '--context'
	}

	It "always restores location with Pop-Location after command execution" {
		EfCoreMigrationWizard

		$script:pushLocationPath | Should -Be 'C:\Repo'
		$script:popLocationCount | Should -Be 1
	}

	It "aborts redo flow when the first step fails" {
		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{
							Name      = 'App.PostgreMigrations.csproj'
							BaseName  = 'App.PostgreMigrations'
							FullName  = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' }
						},
						[PSCustomObject]@{
							Name      = 'App.Api.csproj'
							BaseName  = 'App.Api'
							FullName  = 'C:\Repo\src\App.Api\App.Api.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						}
					)
				}
				'*ModelSnapshot.cs' {
					@([PSCustomObject]@{
							FullName  = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'
							Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' }
						})
				}
				'appsettings*.json' {
					@([PSCustomObject]@{
							Name      = 'appsettings.Development.json'
							FullName  = 'C:\Repo\src\App.Api\appsettings.Development.json'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						})
				}
				'*.cs' {
					@(
						[PSCustomObject]@{ Name = '20260520110000_Initial.cs'; BaseName = '20260520110000_Initial' },
						[PSCustomObject]@{ Name = '20260520120000_AddUser.cs'; BaseName = '20260520120000_AddUser' }
					)
				}
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Redo last migration') { return 'Redo last migration' }
			$OptionList | Select-Object -First 1
		}

		$script:redoCall = 0
		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$script:redoCall++
			if ($script:redoCall -eq 1) { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Match 'dotnet ef database update 20260520110000_Initial'
	}

	It "remove flow uses target 0 when only one migration exists and stops on step 2 failure" {
		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Remove last migration') { return 'Remove last migration' }
			$OptionList | Select-Object -First 1
		}

		$script:removeCall = 0
		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$script:removeCall++
			if ($script:removeCall -eq 1) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 2
		$script:invokeExpressions[0] | Should -Match 'dotnet ef database update 0'
		$script:invokeExpressions[1] | Should -Match 'dotnet ef migrations remove'
	}

	It "squash flow exits early when confirmation is not Yes" {
		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Squash all migrations') { return 'Squash all migrations' }
			if ($PromptMessage -like 'Are you sure*') { return 'No' }
			$OptionList | Select-Object -First 1
		}

		Mock Remove-Item { }

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 0
		Should -Invoke Remove-Item -Times 0
	}

	It "sync flow can choose manual command path without executing dotnet ef for target projects" {
		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{
							Name      = 'App.PostgreMigrations.csproj'
							BaseName  = 'App.PostgreMigrations'
							FullName  = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' }
						},
						[PSCustomObject]@{
							Name      = 'App.OracleMigrations.csproj'
							BaseName  = 'App.OracleMigrations'
							FullName  = 'C:\Repo\src\App.OracleMigrations\App.OracleMigrations.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations' }
						},
						[PSCustomObject]@{
							Name      = 'App.Api.csproj'
							BaseName  = 'App.Api'
							FullName  = 'C:\Repo\src\App.Api\App.Api.csproj'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						}
					)
				}
				'*ModelSnapshot.cs' {
					@([PSCustomObject]@{
							FullName  = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'
							Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' }
						})
				}
				'appsettings*.json' {
					@([PSCustomObject]@{
							Name      = 'appsettings.Development.json'
							FullName  = 'C:\Repo\src\App.Api\appsettings.Development.json'
							Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' }
						})
				}
				'*.cs' {
					@([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' })
				}
				default { @() }
			}
		}

		$script:selectionQueue = @(
			'Sync migration to other database(s)',
			'Yes',
			'Oracle - App.OracleMigrations',
			'No, just show command'
		)

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($script:selectionQueue.Count -gt 0) {
				$next = $script:selectionQueue[0]
				$script:selectionQueue = @($script:selectionQueue | Select-Object -Skip 1)
				return $next
			}
			$OptionList | Select-Object -First 1
		}

		EfCoreMigrationWizard

		# In manual mode for sync target, no dotnet ef should run for target migration creation.
		$script:invokeExpressions | Where-Object { $_ -match 'dotnet ef migrations add' } | Should -BeNullOrEmpty
	}

	It "redo flow executes all three steps on success" {
		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' {
					@(
						[PSCustomObject]@{ Name = '20260520110000_Initial.cs'; BaseName = '20260520110000_Initial' },
						[PSCustomObject]@{ Name = '20260520120000_AddUser.cs'; BaseName = '20260520120000_AddUser' }
					)
				}
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Redo last migration') { return 'Redo last migration' }
			$OptionList | Select-Object -First 1
		}

		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 3
		$script:invokeExpressions[0] | Should -Match 'dotnet ef database update 20260520110000_Initial'
		$script:invokeExpressions[1] | Should -Match 'dotnet ef migrations remove'
		$script:invokeExpressions[2] | Should -Match 'dotnet ef migrations add AddUser'
	}

	It "remove flow executes both steps on success" {
		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' {
					@(
						[PSCustomObject]@{ Name = '20260520110000_Initial.cs'; BaseName = '20260520110000_Initial' },
						[PSCustomObject]@{ Name = '20260520120000_AddUser.cs'; BaseName = '20260520120000_AddUser' }
					)
				}
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Remove last migration') { return 'Remove last migration' }
			$OptionList | Select-Object -First 1
		}

		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 2
		$script:invokeExpressions[0] | Should -Match 'dotnet ef database update 20260520110000_Initial'
		$script:invokeExpressions[1] | Should -Match 'dotnet ef migrations remove'
	}

	It "squash flow deletes migration files and creates initial migration when confirmed" {
		$script:removedFiles = @()

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($OptionList -contains 'Squash all migrations') { return 'Squash all migrations' }
			if ($PromptMessage -like 'Are you sure*') { return 'Yes' }
			$OptionList | Select-Object -First 1
		}

		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' {
					@(
						[PSCustomObject]@{ Name = '20260520110000_Initial.cs'; BaseName = '20260520110000_Initial'; FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\20260520110000_Initial.cs' },
						[PSCustomObject]@{ Name = '20260520120000_AddUser.cs'; BaseName = '20260520120000_AddUser'; FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\20260520120000_AddUser.cs' }
					)
				}
				default { @() }
			}
		}

		Mock Remove-Item {
			param($Path, [switch]$Force)
			$script:removedFiles += $Path
		}

		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		EfCoreMigrationWizard

		$script:removedFiles.Count | Should -Be 2
		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Match 'dotnet ef migrations add initial-migration'
	}

	It "sync flow executes migration add for selected target when run-now is Yes" {
		Mock Get-DatabaseTypeFromProject {
			param($projectName, $projectPath, $snapshotContent)
			if ($projectName -match 'Oracle') { 'Oracle' } else { 'PostgreSQL' }
		}

		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.OracleMigrations.csproj'; BaseName = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations\App.OracleMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' { @([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' }) }
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($MenuTitle -eq '[Select Migration Project]') {
				return ($OptionList | Where-Object { $_ -like '*App.PostgreMigrations*' } | Select-Object -First 1)
			}
			if ($PromptMessage -eq 'Select an option') {
				return 'Sync migration to other database(s)'
			}
			if ($PromptMessage -eq 'Use this name for sync?') {
				return 'Yes'
			}
			if ($MenuTitle -eq '[Select Target Project(s)]') {
				return 'Oracle - App.OracleMigrations'
			}
			if ($PromptMessage -like 'Run migration for*') {
				return 'Yes'
			}
			$OptionList | Select-Object -First 1
		}

		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 1
		$script:invokeExpressions[0] | Should -Match 'dotnet ef migrations add Initial --project "src\\App.OracleMigrations"'
	}

	It "sync flow executes migration add for all other projects when selected and run-now is Yes" {
		Mock Get-DatabaseTypeFromProject {
			param($projectName, $projectPath, $snapshotContent)
			switch -Regex ($projectName) {
				'Oracle' { 'Oracle' }
				'SqlServer' { 'SqlServer' }
				default { 'PostgreSQL' }
			}
		}

		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.OracleMigrations.csproj'; BaseName = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations\App.OracleMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations' } },
						[PSCustomObject]@{ Name = 'App.SqlServerMigrations.csproj'; BaseName = 'App.SqlServerMigrations'; FullName = 'C:\Repo\src\App.SqlServerMigrations\App.SqlServerMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.SqlServerMigrations'; FullName = 'C:\Repo\src\App.SqlServerMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' { @([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' }) }
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($MenuTitle -eq '[Select Migration Project]') {
				return ($OptionList | Where-Object { $_ -like '*App.PostgreMigrations*' } | Select-Object -First 1)
			}
			if ($PromptMessage -eq 'Select an option') {
				return 'Sync migration to other database(s)'
			}
			if ($PromptMessage -eq 'Use this name for sync?') {
				return 'Yes'
			}
			if ($MenuTitle -eq '[Select Target Project(s)]') {
				return 'All other projects'
			}
			if ($PromptMessage -like 'Run migration for*') {
				return 'Yes'
			}
			$OptionList | Select-Object -First 1
		}

		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$global:LASTEXITCODE = 0
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 2
		@($script:invokeExpressions | Where-Object { $_ -match 'dotnet ef migrations add Initial --project "src\\App.OracleMigrations"' }).Count | Should -Be 1
		@($script:invokeExpressions | Where-Object { $_ -match 'dotnet ef migrations add Initial --project "src\\App.SqlServerMigrations"' }).Count | Should -Be 1
	}

	It "sync flow continues to remaining targets when one run-now command fails" {
		Mock Get-DatabaseTypeFromProject {
			param($projectName, $projectPath, $snapshotContent)
			switch -Regex ($projectName) {
				'Oracle' { 'Oracle' }
				'SqlServer' { 'SqlServer' }
				default { 'PostgreSQL' }
			}
		}

		Mock Get-ChildItem {
			param($Path, $Recurse, $Filter, $File)
			switch ($Filter) {
				'*.csproj' {
					@(
						[PSCustomObject]@{ Name = 'App.PostgreMigrations.csproj'; BaseName = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations\App.PostgreMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.PostgreMigrations'; FullName = 'C:\Repo\src\App.PostgreMigrations' } },
						[PSCustomObject]@{ Name = 'App.OracleMigrations.csproj'; BaseName = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations\App.OracleMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.OracleMigrations'; FullName = 'C:\Repo\src\App.OracleMigrations' } },
						[PSCustomObject]@{ Name = 'App.SqlServerMigrations.csproj'; BaseName = 'App.SqlServerMigrations'; FullName = 'C:\Repo\src\App.SqlServerMigrations\App.SqlServerMigrations.csproj'; Directory = [PSCustomObject]@{ Name = 'App.SqlServerMigrations'; FullName = 'C:\Repo\src\App.SqlServerMigrations' } },
						[PSCustomObject]@{ Name = 'App.Api.csproj'; BaseName = 'App.Api'; FullName = 'C:\Repo\src\App.Api\App.Api.csproj'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }
					)
				}
				'*ModelSnapshot.cs' { @([PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations\AppDbContextModelSnapshot.cs'; Directory = [PSCustomObject]@{ FullName = 'C:\Repo\src\App.PostgreMigrations\Migrations' } }) }
				'appsettings*.json' { @([PSCustomObject]@{ Name = 'appsettings.Development.json'; FullName = 'C:\Repo\src\App.Api\appsettings.Development.json'; Directory = [PSCustomObject]@{ Name = 'App.Api'; FullName = 'C:\Repo\src\App.Api' } }) }
				'*.cs' { @([PSCustomObject]@{ Name = '20260520120000_Initial.cs'; BaseName = '20260520120000_Initial' }) }
				default { @() }
			}
		}

		Mock Resolve-Selection {
			param($OptionList, $MenuTitle, $PromptMessage, $InputObject)
			if ($MenuTitle -eq '[Select Migration Project]') {
				return ($OptionList | Where-Object { $_ -like '*App.PostgreMigrations*' } | Select-Object -First 1)
			}
			if ($PromptMessage -eq 'Select an option') {
				return 'Sync migration to other database(s)'
			}
			if ($PromptMessage -eq 'Use this name for sync?') {
				return 'Yes'
			}
			if ($MenuTitle -eq '[Select Target Project(s)]') {
				return 'All other projects'
			}
			if ($PromptMessage -like 'Run migration for*') {
				return 'Yes'
			}
			$OptionList | Select-Object -First 1
		}

		$script:syncCallCount = 0
		Mock Invoke-Expression {
			param($Command)
			$script:invokeExpressions += $Command
			$script:syncCallCount++
			if ($script:syncCallCount -eq 1) {
				$global:LASTEXITCODE = 1
			}
			else {
				$global:LASTEXITCODE = 0
			}
		}

		EfCoreMigrationWizard

		$script:invokeExpressions.Count | Should -Be 2
		@($script:invokeExpressions | Where-Object { $_ -match 'dotnet ef migrations add Initial --project "src\\App.OracleMigrations"' }).Count | Should -Be 1
		@($script:invokeExpressions | Where-Object { $_ -match 'dotnet ef migrations add Initial --project "src\\App.SqlServerMigrations"' }).Count | Should -Be 1
	}
}
