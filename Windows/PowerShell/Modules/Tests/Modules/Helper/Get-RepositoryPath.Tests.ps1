#Requires -Modules Pester

BeforeAll {
	# The path helper cannot use itself to locate its own source, so this single test dot-sources it
	# by relative path - the one unavoidable bootstrap foothold in the suite. Every other test resolves
	# its target through (Get-RepositoryPath).Modules instead of counting folders.
	$HelperFunctionsPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\..\Helper\Functions"
	. "$HelperFunctionsPath\Get-RepositoryPath.ps1"
}

Describe "Get-RepositoryPath" {
	BeforeAll {
		# A synthetic repo laid out like the real one but nested at an arbitrary extra depth. If the
		# resolver counted parent folders it would land in the wrong place here; anchoring on
		# Configuration.psd1 makes the extra nesting irrelevant.
		$script:PsDir = Join-Path $TestDrive "Nested\Extra\Windows\PowerShell"
		$script:Deep = Join-Path $script:PsDir "Modules\SomeModule\Functions"
		New-Item -ItemType Directory -Path $script:Deep -Force | Out-Null
		Set-Content -Path (Join-Path $script:PsDir "Configuration.psd1") -Value "@{}" -NoNewline
	}

	It "resolves the PowerShell root from the folder holding Configuration.psd1" {
		(Get-RepositoryPath -StartPath $script:Deep).PowerShell | Should -Be $script:PsDir
	}

	It "derives the Modules root beneath the PowerShell root" {
		(Get-RepositoryPath -StartPath $script:Deep).Modules | Should -Be (Join-Path $script:PsDir "Modules")
	}

	It "derives the repository root two levels above the PowerShell root" {
		$expected = Split-Path -Path (Split-Path -Path $script:PsDir -Parent) -Parent
		(Get-RepositoryPath -StartPath $script:Deep).Repo | Should -Be $expected
	}

	It "resolves the same PowerShell root regardless of how deep the start path is" {
		$fromDeep = Get-RepositoryPath -StartPath $script:Deep
		$fromShallow = Get-RepositoryPath -StartPath (Join-Path $script:PsDir "Modules")
		$fromDeep.PowerShell | Should -Be $fromShallow.PowerShell
	}

	It "returns the PowerShell root itself when the start path already holds Configuration.psd1" {
		(Get-RepositoryPath -StartPath $script:PsDir).PowerShell | Should -Be $script:PsDir
	}

	It "throws a clear error when no Configuration.psd1 exists in any parent" {
		$orphan = Join-Path $TestDrive "Orphan\Deep\Path"
		New-Item -ItemType Directory -Path $orphan -Force | Out-Null
		{ Get-RepositoryPath -StartPath $orphan } | Should -Throw "*Configuration.psd1*"
	}
}
