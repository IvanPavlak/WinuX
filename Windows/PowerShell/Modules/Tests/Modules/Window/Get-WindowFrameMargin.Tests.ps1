#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-WindowFrameMargin.ps1"

	# Compile the native layer exactly as Window.psm1 does, so this suite also guards
	# WindowNative.cs against compile regressions.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# The sanity cap the function applies; asserted against live readings below.
	$script:SanityCapPx = 50
}

Describe "Get-WindowFrameMargin" {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "exposes the native visible-frame entry point" {
		[WindowModule.Native].GetMethod('GetExtendedFrameBounds') | Should -Not -BeNullOrEmpty
	}

	It "returns a margin for every edge" {
		$margin = Get-WindowFrameMargin -WindowHandle ([IntPtr]::Zero)

		$margin.PSObject.Properties.Name | Should -Contain 'Left'
		$margin.PSObject.Properties.Name | Should -Contain 'Top'
		$margin.PSObject.Properties.Name | Should -Contain 'Right'
		$margin.PSObject.Properties.Name | Should -Contain 'Bottom'
	}

	It "falls back to zero margins for a null handle" {
		$margin = Get-WindowFrameMargin -WindowHandle ([IntPtr]::Zero)

		$margin.Left | Should -Be 0
		$margin.Top | Should -Be 0
		$margin.Right | Should -Be 0
		$margin.Bottom | Should -Be 0
	}

	It "falls back to zero margins when the native reads fail" {
		# A handle that cannot name a window: both GetWindowRect and the DWM read fail, which
		# is the contract that keeps a caller's arithmetic on the uncompensated rectangle.
		$margin = Get-WindowFrameMargin -WindowHandle ([IntPtr]0x7FFFFFFF)

		$margin.Left | Should -Be 0
		$margin.Top | Should -Be 0
		$margin.Right | Should -Be 0
		$margin.Bottom | Should -Be 0
	}

	It "never throws for an unreadable handle" {
		{ Get-WindowFrameMargin -WindowHandle ([IntPtr]0x7FFFFFFF) } | Should -Not -Throw
	}

	It "reports plausible, non-negative margins for real windows" {
		$windows = @([WindowModule.Native]::GetAllWindows())

		if ($windows.Count -eq 0) {
			# CI runners have no interactive desktop, so there is no window to measure.
			Set-ItResult -Skipped -Because "this session has no visible windows to measure"
			return
		}

		foreach ($window in $windows) {
			$margin = Get-WindowFrameMargin -WindowHandle $window.Handle

			foreach ($edge in @($margin.Left, $margin.Top, $margin.Right, $margin.Bottom)) {
				$edge | Should -BeGreaterOrEqual 0
				$edge | Should -BeLessOrEqual $script:SanityCapPx
			}
		}
	}
}
