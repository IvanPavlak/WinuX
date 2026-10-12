#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Merge-LayoutProjectOverrides.ps1"

	# A fresh layout on every call, shaped like Import-PowerShellDataFile returns it: desktop 1
	# splits Primary into Left/Right and fills Secondary, desktop 2 has one Primary entry.
	function New-TestLayout {
		param([hashtable]$ProjectOverrides)
		$layout = @{
			Monitors = @{
				Primary   = @{ VirtualDesktopLayouts = @{ 1 = 'One'; 2 = 'One' } }
				Secondary = @{ VirtualDesktopLayouts = @{ 1 = 'Zero' } }
			}
			Layout   = @(
				@{ ProcessName = 'Code'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' }
				@{ ProcessName = 'Slack'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Right' }
				@{ ProcessName = 'Teams'; DesktopNumber = 1; Monitor = 'Secondary'; Zone = 'Fullscreen' }
				@{ ProcessName = 'Notes'; DesktopNumber = 2; Monitor = 'Primary'; Zone = 'Left' }
			)
		}
		if ($PSBoundParameters.ContainsKey('ProjectOverrides')) { $layout['ProjectOverrides'] = $ProjectOverrides }
		return $layout
	}

	$script:ProjectNames = @('Alpha', 'Beta', 'Gamma')
	$script:ZoneNames = @{
		One   = @{ Left = 0; Right = 1 }
		Zero  = @{ Fullscreen = 0 }
		Three = @{ Left = 0; Center = 1; Right = 2 }
	}

	# The override block every "covered project" case below starts from: desktop 2 switches to
	# Three, and desktop 1 Primary gets two other windows.
	function New-AlphaBlock {
		@{
			Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 2 = 'Three' } } }
			Layout   = @(
				@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' }
				@{ ProcessName = 'Postman'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Right' }
			)
		}
	}

	# An order-independent text rendering of nested hashtables and arrays, so a test can tell
	# whether anything anywhere inside the input changed.
	function Format-DeepValue {
		param($Value)
		if ($null -eq $Value) { return '<null>' }
		if ($Value -is [System.Collections.IDictionary]) {
			$parts = foreach ($key in @($Value.Keys | Sort-Object { "$_" })) { "$key=$(Format-DeepValue $Value[$key])" }
			return '{' + ($parts -join ';') + '}'
		}
		if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
			$parts = foreach ($item in $Value) { Format-DeepValue $item }
			return '[' + ($parts -join ',') + ']'
		}
		return "$Value"
	}

	function Invoke-Merge {
		param([hashtable]$Config, [string[]]$Project)
		Merge-LayoutProjectOverrides -Config $Config -Project $Project -ProjectNames $script:ProjectNames -ZoneNameMappings $script:ZoneNames
	}
}

