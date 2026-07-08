#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-CenteredWindowPercent.ps1"

	# The defaults shipped in Configuration.psd1 (KillAllTerminalSizing).
	$script:Sizing = @{
		TargetWidthPx    = 1376
		TargetHeightPx   = 700
		MinWidthPercent  = 25
		MaxWidthPercent  = 72
		MinHeightPercent = 35
		MaxHeightPercent = 75
	}

	function Resolve-WithDefaults {
		param([int]$WorkAreaWidth, [int]$WorkAreaHeight)
		Resolve-CenteredWindowPercent `
			-WorkAreaWidth $WorkAreaWidth -WorkAreaHeight $WorkAreaHeight `
			-TargetWidthPx $script:Sizing.TargetWidthPx -TargetHeightPx $script:Sizing.TargetHeightPx `
			-MinWidthPercent $script:Sizing.MinWidthPercent -MaxWidthPercent $script:Sizing.MaxWidthPercent `
			-MinHeightPercent $script:Sizing.MinHeightPercent -MaxHeightPercent $script:Sizing.MaxHeightPercent
	}
}

Describe "Resolve-CenteredWindowPercent" {
	It "leaves the ultrawide at the legacy 40/50" {
		$result = Resolve-WithDefaults -WorkAreaWidth 3440 -WorkAreaHeight 1400

		$result.WidthPercent | Should -Be 40
		$result.HeightPercent | Should -Be 50
	}

	It "grows the fraction on a 1920x1080 laptop panel (width hits the cap)" {
		# 1376/1920 = 71.7 -> 72 (Max); 700/1040 = 67.3 -> 67
		$result = Resolve-WithDefaults -WorkAreaWidth 1920 -WorkAreaHeight 1040

		$result.WidthPercent | Should -Be 72
		$result.HeightPercent | Should -Be 67
	}

	It "yields a near-constant physical size on a 2560x1600 panel" {
		# 1376/2560 = 53.75 -> 54; 700/1560 = 44.9 -> 45
		$result = Resolve-WithDefaults -WorkAreaWidth 2560 -WorkAreaHeight 1560

		$result.WidthPercent | Should -Be 54
		$result.HeightPercent | Should -Be 45
	}

	It "binds both caps on a tiny 1366x768 panel" {
		# Both computed percentages exceed the Max clamps.
		$result = Resolve-WithDefaults -WorkAreaWidth 1366 -WorkAreaHeight 728

		$result.WidthPercent | Should -Be 72
		$result.HeightPercent | Should -Be 75
	}

	It "falls back to the Max clamp on a non-positive work area" {
		$result = Resolve-WithDefaults -WorkAreaWidth 0 -WorkAreaHeight 0

		$result.WidthPercent | Should -Be 72
		$result.HeightPercent | Should -Be 75
	}

	It "never returns a percentage outside Center-Windows' [10,100] range" {
		# Misconfigured clamps (Min below 10, Max above 100) must still be hard-clamped.
		$result = Resolve-CenteredWindowPercent `
			-WorkAreaWidth 1920 -WorkAreaHeight 1080 `
			-TargetWidthPx 100000 -TargetHeightPx 1 `
			-MinWidthPercent 0 -MaxWidthPercent 999 `
			-MinHeightPercent 0 -MaxHeightPercent 999

		$result.WidthPercent | Should -BeLessOrEqual 100
		$result.WidthPercent | Should -BeGreaterOrEqual 10
		$result.HeightPercent | Should -BeLessOrEqual 100
		$result.HeightPercent | Should -BeGreaterOrEqual 10
	}

	It "applies the lower clamp on an unexpectedly huge work area" {
		# 1376/8000 = 17.2 -> below MinWidthPercent 25, so clamps up to 25.
		$result = Resolve-WithDefaults -WorkAreaWidth 8000 -WorkAreaHeight 4000

		$result.WidthPercent | Should -Be 25
		$result.HeightPercent | Should -Be 35
	}
}
