#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Window\Functions"
	. "$FunctionsPath\Send-FancyZonesLayoutShortcut.ps1"
}

Describe "Send-FancyZonesLayoutShortcut" {
	# The function sends real input (cursor, foreground, Win+Ctrl+Alt+N), so only the parameter
	# validation is exercised here: every rejection below happens before the body runs.
	It "rejects a layout number outside the FancyZones hotkey range of 0-9" {
		{ Send-FancyZonesLayoutShortcut -LayoutNumber 10 -MonitorX 0 -MonitorY 0 -MonitorWidth 100 -MonitorHeight 100 } | Should -Throw
		{ Send-FancyZonesLayoutShortcut -LayoutNumber -1 -MonitorX 0 -MonitorY 0 -MonitorWidth 100 -MonitorHeight 100 } | Should -Throw
	}

	It "rejects a monitor coordinate that is not an integer" {
		{ Send-FancyZonesLayoutShortcut -LayoutNumber 1 -MonitorX 'left' -MonitorY 0 -MonitorWidth 100 -MonitorHeight 100 } | Should -Throw
	}
}
