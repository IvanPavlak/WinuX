#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-RerunLastCommandExit.ps1"
}

Describe "Invoke-RerunLastCommandExit" {
	BeforeEach {
		$script:exitInvoked = $false
		$script:RerunLastCommandExitAction = {
			$script:exitInvoked = $true
		}
	}

	AfterEach {
		$script:RerunLastCommandExitAction = $null
	}

	It "invokes the configured exit seam action when present" {
		Invoke-RerunLastCommandExit

		$script:exitInvoked | Should -BeTrue
	}
}
