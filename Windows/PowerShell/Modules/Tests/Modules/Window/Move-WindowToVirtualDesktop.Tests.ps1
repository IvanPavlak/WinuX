#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Move-WindowToVirtualDesktop.ps1"

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopCount -ErrorAction SilentlyContinue)) {
		function Get-DesktopCount { [CmdletBinding()] param() }
		function Get-Desktop { [CmdletBinding()] param($Index) }
		function Move-Window { [CmdletBinding()] param($Desktop, $Hwnd) }
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Move-WindowToVirtualDesktop" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Verbose { }
		Mock Write-Warning { }
		Mock Write-Error { }
		Mock Start-Sleep { }

		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 3 }
		Mock Get-Desktop { [PSCustomObject]@{ Index = $Index } }
		Mock Move-Window { }
		Mock Get-DesktopFromWindow { [PSCustomObject]@{ Index = 1 } }
		Mock Get-DesktopIndex { param($Desktop) $Desktop.Index }

		$script:WindowModuleDelays = @{ VirtualDesktopMs = 0 }
	}

	It "uses the provided 0-based desktop index for desktop lookup and move verification" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 1

		$result | Should -BeTrue
		Should -Invoke Get-Desktop -Times 1 -Exactly -ParameterFilter { $Index -eq 1 }
		Should -Invoke Move-Window -Times 1 -Exactly -ParameterFilter {
			$Desktop.Index -eq 1 -and $Hwnd -eq 1234
		}
	}

	It "returns false and stops before move when desktop number equals desktop count (upper bound out of range)" {
		Mock Get-DesktopCount { 2 }

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		$result | Should -BeFalse
		Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter { $Message -like "*out of range*" }
		Should -Invoke Get-Desktop -Times 0
		Should -Invoke Move-Window -Times 0
	}

	It "returns false and stops before move when desktop number is negative" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber -1

		$result | Should -BeFalse
		Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter { $Message -like "*out of range*" }
		Should -Invoke Get-Desktop -Times 0
		Should -Invoke Move-Window -Times 0
	}
}
