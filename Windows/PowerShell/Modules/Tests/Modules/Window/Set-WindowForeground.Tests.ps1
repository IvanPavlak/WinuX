#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Compile the native layer exactly as Window.psm1 does. SetForegroundWindow is a static
	# method and cannot be mocked, so the handle used below belongs to no window: real HWNDs
	# are multiples of four and 424243 is odd, so nothing on screen can be activated.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	. "$FunctionsPath\Set-WindowForeground.ps1"
}

Describe "Set-WindowForeground" {
	It "refuses a zero handle without calling Windows" {
		Set-WindowForeground -Handle ([IntPtr]::Zero) | Should -BeFalse
	}

	It "reports false for a handle no window owns, without throwing" {
		{ Set-WindowForeground -Handle ([IntPtr]424243) } | Should -Not -Throw
		Set-WindowForeground -Handle ([IntPtr]424243) | Should -BeFalse
	}

	It "binds the Handle property of a piped window object" {
		([PSCustomObject]@{ Handle = [IntPtr]424243; Title = 'A' } | Set-WindowForeground) | Should -BeFalse
	}

	It "declares no user32 import of its own" {
		(Get-Command Set-WindowForeground).Definition | Should -Not -Match 'DllImport'
	}
}
