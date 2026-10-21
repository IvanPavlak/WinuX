#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-PowerShellFunctionDependencies.ps1"
}

Describe "Get-PowerShellFunctionDependencies" {
	BeforeEach {
		$script:ProcessedFunctions = @()
		Mock Get-Command { throw "Missing" }
		Mock Write-Warning { }
	}

	It "returns null and warns when function is not found" {
		$result = Get-PowerShellFunctionDependencies -FunctionName "Not-There"

		$result | Should -Be $null
		Should -Invoke Write-Warning -Times 1
	}

	Context "a function that exists" {
		BeforeAll {
			function global:Invoke-DependencySample { Write-LogStep "sample" }
			$script:RealGetCommand = Get-Command -Name Get-Command -CommandType Cmdlet
		}

		AfterAll {
			Remove-Item -Path Function:\Invoke-DependencySample -ErrorAction SilentlyContinue
		}

		BeforeEach {
			Mock Get-Command { & $script:RealGetCommand @PSBoundParameters }
		}

		It "counts a Logging command as a dependency of this repository" {
			# The module list was hard-coded and lacked AI, Configuration, Logging, Window and Custom.
			$result = Get-PowerShellFunctionDependencies -FunctionName "Invoke-DependencySample"

			@($result.Custom.Command) | Should -Contain "Write-LogStep"
			@($result.Module.Command) | Should -Not -Contain "Write-LogStep"
		}

		It "returns the dependencies again on a repeat call" {
			# The processed list was never reset, so the second call returned $null.
			$first = Get-PowerShellFunctionDependencies -FunctionName "Invoke-DependencySample"
			$second = Get-PowerShellFunctionDependencies -FunctionName "Invoke-DependencySample"

			$first | Should -Not -BeNullOrEmpty
			$second | Should -Not -BeNullOrEmpty
			@($second.Custom.Command) | Should -Contain "Write-LogStep"
		}
	}
}
