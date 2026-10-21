#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-MicrosoftActivationScripts.ps1"
}

Describe "Start-MicrosoftActivationScripts" {
	BeforeEach {
		Mock Write-Host { }
		Mock Resolve-Selection { 'No' }
		Mock cscript { 'The machine is permanently activated.' }
		Mock Get-ItemProperty {
			[PSCustomObject]@{ 'Excel.Application.16' = 'dummy' }
		}
	}

	It "returns early without prompt when Windows is activated and Office is installed" {
		Start-MicrosoftActivationScripts

		Should -Invoke Resolve-Selection -Times 0
	}

	It "prompts and exits when Override is set and selection resolves to No" {
		Start-MicrosoftActivationScripts -Override

		Should -Invoke Resolve-Selection -Times 1 -Exactly
	}

	Context "the script URL" {
		BeforeEach {
			$script:SavedConfiguration = $global:Configuration
			Mock Resolve-Selection { 'Yes' }
			Mock Invoke-RestMethod { '' }
			Mock Invoke-Expression { }
			Mock Write-LogSuccess { }
		}

		AfterEach {
			$global:Configuration = $script:SavedConfiguration
		}

		It "downloads from BootstrapConfig.ExternalScripts.MicrosoftActivationScripts" {
			# The key was shipped but never read: the URL was hard-coded.
			$global:Configuration = @{ BootstrapConfig = @{ ExternalScripts = @{ MicrosoftActivationScripts = 'https://example.test/mas' } } }

			Start-MicrosoftActivationScripts -Override

			Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { [string]$Uri -eq 'https://example.test/mas' }
		}

		It "falls back to the built-in URL when the key is empty" {
			$global:Configuration = @{ BootstrapConfig = @{ ExternalScripts = @{ MicrosoftActivationScripts = '' } } }

			Start-MicrosoftActivationScripts -Override

			Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { [string]$Uri -like 'https://get.activated.win*' }
		}
	}
}
