#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-InsetWindowBounds.ps1"
}

Describe "Get-InsetWindowBounds" {
	It "returns inset bounds biased off the zone center for default inset" {
		$result = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1000 -TargetHeight 800

		$result.AdjustedWidth | Should -Be 900
		$result.AdjustedHeight | Should -Be 720
		# Centered would be (50, 40); the deliberate InsetCenterBiasPx offset shifts it.
		$result.AdjustedX | Should -Be (50 + $script:InsetCenterBiasPx)
		$result.AdjustedY | Should -Be (40 + $script:InsetCenterBiasPx)
	}

	It "never centers the window exactly on the zone center" {
		# Load-bearing, not cosmetic: FancyZones' Win+Arrow is a RELATIVE move and only
		# snaps a window into the zone it occupies while it does not already recognise the
		# window as zoned. A window centered exactly on its zone is recognised, so every
		# arrow key throws it into the neighbouring zone and the slow shift-drag fallback
		# has to recover it. Keep this above zero.
		$script:InsetCenterBiasPx | Should -BeGreaterThan 0

		$result = Get-InsetWindowBounds -TargetX 100 -TargetY 200 -TargetWidth 1143 -TargetHeight 716
		$windowCenterX = $result.AdjustedX + ($result.AdjustedWidth / 2)
		$windowCenterY = $result.AdjustedY + ($result.AdjustedHeight / 2)

		$windowCenterX | Should -Not -Be $result.ZoneCenterX
		$windowCenterY | Should -Not -Be $result.ZoneCenterY
	}

	It "keeps the inset window fully inside the target zone" {
		$result = Get-InsetWindowBounds -TargetX 2294 -TargetY -719 -TargetWidth 1143 -TargetHeight 716

		$result.AdjustedX | Should -BeGreaterThan 2294
		$result.AdjustedY | Should -BeGreaterThan -719
		$result.AdjustedRight | Should -BeLessThan (2294 + 1143)
		$result.AdjustedBottom | Should -BeLessThan (-719 + 716)
	}

	It "enforces minimum size of 1 pixel" {
		$result = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1 -TargetHeight 1 -InsetPercent 0.49

		$result.AdjustedWidth | Should -BeGreaterOrEqual 1
		$result.AdjustedHeight | Should -BeGreaterOrEqual 1
	}
}
