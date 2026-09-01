#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Clear-FancyZonesWindowAssignment.ps1"

	# Compile the native layer exactly as Window.psm1 does, so this suite also guards
	# WindowNative.cs against compile regressions.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}
}

Describe "Clear-FancyZonesWindowAssignment" {
	# NOTE: no test clears a real window's marker - that would unsnap live windows on the
	# tester's desktop. Unreadable-handle contracts cover the function's failure surface.

	It "exposes the native clear entry point" {
		[WindowModule.Native].GetMethod('ClearWindowZoneAssignment') | Should -Not -BeNullOrEmpty
	}

	It "returns false for a null handle" {
		Clear-FancyZonesWindowAssignment -WindowHandle ([IntPtr]::Zero) | Should -BeFalse
	}

	It "returns false for an unreadable handle instead of throwing" {
		{ $script:bogusCleared = Clear-FancyZonesWindowAssignment -WindowHandle ([IntPtr]0x7FFFFFFF) } | Should -Not -Throw
		$script:bogusCleared | Should -BeFalse
	}
}
