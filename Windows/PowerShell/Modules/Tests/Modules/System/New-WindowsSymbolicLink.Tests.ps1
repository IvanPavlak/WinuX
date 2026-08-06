#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\New-WindowsSymbolicLink.ps1"
}

Describe "New-WindowsSymbolicLink" {
	BeforeEach {
		Mock Test-Path { $true }
		Mock Remove-Item { }
		Mock New-Item { }
		Mock Initialize-Directory { }
		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
	}

	It "removes an existing item and creates the link" {
		{ New-WindowsSymbolicLink -Path "C:\link" -Target "C:\target" } | Should -Not -Throw

		Should -Invoke Remove-Item -Times 1 -Exactly
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' -and $Path -eq 'C:\link' -and $Target -eq 'C:\target' }
	}

	It "skips with a warning when the target does not exist" {
		Mock Test-Path { $false }

		{ New-WindowsSymbolicLink -Path "C:\link" -Target "C:\missing" } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "target does not exist" }
		Should -Invoke New-Item -Times 0
		Should -Invoke Remove-Item -Times 0
	}

	It "creates the parent directory when missing" {
		Mock Test-Path { param($Path) $Path -notin @("C:\parent", "C:\parent\link") }

		{ New-WindowsSymbolicLink -Path "C:\parent\link" -Target "C:\target" } | Should -Not -Throw

		Should -Invoke Initialize-Directory -Times 1 -Exactly
		Should -Invoke Remove-Item -Times 0
		Should -Invoke New-Item -Times 1 -Exactly
	}

	It "logs an error instead of throwing when creation fails" {
		Mock New-Item { throw "access denied" }

		{ New-WindowsSymbolicLink -Path "C:\link" -Target "C:\target" -DisplayName "Git" } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Git" }
	}
}
