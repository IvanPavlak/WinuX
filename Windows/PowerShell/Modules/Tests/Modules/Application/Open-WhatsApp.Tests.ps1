#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-WhatsApp.ps1"
}

Describe "Open-WhatsApp" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with WhatsApp Appx package parameters" {
		Open-WhatsApp

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'WhatsApp' -and
			$ProcessName -eq 'WhatsApp.Root' -and
			$StartMethod -eq 'AppxPackage' -and
			$PackageName -eq 'WhatsApp'
		}
	}

	It "requires a visible main window so the windowless push notification host is ignored" {
		Open-WhatsApp

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$RequireMainWindow -eq $true
		}
	}
}