Describe "Merge-LayoutProjectOverrides" {
	Context "Nothing to apply" {
		It "returns the input object itself when the layout has no ProjectOverrides" {
			$config = New-TestLayout

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
			@($merged.Applied).Count | Should -Be 0
			@($merged.Variants).Count | Should -Be 0
			@($merged.Errors).Count | Should -Be 0
		}

		It "returns the input object itself when no selected project is covered" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Beta'

			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
			@($merged.Applied).Count | Should -Be 0
			@($merged.Variants) | Should -Be @('Alpha')
		}

		It "returns the input object itself when no project is selected" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project @()

			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
			@($merged.Applied).Count | Should -Be 0
		}

		It "still reports the errors of every block when no selected project is covered" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Zone = 'Left' }) }
			}

			$merged = Invoke-Merge -Config $config -Project 'Beta'

			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
			@($merged.Errors).Count | Should -Be 1
		}
	}

	Context "A covered project" {
		It "merges Monitors key by key: only the listed desktops change their zone layout" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			$primary = $merged.Config.Monitors.Primary.VirtualDesktopLayouts
			$primary[1] | Should -Be 'One'
			$primary[2] | Should -Be 'Three'
			# The override's desktop 2 replaced the base's desktop 2 - no second key for it.
			$primary.Count | Should -Be 2
			$merged.Config.Monitors.Secondary.VirtualDesktopLayouts[1] | Should -Be 'Zero'
		}

		It "replaces every base entry of the overridden desktop and monitor, in place, and keeps the rest" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Rider', 'Postman', 'Teams', 'Notes')
			@($merged.Applied) | Should -Be @('Alpha')
			@($merged.Errors).Count | Should -Be 0
		}

		It "adds the entries of a desktop and monitor the base does not use at the end" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{
					Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 3 = 'Zero' } } }
					Layout   = @(@{ ProcessName = 'Rider'; DesktopNumber = 3; Monitor = 'Primary'; Zone = 'Fullscreen' })
				}
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Code', 'Slack', 'Teams', 'Notes', 'Rider')
			$merged.Config.Monitors.Primary.VirtualDesktopLayouts[3] | Should -Be 'Zero'
			$merged.Config.Monitors.Primary.VirtualDesktopLayouts[1] | Should -Be 'One'
		}

		It "returns a copy without the ProjectOverrides block" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			[object]::ReferenceEquals($merged.Config, $config) | Should -BeFalse
			$merged.Config.ContainsKey('ProjectOverrides') | Should -BeFalse
		}

		It "never modifies the input, and the result shares no entry with it" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = (New-AlphaBlock) }
			$before = Format-DeepValue $config

			$merged = Invoke-Merge -Config $config -Project 'Alpha'
			$merged.Config.Layout[0].Zone = 'Changed'
			$merged.Config.Layout[2].Zone = 'Changed'
			$merged.Config.Monitors.Secondary.VirtualDesktopLayouts[1] = 'Changed'

			Format-DeepValue $config | Should -Be $before
			$config.ProjectOverrides.Alpha.Layout[0].Zone | Should -Be 'Left'
			$config.Layout[2].Zone | Should -Be 'Fullscreen'
		}

		It "applies a key covering several projects for any of them, case-insensitively" -TestCases @(
			@{ Selected = 'Beta' }
			@{ Selected = 'gamma' }
		) {
			param($Selected)
			$config = New-TestLayout -ProjectOverrides @{ 'Beta / Gamma' = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project $Selected

			@($merged.Applied) | Should -Be @('Beta / Gamma')
			$merged.Config.Layout[0].ProcessName | Should -Be 'Rider'
		}

		It "applies several selected projects in selection order, the later one winning on the same desktop and monitor" {
			$overrides = @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' }) }
				Beta  = @{ Layout = @(@{ ProcessName = 'Vim'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Right' }) }
			}

			$alphaThenBeta = Invoke-Merge -Config (New-TestLayout -ProjectOverrides $overrides) -Project 'Alpha', 'Beta'
			$betaThenAlpha = Invoke-Merge -Config (New-TestLayout -ProjectOverrides $overrides) -Project 'Beta', 'Alpha'

			@($alphaThenBeta.Applied) | Should -Be @('Alpha', 'Beta')
			@($alphaThenBeta.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Vim', 'Teams', 'Notes')
			@($betaThenAlpha.Applied) | Should -Be @('Beta', 'Alpha')
			@($betaThenAlpha.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Rider', 'Teams', 'Notes')
		}

		It "applies several selected projects that override different desktops side by side" {
			$overrides = @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' }) }
				Beta  = @{ Layout = @(@{ ProcessName = 'Vim'; DesktopNumber = 2; Monitor = 'Primary'; Zone = 'Right' }) }
			}

			$merged = Invoke-Merge -Config (New-TestLayout -ProjectOverrides $overrides) -Project 'Alpha', 'Beta'

			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Rider', 'Teams', 'Vim')
		}

		It "applies a Monitors-only block without touching the Layout entries" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{ Monitors = @{ Secondary = @{ VirtualDesktopLayouts = @{ 1 = 'One' } } } }
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Applied) | Should -Be @('Alpha')
			$merged.Config.Monitors.Secondary.VirtualDesktopLayouts[1] | Should -Be 'One'
			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Code', 'Slack', 'Teams', 'Notes')
		}
	}

	Context "Validation" {
		It "reports an unknown project token and does not apply that block" {
			$config = New-TestLayout -ProjectOverrides @{ 'Alpha/Ghost' = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			$merged.Errors[0] | Should -Match 'Ghost'
			@($merged.Applied).Count | Should -Be 0
			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
		}

		It "applies the valid blocks next to an invalid one" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = (New-AlphaBlock)
				Ghost = @{ Layout = @(@{ ProcessName = 'Vim'; DesktopNumber = 2; Monitor = 'Primary'; Zone = 'Left' }) }
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha', 'Ghost'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied) | Should -Be @('Alpha')
			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Not -Contain 'Vim'
		}

		It "reports every project token as unknown when no project names are known" {
			$config = New-TestLayout -ProjectOverrides @{ Ghost = (New-AlphaBlock) }

			$merged = Merge-LayoutProjectOverrides -Config $config -Project 'Ghost' -ProjectNames @() -ZoneNameMappings $script:ZoneNames

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
		}

		It "reports an override entry without <Missing> and does not apply the block" -TestCases @(
			@{ Missing = 'DesktopNumber'; Entry = @{ ProcessName = 'Rider'; Monitor = 'Primary'; Zone = 'Left' } }
			@{ Missing = 'Monitor'; Entry = @{ ProcessName = 'Rider'; DesktopNumber = 1; Zone = 'Left' } }
		) {
			param($Missing, $Entry)
			$config = New-TestLayout -ProjectOverrides @{ Alpha = @{ Layout = @($Entry) } }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
		}

		It "reports a zone missing from the base zone layout of the desktop and monitor" {
			# Secondary desktop 1 is Zero: it has Fullscreen only.
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Secondary'; Zone = 'Left' }) }
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
		}

		It "checks a zone against the override's own Monitors when it changes the zone layout" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{
					Monitors = @{ Secondary = @{ VirtualDesktopLayouts = @{ 1 = 'One' } } }
					Layout   = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Secondary'; Zone = 'Left' })
				}
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 0
			@($merged.Applied) | Should -Be @('Alpha')
		}

		It "reports a zone the base layout has but the override's zone layout does not" {
			# Primary desktop 1 is One (Left/Right) in the base; the override turns it into Zero.
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{
					Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = 'Zero' } } }
					Layout   = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' })
				}
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
		}

		It "reports an entry on a desktop and monitor that has no zone layout anywhere" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 5; Monitor = 'Primary'; Zone = 'Left' }) }
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
		}

		It "does not check zones when no zone names are configured" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{ Layout = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Nowhere' }) }
			}

			$merged = Merge-LayoutProjectOverrides -Config $config -Project 'Alpha' -ProjectNames $script:ProjectNames -ZoneNameMappings @{}

			@($merged.Errors).Count | Should -Be 0
			@($merged.Applied) | Should -Be @('Alpha')
		}

		It "reports a ProjectOverrides value that is not a hashtable" {
			$config = New-TestLayout
			$config['ProjectOverrides'] = @('Alpha')

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Variants).Count | Should -Be 0
			[object]::ReferenceEquals($merged.Config, $config) | Should -BeTrue
		}

		It "reports an override block that is not a hashtable" {
			$config = New-TestLayout -ProjectOverrides @{ Alpha = 'not a block' }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			@($merged.Applied).Count | Should -Be 0
		}

		It "reports an unknown key in an override block and does not apply it" {
			$block = New-AlphaBlock
			$block['Desktops'] = @{ 1 = 'One' }
			$config = New-TestLayout -ProjectOverrides @{ Alpha = $block }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -Be 1
			$merged.Errors[0] | Should -Match 'Desktops'
			@($merged.Applied).Count | Should -Be 0
		}

		It "reports a Monitors value that is not a hashtable" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha = @{
					Monitors = 'Primary'
					Layout   = @(@{ ProcessName = 'Rider'; DesktopNumber = 1; Monitor = 'Primary'; Zone = 'Left' })
				}
			}

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Errors).Count | Should -BeGreaterOrEqual 1
			@($merged.Applied).Count | Should -Be 0
		}
	}

	Context "Applied and Variants" {
		It "lists every override key as a variant and only the applied ones as applied" {
			$config = New-TestLayout -ProjectOverrides @{
				Alpha        = (New-AlphaBlock)
				'Beta/Gamma' = @{ Layout = @(@{ ProcessName = 'Vim'; DesktopNumber = 2; Monitor = 'Primary'; Zone = 'Left' }) }
			}

			$merged = Invoke-Merge -Config $config -Project 'Gamma'

			@($merged.Variants | Sort-Object) | Should -Be @('Alpha', 'Beta/Gamma')
			@($merged.Applied) | Should -Be @('Beta/Gamma')
			@($merged.Config.Layout | ForEach-Object { $_.ProcessName }) | Should -Be @('Code', 'Slack', 'Teams', 'Vim')
		}

		It "lists a block with errors as a variant too" {
			$config = New-TestLayout -ProjectOverrides @{ Ghost = (New-AlphaBlock) }

			$merged = Invoke-Merge -Config $config -Project 'Alpha'

			@($merged.Variants) | Should -Be @('Ghost')
			@($merged.Errors).Count | Should -Be 1
		}
	}
}
