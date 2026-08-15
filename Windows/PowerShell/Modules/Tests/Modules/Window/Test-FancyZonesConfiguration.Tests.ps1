#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	# Get-CachedFancyZonesLayouts caches by path for 60 seconds, so every fixture
	# variant gets its own uniquely named file instead of rewriting one path.
	function script:New-TestFancyZonesFixture {
		param (
			[Parameter(Mandatory = $true)][string]$Name,
			[Parameter(Mandatory = $true)][hashtable]$CustomLayouts,
			[hashtable]$LayoutHotkeys
		)

		$layoutsPath = Join-Path $TestDrive "$Name-custom-layouts.json"
		$CustomLayouts | ConvertTo-Json -Depth 10 | Set-Content $layoutsPath

		$hotkeysPath = Join-Path $TestDrive "$Name-layout-hotkeys.json"
		if ($LayoutHotkeys) {
			$LayoutHotkeys | ConvertTo-Json -Depth 10 | Set-Content $hotkeysPath
		}

		return @{ Layouts = $layoutsPath; Hotkeys = $hotkeysPath }
	}

	# A consistent baseline: two grid layouts + one canvas layout, fully mapped and hotkeyed
	$script:BaselineLayouts = @{
		'custom-layouts' = @(
			@{
				name = "Halves"
				uuid = "{AAAAAAAA-0000-0000-0000-000000000001}"
				type = "grid"
				info = @{
					rows                 = 1
					columns              = 2
					'rows-percentage'    = @(10000)
					'columns-percentage' = @(5000, 5000)
					'cell-child-map'     = @(, @(0, 1))
					'show-spacing'       = $true
					spacing              = 16
				}
			}
			@{
				name = "TallLeft"
				uuid = "{AAAAAAAA-0000-0000-0000-000000000002}"
				type = "grid"
				info = @{
					rows                 = 2
					columns              = 2
					'rows-percentage'    = @(5000, 5000)
					'columns-percentage' = @(5000, 5000)
					'cell-child-map'     = @(@(0, 1), @(0, 2))
					'show-spacing'       = $false
					spacing              = 0
				}
			}
			@{
				name = "FreeForm"
				uuid = "{AAAAAAAA-0000-0000-0000-000000000003}"
				type = "canvas"
				info = @{
					'ref-width'  = 1000
					'ref-height' = 1000
					zones        = @(
						@{ X = 0; Y = 0; width = 600; height = 1000 }
						@{ X = 600; Y = 0; width = 400; height = 1000 }
					)
				}
			}
		)
	}

	$script:BaselineHotkeys = @{
		'layout-hotkeys' = @(
			@{ key = 0; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000001}" }
			@{ key = 1; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000002}" }
			@{ key = 2; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000003}" }
		)
	}

	$script:BaselineConfiguration = @{
		ZoneNameMappings = @{
			"Halves"   = @{ "Left" = 0; "Right" = 1 }
			"TallLeft" = @{ "Left" = 0; "Top-Right" = 1; "Bottom-Right" = 2 }
			"FreeForm" = @{ "Large" = 0; "Small" = 1 }
		}
		LayoutNumbers    = @{
			"Halves"   = 0
			"TallLeft" = 1
			"FreeForm" = 2
		}
	}

	function script:Copy-Hashtable {
		param ([hashtable]$Source)
		$copy = @{}
		foreach ($key in $Source.Keys) {
			$copy[$key] = if ($Source[$key] -is [hashtable]) { Copy-Hashtable -Source $Source[$key] } else { $Source[$key] }
		}
		return $copy
	}
}

