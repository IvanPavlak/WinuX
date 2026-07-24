#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Reset-VirtualDesktopComProxy.ps1"

	# Logging shim for stripped sessions (no-op where the Logging module is loaded).
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param($Message, [string]$Style, [switch]$NoLeadingNewline) }
	}
}

Describe "Reset-VirtualDesktopComProxy" {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "returns a boolean and never throws" {
		{ $script:reconnectResult = Reset-VirtualDesktopComProxy } | Should -Not -Throw
		$script:reconnectResult | Should -BeOfType [bool]
	}

	It "reports fresh state when types are absent, and reconnects non-destructively when present" {
		# Environment-adaptive on purpose: without the VirtualDesktop module the
		# compiled types do not exist (nothing to reconnect => $true); with them
		# loaded and the shell healthy, a reconnect must rebuild the proxies and
		# leave the module fully functional.
		$desktopType = ([System.Management.Automation.PSTypeName]'VirtualDesktop.Desktop').Type

		$result = Reset-VirtualDesktopComProxy
		$result | Should -BeTrue

		if ($desktopType) {
			{ [void]$desktopType.GetProperty('Count').GetValue($null) } | Should -Not -Throw
		}
	}
}
