#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resize-Windows.ps1"
}

Describe "Resize-Windows" {
	BeforeEach {
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 15 }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Get-MonitorInfo { @() }
		Mock Clear-WindowCache { }
		Mock Get-CachedWindows { @() }
		Mock Set-WindowPosition { $true }
		Mock Write-Host { }
		Mock Write-Warning { }
	}

	It "returns early when monitor info is not available" {
		Resize-Windows -Percent 80

		Should -Invoke Get-MonitorInfo -Times 1
		Should -Invoke Write-Warning -Times 1
		Should -Invoke Get-CachedWindows -Times 0
	}

	It "stores summary in script state without pipeline output" {
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{
					Left = 0; Top = 0; Right = 1920; Bottom = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
					IsPrimary = $true; DeviceName = 'DISPLAY1'
				})
		}
		Mock Get-CachedWindows {
			@([PSCustomObject]@{
					Handle = [IntPtr]1; Title = 'Test Window'; ProcessName = 'TestApp'
					Width = 800; Height = 600; Left = 100; Top = 100
				})
		}

		$result = @(Resize-Windows -WindowHandle ([IntPtr]1))
		$state = $script:LastResizeWindowsResult

		$result.Count | Should -Be 0
		$state.ResizedCount | Should -Be 1
		$state.SkippedCount | Should -Be 0
		$state.FailedWindows.Count | Should -Be 0
	}

	It "delegates filtering to Get-WindowHandle when ProcessName is provided" {
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{
					Left = 0; Top = 0; Right = 1920; Bottom = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
					IsPrimary = $true; DeviceName = 'DISPLAY1'
				})
		}
		# Get-WindowHandle is the shared filtering path (same as Move-Windows); mocking it
		# verifies Resize-Windows delegates rather than re-enumerating via Get-CachedWindows.
		Mock Get-WindowHandle {
			@([PSCustomObject]@{
					Handle = [IntPtr]2; Title = 'Chrome'; ProcessName = 'chrome'
					Width = 800; Height = 600; Left = 100; Top = 100
				})
		}

		Resize-Windows -ProcessName "chrome"

		Should -Invoke Get-WindowHandle -Times 1 -ParameterFilter { $ProcessName -eq 'chrome' }
		Should -Invoke Get-CachedWindows -Times 0
		Should -Invoke Set-WindowPosition -Times 1 -ParameterFilter { $WindowHandle -eq [IntPtr]2 }
	}
}
