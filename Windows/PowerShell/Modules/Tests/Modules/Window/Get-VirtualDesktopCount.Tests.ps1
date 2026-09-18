#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-VirtualDesktopCount.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
}

Describe "Get-VirtualDesktopCount and Get-CurrentVirtualDesktopIndex" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		$null = New-FakeVirtualDesktopSession -DesktopCount 3 -CurrentIndex 2
	}

	It "counts the desktops the manager reports" {
		Get-VirtualDesktopCount | Should -Be 3
		Get-VirtualDesktopCount | Should -BeOfType [int]
	}

	It "reports the desktop currently on screen, 0-based" {
		Get-CurrentVirtualDesktopIndex | Should -Be 2
	}

	It "reports desktop 0 as 0, not as nothing" {
		$global:FakeVirtualDesktop.CurrentIndex = 0
		Get-CurrentVirtualDesktopIndex | Should -Be 0
	}

	It "reads through the operation seam, so a stale session is reconnected instead of answering with a stale count" {
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1

		Get-VirtualDesktopCount | Should -Be 3
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
	}

	It "throws rather than returning nothing when the manager cannot be reached" {
		$null = New-FakeVirtualDesktopSession -ModuleUnavailable

		{ Get-VirtualDesktopCount } | Should -Throw
		{ Get-CurrentVirtualDesktopIndex } | Should -Throw
	}
}
