#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"

	. "$FunctionsPath\Resolve-ProjectTerminalTab.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Resolve-ProjectTerminalTab" {
	BeforeEach {
		$global:Configuration = @{ DefaultWSLDistribution = "Ubuntu" }
		Mock Resolve-ProjectPath { "C:\Fake\$ProjectName\$PathKey" }
	}

	Context "Path entries" {
		It "resolves a plain path key through Resolve-ProjectPath" {
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "Api"

			$tab.Kind | Should -Be "Path"
			$tab.Path | Should -Be "C:\Fake\Demo\Api"
			$tab.Key | Should -Be "Api"
			$tab.Distribution | Should -BeNullOrEmpty
		}

		It "takes a hashtable entry's explicit path verbatim, without resolving anything" {
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry @{ Key = "Logs"; Path = "C:\Logs" }

			$tab.Kind | Should -Be "Path"
			$tab.Path | Should -Be "C:\Logs"
			Should -Invoke Resolve-ProjectPath -Times 0
		}

		It "titles every tab ProjectName.Key" {
			(Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "Api").Title | Should -Be "Demo.Api"
			(Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry @{ Key = "Logs"; Path = "C:\Logs" }).Title | Should -Be "Demo.Logs"
			(Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "WSL").Title | Should -Be "Demo.WSL"
		}
	}

	Context "Plain tabs" {
		It "reads DEFAULT as a tab with no path" {
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "DEFAULT"

			$tab.Kind | Should -Be "Default"
			$tab.Path | Should -BeNullOrEmpty
		}

		It "reads a hashtable entry that names a tab without a path as a plain tab" {
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry @{ Key = "Shell" }

			$tab.Kind | Should -Be "Default"
			$tab.Title | Should -Be "Demo.Shell"
			Should -Invoke Resolve-ProjectPath -Times 0
		}
	}

	Context "WSL entries" {
		It "reads the plain WSL key as a WSL tab at the distribution home" {
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "WSL"

			$tab.Kind | Should -Be "WSL"
			$tab.Path | Should -BeNullOrEmpty
			$tab.Distribution | Should -Be "Ubuntu"
		}

		It "keeps a WSL path exactly as configured, as a WSL tab" {
			# The regression this function exists for: read as an ordinary explicit path, this
			# entry reached Set-Location, which resolves a rooted path against the CURRENT DRIVE
			# and sent the tab to C:\mnt\c\... instead of into WSL.
			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry @{ Key = "WSL"; Path = "/mnt/c/Dev/Demo" }

			$tab.Kind | Should -Be "WSL"
			$tab.Path | Should -Be "/mnt/c/Dev/Demo"
			Should -Invoke Resolve-ProjectPath -Times 0
		}

		It "carries no distribution when DefaultWSLDistribution is unset" {
			$global:Configuration = @{ DefaultWSLDistribution = "" }

			$tab = Resolve-ProjectTerminalTab -ProjectName "Demo" -PathEntry "WSL"

			$tab.Kind | Should -Be "WSL"
			$tab.Distribution | Should -BeNullOrEmpty
		}
	}
}
