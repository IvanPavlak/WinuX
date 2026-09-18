#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Compile the native layer exactly as Window.psm1 does; the probe is a static call.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	. "$FunctionsPath\Test-WindowVisible.ps1"

	# A real window owned by this process, never shown: IsWindow holds, IsWindowVisible does
	# not, which is exactly the "hidden before teardown" state the probe must read as closed.
	Add-Type -AssemblyName System.Windows.Forms
	$script:HiddenForm = New-Object System.Windows.Forms.Form
	$script:HiddenForm.ShowInTaskbar = $false
	$script:HiddenHandle = $script:HiddenForm.Handle
}

AfterAll {
	if ($script:HiddenForm) { $script:HiddenForm.Dispose() }
}

Describe "Test-WindowVisible" {
	It "is false for a zero handle" {
		Test-WindowVisible -Handle ([IntPtr]::Zero) | Should -BeFalse
	}

	It "is false for a handle no window owns" {
		Test-WindowVisible -Handle ([IntPtr]424243) | Should -BeFalse
	}

	It "is false for a live window that is hidden" {
		[WindowModule.Native]::IsWindow($script:HiddenHandle) | Should -BeTrue
		Test-WindowVisible -Handle $script:HiddenHandle | Should -BeFalse
	}

	It "is true for the window hosting this process when it is visible" {
		$hostHandle = (Get-Process -Id $PID).MainWindowHandle
		if ($hostHandle -eq [IntPtr]::Zero) {
			Set-ItResult -Skipped -Because "the test host has no visible main window"
			return
		}

		Test-WindowVisible -Handle $hostHandle | Should -BeTrue
	}
}
