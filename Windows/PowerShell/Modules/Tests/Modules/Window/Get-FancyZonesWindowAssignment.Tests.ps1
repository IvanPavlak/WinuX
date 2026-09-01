#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-FancyZonesWindowAssignment.ps1"

	# Compile the native layer exactly as Window.psm1 does, so this suite also guards
	# WindowNative.cs against compile regressions.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}
}

Describe "Get-FancyZonesWindowAssignment" {
	It "exposes the native assignment entry point" {
		[WindowModule.Native].GetMethod('GetWindowZoneAssignment') | Should -Not -BeNullOrEmpty
	}

	It "returns zero for a null handle" {
		Get-FancyZonesWindowAssignment -WindowHandle ([IntPtr]::Zero) | Should -Be ([uint64]0)
	}

	It "returns zero for an unreadable handle instead of throwing" {
		{ $script:bogusMask = Get-FancyZonesWindowAssignment -WindowHandle ([IntPtr]0x7FFFFFFF) } | Should -Not -Throw
		$script:bogusMask | Should -Be ([uint64]0)
	}

	It "returns a non-negative mask for every real window" {
		$windows = @([WindowModule.Native]::GetAllWindows())

		if ($windows.Count -eq 0) {
			# CI runners have no interactive desktop, so there is no window to inspect.
			Set-ItResult -Skipped -Because "this session has no visible windows to inspect"
			return
		}

		foreach ($window in $windows) {
			$mask = Get-FancyZonesWindowAssignment -WindowHandle $window.Handle
			$mask | Should -BeOfType [uint64]
		}
	}
}
