#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	$script:CanvasInfo = [PSCustomObject]@{
		'ref-width'  = 2000
		'ref-height' = 1000
		zones        = @(
			[PSCustomObject]@{ X = 0; Y = 0; width = 1000; height = 1000 }
			[PSCustomObject]@{ X = 1000; Y = 0; width = 1000; height = 500 }
			[PSCustomObject]@{ X = 1000; Y = 500; width = 666; height = 500 }
		)
	}
}

Describe "Format-CanvasZoneListing" {
	It "Should render one line per zone with percentages of the ref rect" {
		$result = Format-CanvasZoneListing -LayoutInfo $script:CanvasInfo

		$lines = $result -split "`n"
		$lines.Count | Should -Be 3
		$lines[0] | Should -Match "Zone 0: x=0% y=0% w=50% h=100%"
		$lines[1] | Should -Match "Zone 1: x=50% y=0% w=50% h=50%"
	}

	It "Should round fractional percentages to one decimal" {
		$result = Format-CanvasZoneListing -LayoutInfo $script:CanvasInfo

		# 666 / 2000 = 33.3%
		($result -split "`n")[2] | Should -Match "w=33\.3%"
	}

	It "Should include zone names from the ZoneNames map" {
		$result = Format-CanvasZoneListing -LayoutInfo $script:CanvasInfo -ZoneNames @{ 0 = "Left"; 1 = "Top-Right" }

		$result | Should -Match 'Zone 0 \[Left\]:'
		$result | Should -Match 'Zone 1 \[Top-Right\]:'
		$result | Should -Match 'Zone 2: '
	}

	It "Should append zone content labels" {
		$result = Format-CanvasZoneListing -LayoutInfo $script:CanvasInfo -ZoneContent @{ 0 = @("Code", "Firefox") }

		$result | Should -Match "Zone 0.*=> Code, Firefox"
	}

	It "Should report an undrawable layout instead of throwing" {
		$badInfo = [PSCustomObject]@{ 'ref-width' = 0; 'ref-height' = 1000; zones = @() }

		$result = Format-CanvasZoneListing -LayoutInfo $badInfo

		$result | Should -Match "no drawable zones"
	}
}
