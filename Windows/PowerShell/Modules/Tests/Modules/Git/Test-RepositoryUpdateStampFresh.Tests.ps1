#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Test-RepositoryUpdateStampFresh.ps1"
}

Describe "Test-RepositoryUpdateStampFresh" {
	BeforeEach {
		$script:Stamp = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
	}

	It "is not fresh when there is no stamp" {
		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -IntervalHours 24 | Should -BeFalse
	}

	It "is fresh when the stamp is younger than the interval" {
		Set-Content -Path $script:Stamp -Value "stamp"

		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -IntervalHours 24 | Should -BeTrue
	}

	It "is not fresh when the stamp is older than the interval" {
		Set-Content -Path $script:Stamp -Value "stamp"
		(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-Date).AddHours(-25)

		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -IntervalHours 24 | Should -BeFalse
	}

	It "is never fresh with an interval of 0, so every shell runs it" {
		Set-Content -Path $script:Stamp -Value "stamp"

		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -IntervalHours 0 | Should -BeFalse
	}
}
