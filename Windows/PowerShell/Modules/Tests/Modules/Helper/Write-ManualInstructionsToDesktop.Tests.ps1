#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Write-ManualInstructionsToDesktop.ps1"
}

Describe "Write-ManualInstructionsToDesktop" {
	BeforeEach {
		Mock Out-File { }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
	}

	It "writes instructions document to a desktop file path" {
		# This used to assert Should -Throw: Pester 5's mock proxy dropped the argument
		# transformation on Out-File's -Encoding, so the string 'UTF8' failed to bind and the
		# test was green off a mocking artifact, not off the function. Pester 6 binds it fine.
		Write-ManualInstructionsToDesktop -FileName "setup.txt" -Title "Setup" -Content "Step 1"

		# Mirror the function's fallback chain: on runner profiles without a Desktop folder,
		# plain GetFolderPath returns an empty string that Join-Path rejects.
		$expectedDesktop = [Environment]::GetFolderPath("Desktop")
		if ([string]::IsNullOrWhiteSpace($expectedDesktop)) {
			$expectedDesktop = [Environment]::GetFolderPath("Desktop", "DoNotVerify")
		}
		if ([string]::IsNullOrWhiteSpace($expectedDesktop)) {
			$expectedDesktop = Join-Path $env:USERPROFILE "Desktop"
		}

		Should -Invoke Out-File -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq (Join-Path $expectedDesktop "setup.txt")
		}
		Should -Invoke Write-LogSuccess -Times 1 -Exactly
	}
}
