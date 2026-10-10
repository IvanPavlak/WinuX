#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Read-ImpactMap.ps1")
	. (Join-Path $ModuleRoot "Tests\Get-SelectorMisses.ps1")

	function Write-Map {
		param([string]$Path, [string]$Pester = '6.1.0', [string]$Commit = $null, [hashtable]$Tests)
		$document = [ordered]@{ commit = $Commit; pester = $Pester; built = '2026-10-10T00:00:00Z'; tests = $Tests }
		Set-Content -LiteralPath $Path -Value ($document | ConvertTo-Json -Depth 5) -Encoding UTF8
	}
}

Describe "Read-ImpactMap" {
	BeforeEach {
		$script:MapFile = Join-Path $TestDrive ("impact_{0}.json" -f [guid]::NewGuid().ToString('N'))
	}

	It "inverts test -> functions into function -> tests" {
		Write-Map -Path $script:MapFile -Tests @{
			'Modules/Tests/Modules/A/A.Tests.ps1' = @('Modules/A/Functions/Get-A.ps1', 'Modules/H/Functions/Get-Help.ps1')
			'Modules/Tests/Modules/B/B.Tests.ps1' = @('Modules/H/Functions/Get-Help.ps1')
		}
		$map = (Read-ImpactMap -Path $script:MapFile -PesterVersion '6.1.0').Map
		@($map['Modules/A/Functions/Get-A.ps1']) | Should -Be @('Modules/Tests/Modules/A/A.Tests.ps1')
		@($map['Modules/H/Functions/Get-Help.ps1'] | Sort-Object) | Should -Be @('Modules/Tests/Modules/A/A.Tests.ps1', 'Modules/Tests/Modules/B/B.Tests.ps1')
	}

	It "is silently absent when no map was built" {
		$result = Read-ImpactMap -Path $script:MapFile -PesterVersion '6.1.0'
		$result.Map | Should -BeNullOrEmpty
		$result.Note | Should -BeNullOrEmpty
	}

	It "ignores a map built for another Pester version, and says so" {
		Write-Map -Path $script:MapFile -Pester '5.7.1' -Tests @{ 'a' = @('b') }
		$result = Read-ImpactMap -Path $script:MapFile -PesterVersion '6.1.0'
		$result.Map | Should -BeNullOrEmpty
		$result.Note | Should -Not -BeNullOrEmpty
	}

	It "ignores a corrupt map, and says so" {
		Set-Content -LiteralPath $script:MapFile -Value '{ nope'
		$result = Read-ImpactMap -Path $script:MapFile -PesterVersion '6.1.0'
		$result.Map | Should -BeNullOrEmpty
		$result.Note | Should -Not -BeNullOrEmpty
	}

	It "ignores a map built too many commits ago, and says so" -Tag 'Integration' {
		$repo = Join-Path $TestDrive ("repo_{0}" -f [guid]::NewGuid().ToString('N'))
		git -c init.defaultBranch=master init --quiet $repo
		$identity = @('-c', 'user.name=Test', '-c', 'user.email=test@example.com')
		git -C $repo @identity commit --quiet --allow-empty -m one
		$first = @(git -C $repo rev-parse HEAD)[0]
		for ($i = 0; $i -lt 3; $i++) { git -C $repo @identity commit --quiet --allow-empty -m "c$i" }

		$first | Should -Match '^[0-9a-f]{40}$' -Because "the throwaway repository needs its first commit"
		Write-Map -Path $script:MapFile -Commit $first -Tests @{ 'a' = @('b') }
		$fresh = Read-ImpactMap -Path $script:MapFile -RepositoryRoot $repo -PesterVersion '6.1.0' -MaxCommitsBehind 5
		$fresh.Note | Should -BeNullOrEmpty
		$fresh.Map | Should -Not -BeNullOrEmpty
		$stale = Read-ImpactMap -Path $script:MapFile -RepositoryRoot $repo -PesterVersion '6.1.0' -MaxCommitsBehind 2
		$stale.Map | Should -BeNullOrEmpty
		$stale.Note | Should -Match 'commits ago'
	}
}

Describe "Get-SelectorMisses" {
	It "returns the failing files the selection did not include" {
		$misses = Get-SelectorMisses -FailedFiles 'a/One.Tests.ps1', 'b/Two.Tests.ps1' -SelectedFiles 'A/ONE.Tests.ps1', 'c/Three.Tests.ps1'
		@($misses) | Should -Be @('b/Two.Tests.ps1')
	}

	It "reports nothing when every failing file was selected, or nothing failed" {
		@(Get-SelectorMisses -FailedFiles 'a' -SelectedFiles 'a', 'b').Count | Should -Be 0
		@(Get-SelectorMisses -FailedFiles @() -SelectedFiles 'a').Count | Should -Be 0
	}

	It "cannot miss anything when the selection was the full suite" {
		@(Get-SelectorMisses -FailedFiles 'a', 'b' -SelectedFiles @() -FullSuite).Count | Should -Be 0
	}

	It "treats an empty selection as missing every failure" {
		@(Get-SelectorMisses -FailedFiles 'a', 'b' -SelectedFiles @()).Count | Should -Be 2
	}
}
