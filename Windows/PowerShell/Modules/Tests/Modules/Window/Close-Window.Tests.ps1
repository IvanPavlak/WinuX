#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Compile the native layer exactly as Window.psm1 does. PostClose is a static method and
	# cannot be mocked, so every handle used below belongs to no window: real HWNDs are
	# multiples of four, and 424243 / 424247 are odd, so the WM_CLOSE can reach nothing.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	. "$FunctionsPath\Close-Window.ps1"
}

Describe "Close-Window" {
	It "skips a zero handle and reports nothing posted" {
		Close-Window -Handle ([IntPtr]::Zero) | Should -Be 0
	}

	It "reports zero for a handle no window owns, without throwing" {
		# PostMessage returns false for an invalid window handle.
		{ Close-Window -Handle ([IntPtr]424243) } | Should -Not -Throw
		Close-Window -Handle ([IntPtr]424243) | Should -Be 0
	}

	It "accepts several handles in one call" {
		Close-Window -Handle @([IntPtr]424243, [IntPtr]::Zero, [IntPtr]424247) | Should -Be 0
	}

	It "binds the Handle property of piped window objects" {
		$windows = @(
			[PSCustomObject]@{ Handle = [IntPtr]424243; Title = 'A' },
			[PSCustomObject]@{ Handle = [IntPtr]424247; Title = 'B' }
		)

		{ $windows | Close-Window } | Should -Not -Throw
		($windows | Close-Window) | Should -Be 0
	}

	It "exposes WM_CLOSE through the native seam rather than a private declaration" {
		[WindowModule.Native]::WM_CLOSE | Should -Be 0x0010
		(Get-Command Close-Window).Definition | Should -Not -Match 'DllImport'
	}
}
