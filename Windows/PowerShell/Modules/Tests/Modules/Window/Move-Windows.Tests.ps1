#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Move-Windows.ps1"

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopCount -ErrorAction SilentlyContinue)) {
		function Get-DesktopCount { [CmdletBinding()] param() }
		function Switch-Desktop { [CmdletBinding()] param($Desktop) }
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Move-Windows" {
	BeforeEach {
		Mock Import-VirtualDesktopModule { $false }
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Clear-WindowCache { }
		Mock Get-CachedWindows { @() }
		Mock Get-MonitorInfo { @() }
		Mock Get-MonitorSpecs { $null }
		Mock Set-WindowPosition { $true }
		Mock Invoke-WithOptionalRetry {
			param($EnableRetry, $ScriptBlock, $MaxAttempts, $InitialDelayMs)
			& $ScriptBlock
		}
	}

	It "returns early when virtual desktop module is unavailable" {
		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Import-VirtualDesktopModule -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "switches focus to the target desktop after moving windows" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Switch-Desktop { }

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Switch-Desktop -Times 1 -ParameterFilter { $Desktop -eq 0 }
	}

	It "repositions windows on the target monitor when -Monitor is specified" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Get-DesktopFromWindow { [PSCustomObject]@{ Name = 'Desktop1' } }
		Mock Get-DesktopIndex { 0 }
		Mock Switch-Desktop { }
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle      = [IntPtr]1111
					Title       = 'Test Window'
					ProcessName = 'notepad'
					Left        = 200
					Top         = 200
					Width       = 800
					Height      = 600
				}
			)
		}
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{
					DeviceName     = '\\.\DISPLAY1'
					Left           = 0
					Top            = 0
					Right          = 1920
					Bottom         = 1080
					Width          = 1920
					Height         = 1080
					WorkAreaLeft   = 0
					WorkAreaTop    = 0
					WorkAreaRight  = 1920
					WorkAreaBottom = 1040
					WorkAreaWidth  = 1920
					WorkAreaHeight = 1040
					IsPrimary      = $true
				},
				[PSCustomObject]@{
					DeviceName     = '\\.\DISPLAY2'
					Left           = 1920
					Top            = 0
					Right          = 3840
					Bottom         = 1080
					Width          = 1920
					Height         = 1080
					WorkAreaLeft   = 1920
					WorkAreaTop    = 0
					WorkAreaRight  = 3840
					WorkAreaBottom = 1040
					WorkAreaWidth  = 1920
					WorkAreaHeight = 1040
					IsPrimary      = $false
				}
			)
		}

		{ Move-Windows -VirtualDesktop 1 -Monitor 2 } | Should -Not -Throw

		Should -Invoke Set-WindowPosition -Times 1 -ParameterFilter {
			$WindowHandle -eq [IntPtr]1111 -and $X -ge 1920 -and $Y -ge 0
		}
	}

	It "returns early when monitor index is out of range" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; IsPrimary = $true },
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; IsPrimary = $false }
			)
		}
		Mock Switch-Desktop { }

		{ Move-Windows -VirtualDesktop 1 -Monitor 5 } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Switch-Desktop -Times 0
	}
}
