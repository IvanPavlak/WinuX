#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Create-CenteredBorder.ps1"
}

Describe "Create-CenteredBorder" {
	Context "Border Without Title" {
		It "Should create a full-width border line" {
			$result = Create-CenteredBorder

			$result | Should -Not -BeNullOrEmpty
			$result | Should -Match '^=+$'
		}

		It "Should use custom border character" {
			$result = Create-CenteredBorder -BorderChar '-'

			$result | Should -Match '^-+$'
		}
	}

	Context "Border With Title" {
		It "Should include the title in brackets" {
			$result = Create-CenteredBorder -Title "Test"

			$result | Should -Match '\[Test\]'
		}

		It "Should pad title with spaces" {
			$result = Create-CenteredBorder -Title "Test"

			$result | Should -Match '= \[Test\] ='
		}

		It "Should center the title within the border" {
			$result = Create-CenteredBorder -Title "Hello"

			# Title should be roughly centered - left and right padding should be similar
			$titleIndex = $result.IndexOf('[Hello]')
			$titleIndex | Should -BeGreaterThan 10  # Should not be at the start
		}
	}
}
