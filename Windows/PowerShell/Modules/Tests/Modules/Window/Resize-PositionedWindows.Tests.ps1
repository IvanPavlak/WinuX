#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resize-PositionedWindows.ps1"
}

Describe "Resize-PositionedWindows" {
	BeforeEach {
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 15 }
		$script:LastResizeWindowsResult = [PSCustomObject]@{
			ResizedCount  = 0
			SkippedCount  = 0
			FailedWindows = @()
		}
		Mock Resize-Windows {
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 0
				SkippedCount  = 0
				FailedWindows = @()
			}
		}
		Mock Write-Host { }
	}

	It "returns zeroed result when there are no tracked windows" {
		$script:PositionedWindowHandles = @()

		$result = Resize-PositionedWindows

		$result.ResizedCount | Should -Be 0
		$result.SkippedCount | Should -Be 0
		$result.FailedWindows.Count | Should -Be 0
	}

	It "aggregates resize results from tracked windows" {
		$script:PositionedWindowHandles = @(
			@{ Handle = [IntPtr]1; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100 },
			@{ Handle = [IntPtr]2; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100 }
		)
		Mock Resize-Windows {
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 1
				SkippedCount  = 2
				FailedWindows = @(@{ Handle = [IntPtr]9 })
			}
		}

		$result = Resize-PositionedWindows

		$result.ResizedCount | Should -Be 2
		$result.SkippedCount | Should -Be 4
		$result.FailedWindows.Count | Should -Be 2
		Should -Invoke Resize-Windows -Times 2
	}
}
