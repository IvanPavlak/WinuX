#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-DatabaseTypeFromProject.ps1"
}

Describe "Get-DatabaseTypeFromProject" {
	Context "Detection by Project Name" {
		It "Should detect PostgreSQL from project name containing 'Postgre'" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.PostgreSQL" -projectPath "C:\Projects" -snapshotContent ""

			$result | Should -Be "PostgreSQL"
		}

		It "Should detect PostgreSQL from project name containing 'Npgsql'" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.Npgsql" -projectPath "C:\Projects" -snapshotContent ""

			$result | Should -Be "PostgreSQL"
		}

		It "Should detect Oracle from project name" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.Oracle" -projectPath "C:\Projects" -snapshotContent ""

			$result | Should -Be "Oracle"
		}

		It "Should detect SqlServer from project name" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.SqlServer" -projectPath "C:\Projects" -snapshotContent ""

			$result | Should -Be "SqlServer"
		}

		It "Should detect SqlServer from project name containing 'MsSql'" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.MsSql" -projectPath "C:\Projects" -snapshotContent ""

			$result | Should -Be "SqlServer"
		}
	}

	Context "Detection by Project Path" {
		It "Should detect PostgreSQL from project path" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects\PostgreSQL\MyApp.csproj" -snapshotContent ""

			$result | Should -Be "PostgreSQL"
		}

		It "Should detect Oracle from project path" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects\Oracle\MyApp.csproj" -snapshotContent ""

			$result | Should -Be "Oracle"
		}

		It "Should detect SqlServer from project path" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects\SqlServer\MyApp.csproj" -snapshotContent ""

			$result | Should -Be "SqlServer"
		}
	}

	Context "Detection by Snapshot Content" {
		It "Should detect PostgreSQL from snapshot content" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects" -snapshotContent 'using Npgsql;'

			$result | Should -Be "PostgreSQL"
		}

		It "Should detect Oracle from snapshot content" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects" -snapshotContent 'using Oracle.EntityFrameworkCore;'

			$result | Should -Be "Oracle"
		}

		It "Should detect SqlServer from snapshot content" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects" -snapshotContent 'using Microsoft.EntityFrameworkCore.SqlServer;'

			$result | Should -Be "SqlServer"
		}
	}

	Context "Priority Order" {
		It "Should prioritize project name over snapshot content" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp.Oracle" -projectPath "C:\Projects" -snapshotContent 'using Npgsql;'

			$result | Should -Be "Oracle"
		}

		It "Should prioritize project path over snapshot content" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects\SqlServer\MyApp.csproj" -snapshotContent 'using Npgsql;'

			$result | Should -Be "SqlServer"
		}
	}

	Context "Unknown Database Type" {
		It "Should return Unknown when no database type can be determined" {
			$result = Get-DatabaseTypeFromProject -projectName "MyApp" -projectPath "C:\Projects\MyApp.csproj" -snapshotContent ""

			$result | Should -Be "Unknown"
		}

		It "Should return Unknown when all parameters are empty" {
			$result = Get-DatabaseTypeFromProject -projectName "" -projectPath "" -snapshotContent ""

			$result | Should -Be "Unknown"
		}
	}
}
