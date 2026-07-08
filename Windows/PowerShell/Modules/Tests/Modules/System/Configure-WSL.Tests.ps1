#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-WSL.ps1"
}

Describe "Configure-WSL" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
		}

		Mock Test-WSLEnabled { $true }
		Mock Test-WSLDistributionInstalled { $true }
		Mock Enable-WindowsOptionalFeature { }
		Mock wsl { }
		Mock Write-Host { }
	}

	It "skips install actions when WSL and distro are already present" {
		{ Configure-WSL } | Should -Not -Throw

		Should -Invoke Enable-WindowsOptionalFeature -Times 0
		Should -Invoke wsl -Times 0
	}
}
