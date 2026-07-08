#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Confirm-WindowForeground.ps1"
}

Describe "Confirm-WindowForeground" {
	BeforeEach {
		Mock Start-Sleep { }
	}

	It "requires a window handle" {
		(Get-Command Confirm-WindowForeground).Parameters['WindowHandle'].Attributes.Mandatory |
			Should -Contain $true
	}

	It "returns false for a handle that can never become foreground" {
		# A bogus, non-zero handle can never match the real foreground window, so every
		# attempt fails and the helper reports failure rather than hanging.
		$result = Confirm-WindowForeground -WindowHandle ([IntPtr]0xDEADBEEF) -MaxAttempts 3

		$result | Should -BeFalse
	}

	It "settles once per attempt before giving up" {
		Confirm-WindowForeground -WindowHandle ([IntPtr]0xDEADBEEF) -MaxAttempts 3 | Out-Null

		# One settle delay per focus attempt.
		Should -Invoke Start-Sleep -Times 3 -Exactly
	}

	It "honors a custom maximum attempt count" {
		Confirm-WindowForeground -WindowHandle ([IntPtr]0xDEADBEEF) -MaxAttempts 1 | Out-Null

		Should -Invoke Start-Sleep -Times 1 -Exactly
	}

	It "never settles for less than the 10ms floor" {
		Confirm-WindowForeground -WindowHandle ([IntPtr]0xDEADBEEF) -BaseSettleMs 0 -MaxAttempts 1 | Out-Null

		Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -ge 10 }
	}
}
