#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	$script:OriginalConfiguration = $global:Configuration
	$global:Configuration = @{
		ZoneNameMappings = @{
			"One"  = @{
				"Left"  = 0
				"Right" = 1
			}
			"Four" = @{
				"Top-Left"     = 0
				"Bottom-Left"  = 1
				"Top-Right"    = 2
				"Bottom-Right" = 3
			}
		}
	}
}

Describe "Update-LayoutSectionHeaders" {
	Context "Section Header Generation" {
		It "Should generate section headers for desktop/monitor combinations" {
			$content = @"
@{
    Monitors = @{
        Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
    }
    Layout = @(
        @{
            ProcessName = "App1"
            DesktopNumber = 1
            Monitor = "Primary"
            Zone = "Left"
        }
    )
}
"@
			$config = @{
				Monitors = @{
					Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Left" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$result | Should -Match "VIRTUAL DESKTOP 1"
			$result | Should -Match "Monitor: Primary"
			$result | Should -Match "Layout: One"
		}

		It "Should sort entries by DesktopNumber then Monitor priority" {
			$content = @'
@{
    Monitors = @{
        Primary = @{ VirtualDesktopLayouts = @{ 1 = "One"; 2 = "Two" } }
        Secondary = @{ VirtualDesktopLayouts = @{ 1 = "Three"; 2 = "Four" } }
    }
    Layout = @(
        @{
            ProcessName = "App2"
            DesktopNumber = 1
            Monitor = "Secondary"
            Zone = "Left"
        }
        @{
            ProcessName = "App1"
            DesktopNumber = 1
            Monitor = "Primary"
            Zone = "Left"
        }
        @{
            ProcessName = "App3"
            DesktopNumber = 2
            Monitor = "Secondary"
            Zone = "Right"
        }
        @{
            ProcessName = "App4"
            DesktopNumber = 2
            Monitor = "Primary"
            Zone = "Right"
        }
    )
}
'@
			$config = @{
				Monitors = @{
					Primary   = @{ VirtualDesktopLayouts = @{ 1 = "One"; 2 = "Two" } }
					Secondary = @{ VirtualDesktopLayouts = @{ 1 = "Three"; 2 = "Four" } }
				}
				Layout   = @(
					@{ ProcessName = "App2"; DesktopNumber = 1; Monitor = "Secondary"; Zone = "Left" }
					@{ ProcessName = "App1"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Left" }
					@{ ProcessName = "App3"; DesktopNumber = 2; Monitor = "Secondary"; Zone = "Right" }
					@{ ProcessName = "App4"; DesktopNumber = 2; Monitor = "Primary"; Zone = "Right" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			# Find all "Monitor:" occurrences and verify order
			$matches = [regex]::Matches($result, 'Monitor: (\w+)')
			$matches.Count | Should -BeGreaterOrEqual 4

			# First monitor mentioned should be Primary (Desktop 1)
			$matches[0].Groups[1].Value | Should -Be "Primary"
			# Second should be Secondary (Desktop 1)
			$matches[1].Groups[1].Value | Should -Be "Secondary"
			# Third should be Primary (Desktop 2)
			$matches[2].Groups[1].Value | Should -Be "Primary"
			# Fourth should be Secondary (Desktop 2)
			$matches[3].Groups[1].Value | Should -Be "Secondary"
		}

		It "Should sort entries within a section by zone order" {
			$content = @'
@{
	Monitors = @{
		Primary = @{ VirtualDesktopLayouts = @{ 1 = "Four" } }
	}
	Layout = @(
		@{
			ProcessName = "App1"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Bottom-Right"
		}
		@{
			ProcessName = "App2"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Top-Left"
		}
		@{
			ProcessName = "App3"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Top-Right"
		}
		@{
			ProcessName = "App4"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Bottom-Left"
		}
	)
}
'@
			$config = @{
				Monitors = @{
					Primary = @{ VirtualDesktopLayouts = @{ 1 = "Four" } }
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Bottom-Right" }
					@{ ProcessName = "App2"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Top-Left" }
					@{ ProcessName = "App3"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Top-Right" }
					@{ ProcessName = "App4"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Bottom-Left" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$zoneMatches = [regex]::Matches($result, 'Zone\s*=\s*"([^"]+)"')
			$zoneMatches.Count | Should -Be 4
			$zoneMatches[0].Groups[1].Value | Should -Be "Top-Left"
			$zoneMatches[1].Groups[1].Value | Should -Be "Bottom-Left"
			$zoneMatches[2].Groups[1].Value | Should -Be "Top-Right"
			$zoneMatches[3].Groups[1].Value | Should -Be "Bottom-Right"
		}

		It "Should preserve original order for entries in the same zone" {
			$content = @'
@{
	Monitors = @{
		Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
	}
	Layout = @(
		@{
			ProcessName = "FirstLeft"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Left"
		}
		@{
			ProcessName = "SecondLeft"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Left"
		}
		@{
			ProcessName = "RightApp"
			DesktopNumber = 1
			Monitor = "Primary"
			Zone = "Right"
		}
	)
}
'@
			$config = @{
				Monitors = @{
					Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
				}
				Layout   = @(
					@{ ProcessName = "FirstLeft"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Left" }
					@{ ProcessName = "SecondLeft"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Left" }
					@{ ProcessName = "RightApp"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Right" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$processMatches = [regex]::Matches($result, 'ProcessName\s*=\s*"([^"]+)"')
			$processMatches.Count | Should -Be 3
			$processMatches[0].Groups[1].Value | Should -Be "FirstLeft"
			$processMatches[1].Groups[1].Value | Should -Be "SecondLeft"
			$processMatches[2].Groups[1].Value | Should -Be "RightApp"
		}

		It "Should return original content when Layout array cannot be parsed" {
			$content = "Simple text without Layout array structure"
			$config = @{}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$result | Should -Be $content
		}
	}

	Context "Layout Name Resolution" {
		It "Should resolve layout type from Monitors configuration" {
			$content = @'
@{
    Monitors = @{
        Primary = @{ VirtualDesktopLayouts = @{ 1 = "CustomLayoutName" } }
    }
    Layout = @(
        @{
            ProcessName = "App1"
            DesktopNumber = 1
            Monitor = "Primary"
            Zone = "Full"
        }
    )
}
'@
			$config = @{
				Monitors = @{
					Primary = @{ VirtualDesktopLayouts = @{ 1 = "CustomLayoutName" } }
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Full" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$result | Should -Match "Layout: CustomLayoutName"
		}
	}

	Context "Monitor Ordering Beyond Secondary" {
		It "Should order Monitor3, Monitor4 and Monitor5 after Secondary and among themselves" {
			# The three-way Primary=0 / Secondary=1 / everything-else=2 sort this replaced left
			# Monitor3, Monitor4 and Monitor5 tied at 2, so they kept their (arbitrary) input
			# order and generated headers looked randomly ordered past Secondary. Entries are
			# supplied here in deliberately reversed monitor order.
			$monitorSection = @'
        Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
        Secondary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
        Monitor3 = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
        Monitor4 = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
        Monitor5 = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
'@
			$entries = @('Monitor5', 'Monitor4', 'Monitor3', 'Secondary', 'Primary') | ForEach-Object {
				@"
        @{
            ProcessName = "App-$_"
            DesktopNumber = 1
            Monitor = "$_"
            Zone = "Left"
        }
"@
			}
			$content = "@{`n    Monitors = @{`n$monitorSection    }`n    Layout = @(`n$($entries -join "`n")`n    )`n}"

			$config = @{
				Monitors = @{
					Primary   = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
					Secondary = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
					Monitor3  = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
					Monitor4  = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
					Monitor5  = @{ VirtualDesktopLayouts = @{ 1 = "One" } }
				}
				Layout   = @(
					@{ ProcessName = "App-Monitor5"; DesktopNumber = 1; Monitor = "Monitor5"; Zone = "Left" }
					@{ ProcessName = "App-Monitor4"; DesktopNumber = 1; Monitor = "Monitor4"; Zone = "Left" }
					@{ ProcessName = "App-Monitor3"; DesktopNumber = 1; Monitor = "Monitor3"; Zone = "Left" }
					@{ ProcessName = "App-Secondary"; DesktopNumber = 1; Monitor = "Secondary"; Zone = "Left" }
					@{ ProcessName = "App-Primary"; DesktopNumber = 1; Monitor = "Primary"; Zone = "Left" }
				)
			}

			$result = Update-LayoutSectionHeaders -Content $content -Config $config

			$headerOrder = @([regex]::Matches($result, 'Monitor:\s*(?<Name>\S+)') | ForEach-Object { $_.Groups['Name'].Value })

			$headerOrder | Should -Be @('Primary', 'Secondary', 'Monitor3', 'Monitor4', 'Monitor5')
		}
	}

	AfterAll {
		if ($null -ne $script:OriginalConfiguration) {
			$global:Configuration = $script:OriginalConfiguration
		}
		else {
			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}
	}
}
