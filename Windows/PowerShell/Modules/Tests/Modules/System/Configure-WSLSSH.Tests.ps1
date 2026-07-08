#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-WSLSSH.ps1"
}

Describe "Configure-WSLSSH" {
	BeforeEach {
		Mock wsl { }
		Mock Write-Host { }
	}

	It "executes WSL commands to copy and secure SSH keys" {
		{ Configure-WSLSSH } | Should -Not -Throw

		Should -Invoke wsl -Times 8
	}
}
