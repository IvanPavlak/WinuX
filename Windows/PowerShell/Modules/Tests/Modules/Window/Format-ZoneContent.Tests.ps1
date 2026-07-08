#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Format-ZoneContent" {
	Context "Basic Formatting" {
		It "Should pass through short content unchanged" {
			$result = Format-ZoneContent -Content @("Test") -Width 20

			$result | Should -Be @("Test")
		}

		It "Should handle multiple items" {
			$result = Format-ZoneContent -Content @("Process", "Title") -Width 20

			$result.Count | Should -Be 2
			$result[0] | Should -Be "Process"
			$result[1] | Should -Be "Title"
		}
	}

	Context "Truncation" {
		It "Should truncate long text with ellipsis" {
			$result = Format-ZoneContent -Content @("VeryLongProcessName") -Width 10

			$result[0] | Should -Be "VeryLongP…"
			$result[0].Length | Should -Be 10
		}

		It "Should handle exactly matching width without truncation" {
			$result = Format-ZoneContent -Content @("Exactly10!") -Width 10

			$result[0] | Should -Be "Exactly10!"
		}
	}

	Context "Multi-line Content" {
		It "Should split content with embedded newlines" {
			$result = Format-ZoneContent -Content @("Line1`nLine2") -Width 20

			$result.Count | Should -Be 2
			$result[0] | Should -Be "Line1"
			$result[1] | Should -Be "Line2"
		}
	}

	Context "Edge Cases" {
		It "Should return empty array for empty input" {
			$result = Format-ZoneContent -Content @() -Width 10

			$result.Count | Should -Be 0
		}
	}
}