Describe "Test-FancyZonesConfiguration" {
	BeforeAll {
		$script:SavedConfiguration = $global:Configuration
	}

	AfterAll {
		$global:Configuration = $script:SavedConfiguration
	}

	BeforeEach {
		$global:Configuration = @{
			ZoneNameMappings = Copy-Hashtable $script:BaselineConfiguration.ZoneNameMappings
			LayoutNumbers    = Copy-Hashtable $script:BaselineConfiguration.LayoutNumbers
		}
	}

	Context "Consistent configuration" {
		It "Should report a fully consistent configuration as valid" {
			$fixture = New-TestFancyZonesFixture -Name "valid" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeTrue
			$result.Errors.Count | Should -Be 0
			$result.Warnings.Count | Should -Be 0
		}
	}

	Context "ZoneNameMappings validation" {
		It "Should reject a zone name mapped to an out-of-range index, naming layout, zone, index, and count" {
			$fixture = New-TestFancyZonesFixture -Name "outofrange" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.ZoneNameMappings["Halves"]["Bottom-Right"] = 5

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			$mappingError = @($result.Errors | Where-Object { $_.Message -match "Bottom-Right" })
			$mappingError.Count | Should -Be 1
			$mappingError[0].Layout | Should -Be "Halves"
			$mappingError[0].Message | Should -Match "index 5"
			$mappingError[0].Message | Should -Match "2 zones"
		}

		It "Should reject a mappings entry whose layout does not exist" {
			$fixture = New-TestFancyZonesFixture -Name "missinglayout" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.ZoneNameMappings["Ghost"] = @{ "Full" = 0 }

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "'Ghost' has no layout" }).Count | Should -Be 1
		}

		It "Should validate canvas mappings against the zones array length" {
			$fixture = New-TestFancyZonesFixture -Name "canvasrange" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.ZoneNameMappings["FreeForm"]["Third"] = 2

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Layout -eq "FreeForm" -and $_.Message -match "index 2" }).Count | Should -Be 1
		}

		It "Should only warn for a layout without a mappings entry" {
			$fixture = New-TestFancyZonesFixture -Name "unmapped" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.ZoneNameMappings.Remove("FreeForm")

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeTrue
			@($result.Warnings | Where-Object { $_.Message -match "'FreeForm' has no ZoneNameMappings entry" }).Count | Should -Be 1
		}

		It "Should only warn for a zone index that has no name" {
			$fixture = New-TestFancyZonesFixture -Name "unnamed" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.ZoneNameMappings["TallLeft"].Remove("Bottom-Right")

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeTrue
			@($result.Warnings | Where-Object { $_.Layout -eq "TallLeft" -and $_.Message -match "zone index 2 has no name" }).Count | Should -Be 1
		}
	}

	Context "Grid layout internal consistency" {
		It "Should reject percentages that do not sum to exactly 10000" {
			$layouts = @{
				'custom-layouts' = @(
					@{
						name = "Halves"
						uuid = "{AAAAAAAA-0000-0000-0000-000000000001}"
						type = "grid"
						info = @{
							rows                 = 1
							columns              = 2
							'rows-percentage'    = @(10000)
							'columns-percentage' = @(5000, 4999)
							'cell-child-map'     = @(, @(0, 1))
							'show-spacing'       = $false
							spacing              = 0
						}
					}
				)
			}
			$global:Configuration = @{ ZoneNameMappings = @{ "Halves" = @{ "Left" = 0; "Right" = 1 } }; LayoutNumbers = @{ "Halves" = 0 } }
			$hotkeys = @{ 'layout-hotkeys' = @(@{ key = 0; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000001}" }) }
			$fixture = New-TestFancyZonesFixture -Name "badsum" -CustomLayouts $layouts -LayoutHotkeys $hotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "sums to 9999" }).Count | Should -Be 1
		}

		It "Should reject a cell-child-map whose zone indices are not contiguous" {
			$layouts = @{
				'custom-layouts' = @(
					@{
						name = "Gappy"
						uuid = "{AAAAAAAA-0000-0000-0000-000000000009}"
						type = "grid"
						info = @{
							rows                 = 1
							columns              = 2
							'rows-percentage'    = @(10000)
							'columns-percentage' = @(5000, 5000)
							'cell-child-map'     = @(, @(0, 2))
							'show-spacing'       = $false
							spacing              = 0
						}
					}
				)
			}
			$global:Configuration = @{ ZoneNameMappings = @{}; LayoutNumbers = @{} }
			$hotkeys = @{ 'layout-hotkeys' = @() }
			$fixture = New-TestFancyZonesFixture -Name "gappy" -CustomLayouts $layouts -LayoutHotkeys $hotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "not a contiguous" }).Count | Should -Be 1
		}
	}

	Context "LayoutNumbers validation" {
		It "Should reject duplicate hotkey numbers" {
			$fixture = New-TestFancyZonesFixture -Name "dupnumbers" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.LayoutNumbers["FreeForm"] = 0

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "both assigned hotkey 0" }).Count | Should -Be 1
		}

		It "Should reject hotkey numbers outside 0-9" {
			$fixture = New-TestFancyZonesFixture -Name "badnumber" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.LayoutNumbers["FreeForm"] = 12

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "only supports hotkeys 0-9" }).Count | Should -Be 1
		}

		It "Should reject a LayoutNumbers entry whose layout does not exist" {
			$fixture = New-TestFancyZonesFixture -Name "numbermissing" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $script:BaselineHotkeys
			$global:Configuration.LayoutNumbers["Ghost"] = 5

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "LayoutNumbers entry 'Ghost'" }).Count | Should -Be 1
		}
	}

	Context "layout-hotkeys.json synchronization" {
		It "Should reject a hotkey pointing at the wrong layout's uuid" {
			$hotkeys = @{
				'layout-hotkeys' = @(
					# Keys 0 and 1 swapped relative to LayoutNumbers
					@{ key = 0; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000002}" }
					@{ key = 1; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000001}" }
					@{ key = 2; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000003}" }
				)
			}
			$fixture = New-TestFancyZonesFixture -Name "swappedhotkeys" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $hotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "WRONG layout" }).Count | Should -BeGreaterThan 0
		}

		It "Should reject a hotkey uuid that exists nowhere in custom-layouts.json" {
			$hotkeys = @{
				'layout-hotkeys' = @(
					@{ key = 0; 'layout-id' = "{DEADBEEF-0000-0000-0000-000000000000}" }
					@{ key = 1; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000002}" }
					@{ key = 2; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000003}" }
				)
			}
			$fixture = New-TestFancyZonesFixture -Name "orphanuuid" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $hotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "does not exist in custom-layouts.json" }).Count | Should -Be 1
		}

		It "Should reject a LayoutNumbers assignment with no hotkey entry at all" {
			$hotkeys = @{
				'layout-hotkeys' = @(
					@{ key = 0; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000001}" }
					@{ key = 1; 'layout-id' = "{AAAAAAAA-0000-0000-0000-000000000002}" }
					# key 2 missing while LayoutNumbers assigns FreeForm = 2
				)
			}
			$fixture = New-TestFancyZonesFixture -Name "missinghotkey" -CustomLayouts $script:BaselineLayouts -LayoutHotkeys $hotkeys

			$result = Test-FancyZonesConfiguration -CustomLayoutsPath $fixture.Layouts -LayoutHotkeysPath $fixture.Hotkeys -Silent

			$result.Valid | Should -BeFalse
			@($result.Errors | Where-Object { $_.Message -match "no entry for hotkey 2" }).Count | Should -Be 1
		}
	}

	Context "Missing files" {
		It "Should report a missing custom-layouts.json as a global error" {
			$result = Test-FancyZonesConfiguration -CustomLayoutsPath (Join-Path $TestDrive "does-not-exist.json") -LayoutHotkeysPath (Join-Path $TestDrive "also-missing.json") -Silent

			$result.Valid | Should -BeFalse
			$result.Errors[0].Layout | Should -BeNullOrEmpty
			$result.Errors[0].Message | Should -Match "Custom layouts file not found"
		}
	}
}
