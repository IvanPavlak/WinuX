#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-DbContextFromSnapshot.ps1"
}

Describe "Get-DbContextFromSnapshot" {
	BeforeEach {
		Mock Test-Path { $true }
	}

	It "extracts DbContext class name from snapshot attribute" {
		Mock Get-Content { "[DbContext(typeof(MyApp.Data.AppDbContext))]" }

		$result = Get-DbContextFromSnapshot -SnapshotPath "C:\\snapshot.cs"

		$result | Should -Be "AppDbContext"
	}

	It "returns null when snapshot path does not exist" {
		Mock Test-Path { $false }

		$result = Get-DbContextFromSnapshot -SnapshotPath "C:\\missing.cs"

		$result | Should -Be $null
	}
}
