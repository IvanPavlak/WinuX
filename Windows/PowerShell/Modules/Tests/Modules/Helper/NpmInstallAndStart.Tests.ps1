#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\NpmInstallAndStart.ps1"
}

Describe "NpmInstallAndStart" {
	BeforeEach {
		$script:npmCommands = @()
		function global:npm {
			param([string]$Command)
			$script:npmCommands += $Command
		}
	}

	AfterEach {
		Remove-Item Function:\npm -ErrorAction SilentlyContinue
	}

	It "invokes npm install then npm start" {
		NpmInstallAndStart

		$script:npmCommands.Count | Should -Be 2
		$script:npmCommands[0] | Should -Be "install"
		$script:npmCommands[1] | Should -Be "start"
	}
}
