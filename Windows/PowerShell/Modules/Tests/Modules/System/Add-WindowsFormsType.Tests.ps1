#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Add-WindowsFormsType.ps1"
}

Describe "Add-WindowsFormsType" {
	BeforeEach {
		Mock Add-Type { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
	}

	It "loads System.Windows.Forms and writes status output by default" {
		{ Add-WindowsFormsType } | Should -Not -Throw
		Should -Invoke Add-Type -Times 1 -ParameterFilter { $AssemblyName -eq "System.Windows.Forms" }
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogSuccess -Times 1
	}

	It "suppresses status output when Quiet is used" {
		{ Add-WindowsFormsType -Quiet } | Should -Not -Throw
		Should -Invoke Add-Type -Times 1
		Should -Invoke Write-LogTitle -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}
}
