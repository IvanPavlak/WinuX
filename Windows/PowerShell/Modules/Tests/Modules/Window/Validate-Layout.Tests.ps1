#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Validate-Layout" {
	Context "Valid Configurations" {
		It "Should pass validation for a well-formed single-monitor layout" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							1 = "One"
							2 = "Two"
						}
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left"; Monitor = "Primary" }
					@{ ProcessName = "App2"; DesktopNumber = 2; Zone = "Right"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config -LayoutName "Test"

			$result.IsValid | Should -Be $true
			$result.Errors.Count | Should -Be 0
		}

		It "Should pass validation for multi-monitor layout" {
			$config = @{
				Monitors = @{
					Primary   = @{
						VirtualDesktopLayouts = @{
							1 = "One"
						}
					}
					Secondary = @{
						VirtualDesktopLayouts = @{
							1 = "Two"
						}
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left"; Monitor = "Primary" }
					@{ ProcessName = "App2"; DesktopNumber = 1; Zone = "Right"; Monitor = "Secondary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
		}

		It "Should pass when Layout uses explicit coordinates instead of Zone" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @(
					@{
						ProcessName   = "App1"
						DesktopNumber = 1
						Monitor       = "Primary"
						Layout        = @{ X = 100; Y = 100; Width = 800; Height = 600 }
					}
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
		}
	}

	Context "Invalid Desktop Indices" {
		It "Should fail when desktop indices are not contiguous (missing index)" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							1 = "One"
							3 = "Two"  # Missing index 2
						}
					}
				}
				Layout   = @()
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Should -Contain "Monitor 'Primary': Missing virtual desktop indices: 2 (expected 1 to 3)"
		}

		It "Should fail when using 0-based indexing instead of 1-based" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							0 = "One"  # Should start at 1
							1 = "Two"
						}
					}
				}
				Layout   = @()
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "0-based indexing" } | Should -Not -BeNullOrEmpty
		}

		It "Should fail when Layout references out-of-range desktop numbers" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							1 = "One"
						}
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 5; Zone = "Left"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Should -Contain "Layout array uses invalid desktop numbers: 5 (valid range: 1 to 1)"
		}

		It "Should fail when Layout references desktop number below 1" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							1 = "One"
						}
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 0; Zone = "Left"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "invalid desktop numbers.*0" } | Should -Not -BeNullOrEmpty
		}
	}

	Context "Invalid Zone References" {
		It "Should fail when zone item references undefined monitor" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left"; Monitor = "NonExistent" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "NonExistent.*not defined" } | Should -Not -BeNullOrEmpty
		}

		It "Should fail when zone item is missing Monitor" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "no Monitor specified" } | Should -Not -BeNullOrEmpty
		}

		It "Should fail when zone item is missing DesktopNumber" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; Zone = "Left"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "no DesktopNumber specified" } | Should -Not -BeNullOrEmpty
		}

		It "Should fail when monitor has no VirtualDesktopLayouts defined" {
			$config = @{
				Monitors = @{
					Primary   = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
					Secondary = @{}  # No VirtualDesktopLayouts
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left"; Monitor = "Secondary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "no VirtualDesktopLayouts defined" } | Should -Not -BeNullOrEmpty
		}

		It "Should fail when desktop/monitor combination is not defined" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 2; Zone = "Left"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $false
			$result.Errors | Where-Object { $_ -match "Desktop=2.*no layout is defined" } | Should -Not -BeNullOrEmpty
		}
	}

	Context "Warnings (Non-Fatal)" {
		It "Should warn when desktops are defined but not used" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{
							1 = "One"
							2 = "Two"
						}
					}
				}
				Layout   = @(
					@{ ProcessName = "App1"; DesktopNumber = 1; Zone = "Left"; Monitor = "Primary" }
				)
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
			$result.Warnings | Where-Object { $_ -match "not used in Layout array" } | Should -Not -BeNullOrEmpty
		}

		It "Should warn when monitors have different desktop counts" {
			$config = @{
				Monitors = @{
					Primary   = @{
						VirtualDesktopLayouts = @{ 1 = "One"; 2 = "Two" }
					}
					Secondary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @()
			}

			$result = Validate-Layout -Config $config

			$result.Warnings | Where-Object { $_ -match "different virtual desktop counts" } | Should -Not -BeNullOrEmpty
		}
	}

	Context "Edge Cases" {
		It "Should handle empty config gracefully" {
			$config = @{}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
		}

		It "Should handle config with no virtual desktop layouts" {
			$config = @{
				Monitors = @{
					Primary = @{}
				}
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
		}

		It "Should handle config with empty Layout array" {
			$config = @{
				Monitors = @{
					Primary = @{
						VirtualDesktopLayouts = @{ 1 = "One" }
					}
				}
				Layout   = @()
			}

			$result = Validate-Layout -Config $config

			$result.IsValid | Should -Be $true
		}
	}
}
