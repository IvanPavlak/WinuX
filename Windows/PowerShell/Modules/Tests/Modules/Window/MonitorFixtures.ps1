<#
	.SYNOPSIS
		Shared monitor fixtures for the Window module's monitor-aware tests.

	.DESCRIPTION
		Dot-source this file from a test's BeforeAll to build monitor sets shaped like
		Get-MonitorInfo output.

		It exists because every monitor fixture in this folder used to be a hand-rolled
		primary-plus-one-secondary pair, so nothing exercised three or more displays - the case
		where a positional monitor label stops being unambiguous. With two displays there is
		exactly one non-primary monitor, so "Secondary" is correct whatever order the monitors
		were enumerated in, and a label bug cannot show up.

		The fixture is deliberately built so ENUMERATION order differs from PHYSICAL order (see
		New-MonitorFixture), which is what Get-MonitorSpecs' spatial sort has to normalize.

		This file is NOT named *.Tests.ps1 on purpose: the harness discovers only that pattern,
		so this stays a helper and never becomes a test target.
#>

function New-MonitorFixture {
	<#
	.SYNOPSIS
		Builds a monitor set in Get-MonitorInfo's shape.

	.DESCRIPTION
		Three panels, deliberately mixed-resolution, laid out left to right as
		DISPLAY2 | DISPLAY1 (primary) | DISPLAY3:

		  DISPLAY1  primary  3440x1440 at (0, 0)       work 3440x1400  (40px taskbar)
		  DISPLAY2           1920x1080 at (-1920, 0)   work 1920x1080  (no taskbar)
		  DISPLAY3           2560x1440 at (3440, -180) work 2560x1400  (40px taskbar)

		So the expected labels for the full set are Primary => DISPLAY1,
		Secondary => DISPLAY2 (leftmost non-primary) and Monitor3 => DISPLAY3.

	.PARAMETER Count
		How many displays to return: 1 (primary only), 2 (primary + DISPLAY2), or 3.

	.PARAMETER EnumerationOrder
		The order the monitors come back in, standing in for Screen.AllScreens order:
		- Scrambled (default) - DISPLAY3, DISPLAY2, DISPLAY1: neither physical nor primary-first
		- Physical             - left to right, the order labels are assigned in
		- Reversed            - physical order reversed

		Defaulting to Scrambled means a test that does not think about ordering still catches a
		regression that reintroduces enumeration-order labeling.

	.EXAMPLE
		$monitors = New-MonitorFixture -Count 3
		$specs = Get-MonitorSpecs -MonitorInfo $monitors -AsHashtable
		$specs.Secondary.DeviceName | Should -Be '\\.\DISPLAY2'

	.EXAMPLE
		# Same displays, three different enumeration orders, one set of labels.
		'Physical', 'Scrambled', 'Reversed' | ForEach-Object {
			(Get-MonitorSpecs -MonitorInfo (New-MonitorFixture -EnumerationOrder $_) -AsHashtable).Monitor3.DeviceName
		}
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateRange(1, 3)]
		[int]$Count = 3,

		[Parameter()]
		[ValidateSet('Scrambled', 'Physical', 'Reversed')]
		[string]$EnumerationOrder = 'Scrambled'
	)

	$display1 = [PSCustomObject]@{
		DeviceName     = '\\.\DISPLAY1'
		Left           = 0
		Top            = 0
		Right          = 3440
		Bottom         = 1440
		Width          = 3440
		Height         = 1440
		WorkAreaLeft   = 0
		WorkAreaTop    = 0
		WorkAreaRight  = 3440
		WorkAreaBottom = 1400
		WorkAreaWidth  = 3440
		WorkAreaHeight = 1400
		IsPrimary      = $true
	}

	$display2 = [PSCustomObject]@{
		DeviceName     = '\\.\DISPLAY2'
		Left           = -1920
		Top            = 0
		Right          = 0
		Bottom         = 1080
		Width          = 1920
		Height         = 1080
		WorkAreaLeft   = -1920
		WorkAreaTop    = 0
		WorkAreaRight  = 0
		WorkAreaBottom = 1080
		WorkAreaWidth  = 1920
		WorkAreaHeight = 1080
		IsPrimary      = $false
	}

	$display3 = [PSCustomObject]@{
		DeviceName     = '\\.\DISPLAY3'
		Left           = 3440
		Top            = -180
		Right          = 6000
		Bottom         = 1260
		Width          = 2560
		Height         = 1440
		WorkAreaLeft   = 3440
		WorkAreaTop    = -180
		WorkAreaRight  = 6000
		WorkAreaBottom = 1220
		WorkAreaWidth  = 2560
		WorkAreaHeight = 1400
		IsPrimary      = $false
	}

	# Physical (left to right) order for each supported count.
	$physical = switch ($Count) {
		1 { @($display1) }
		2 { @($display2, $display1) }
		3 { @($display2, $display1, $display3) }
	}

	switch ($EnumerationOrder) {
		'Physical' { return @($physical) }
		'Reversed' { return @($physical[($physical.Count - 1)..0]) }
		default {
			# Scrambled: highest device number first, primary last.
			return @($physical | Sort-Object -Property @{ Expression = { $_.DeviceName }; Descending = $true })
		}
	}
}

function Get-ExpectedMonitorLabel {
	<#
	.SYNOPSIS
		The label New-MonitorFixture's displays are expected to receive.

	.DESCRIPTION
		Keeps the expected label-to-device-name mapping in one place so a test asserts against
		the documented contract rather than restating it. Mirrors the layout described in
		New-MonitorFixture: the primary display is Primary, and the non-primary displays take
		Secondary, Monitor3, ... in left-to-right order.

	.PARAMETER Label
		"Primary", "Secondary" or "Monitor3".

	.OUTPUTS
		The device name expected to carry that label.

	.EXAMPLE
		(Get-MonitorSpecs -MonitorInfo (New-MonitorFixture) -AsHashtable).Monitor3.DeviceName |
			Should -Be (Get-ExpectedMonitorLabel -Label 'Monitor3')
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('Primary', 'Secondary', 'Monitor3')]
		[string]$Label
	)

	switch ($Label) {
		'Primary' { return '\\.\DISPLAY1' }
		'Secondary' { return '\\.\DISPLAY2' }
		'Monitor3' { return '\\.\DISPLAY3' }
	}
}
