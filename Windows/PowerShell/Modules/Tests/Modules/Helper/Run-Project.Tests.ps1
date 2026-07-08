#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Run-Project.ps1"
}

Describe "Run-Project" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			RunnableProjects        = @("Demo")
			RunnableProjectMappings = @()
			ProjectTerminals        = @()
			DockerComposeFiles      = @{}
		}
		Mock Resolve-Selection { @("Demo") }
		Mock Get-WindowHandle { $null }
		Mock Write-Host { }
		Mock Write-LogStep { }
		Mock Write-LogError { }
		Mock Focus-TerminalTab { }
	}

	It "continues safely when no runnable mapping exists for selected project" {
		{ Run-Project } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
