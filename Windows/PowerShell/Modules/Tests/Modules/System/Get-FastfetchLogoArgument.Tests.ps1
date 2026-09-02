#Requires -Modules Pester

BeforeAll {
	$SystemFunctionsPath = Join-Path (Get-RepositoryPath).Modules "System\Functions"

	# The collaborators are dot-sourced rather than stubbed so Mock has real commands to attach to
	# and so a rename on either side fails here rather than silently at shell startup.
	. "$SystemFunctionsPath\Get-TerminalCellSize.ps1"
	. "$SystemFunctionsPath\New-SixelImage.ps1"
	. "$SystemFunctionsPath\Get-FastfetchLogoArgument.ps1"
}

Describe "Get-FastfetchLogoArgument" {
	BeforeEach {
		Mock Write-LogDebug { }

		# Both branches are selected by environment, so every test states the terminal it means.
		$script:SavedWtSession = $env:WT_SESSION
		$script:SavedTermProgram = $env:TERM_PROGRAM
		$env:WT_SESSION = $null
		$env:TERM_PROGRAM = $null

		# The two parameter defaults read configuration. Blank them so the suite behaves the same on
		# a provisioned machine (where both resolve to real paths) as it does on a clean CI runner.
		$script:SavedConfiguration = $global:Configuration
		$script:SavedMachinePaths = $global:MachineSpecificPaths
		$script:SavedMachineType = $global:MachineType
		$global:Configuration = @{ Universal = @{ FastFetchImageLogo = $null } }
		$global:MachineSpecificPaths = @{ SymbolicLinks = @{} }
		$global:MachineType = "Test"

		$script:ImagePath = Join-Path $TestDrive "ImageLogo.png"
		Set-Content -LiteralPath $script:ImagePath -Value "image bytes" -NoNewline
	}

	AfterEach {
		$env:WT_SESSION = $script:SavedWtSession
		$env:TERM_PROGRAM = $script:SavedTermProgram
		$global:Configuration = $script:SavedConfiguration
		$global:MachineSpecificPaths = $script:SavedMachinePaths
		$global:MachineType = $script:SavedMachineType
	}

	Context "when an image logo is not possible" {
		It "returns nothing when no image is configured, which is the base configuration's state" {
			$env:TERM_PROGRAM = "WezTerm"

			Get-FastfetchLogoArgument -OutputRedirected $false | Should -BeNullOrEmpty
		}

		It "returns nothing when the configured image is missing" {
			$env:TERM_PROGRAM = "WezTerm"
			$global:Configuration.Universal.FastFetchImageLogo = Join-Path $TestDrive "Absent.png"

			Get-FastfetchLogoArgument -OutputRedirected $false | Should -BeNullOrEmpty
		}

		It "returns nothing when output is redirected, so the captured panel stays measurable" {
			# Invoke-ClearAndFastfetch sizes the panel by capturing fastfetch's output, one line per
			# visual row. An image payload is a single enormous line - a 50KB sixel reads as a
			# 50,000-column panel - which would make the auto-fit shrink the font on every call.
			$env:WT_SESSION = "test-session"

			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $true |
			Should -BeNullOrEmpty
		}

		It "returns nothing in a terminal with no image protocol" {
			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false |
			Should -BeNullOrEmpty
		}

		It "returns nothing when Windows Terminal does not report its cell size" {
			$env:WT_SESSION = "test-session"
			Mock Get-TerminalCellSize { $null }

			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false |
			Should -BeNullOrEmpty
		}

		It "returns nothing when the sixel cannot be encoded" {
			$env:WT_SESSION = "test-session"
			Mock Get-TerminalCellSize { [pscustomobject]@{ Width = 10; Height = 20 } }
			Mock New-SixelImage { $null }

			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false |
			Should -BeNullOrEmpty
		}
	}

	Context "reading the opt-in from configuration" {
		It "uses Universal.FastFetchImageLogo when no image is passed" {
			$env:TERM_PROGRAM = "WezTerm"
			$global:Configuration.Universal.FastFetchImageLogo = $script:ImagePath

			$result = Get-FastfetchLogoArgument -OutputRedirected $false

			$result -join " " |
			Should -Be "--logo-type iterm --logo $script:ImagePath --logo-width 36 --logo-padding-right 4"
		}

		It "measures the cell block from the deployed fastfetch text logo by default" {
			# PathTemplates.SymbolicLinks.FastFetch.Logo is the text logo the fastfetch config
			# renders, so measuring it is what keeps the image and the text logo interchangeable.
			$env:WT_SESSION = "test-session"
			Mock Get-TerminalCellSize { [pscustomobject]@{ Width = 10; Height = 20 } }
			Mock New-SixelImage { Join-Path $TestDrive "configured.six" }

			$textLogo = Join-Path $TestDrive "FastFetchLogo_Test.txt"
			Set-Content -LiteralPath $textLogo -Value @('$1  ####', '$2  ##')
			$global:MachineSpecificPaths.SymbolicLinks = @{ FastFetch = @{ Logo = @{ Path = $textLogo } } }
			$global:Configuration.Universal.FastFetchImageLogo = $script:ImagePath

			Get-FastfetchLogoArgument -OutputRedirected $false | Out-Null

			# 2 lines tall, 6 columns wide: '$1  ####' is 8 characters less the two-character
			# colour placeholder, which is fastfetch markup rather than a glyph.
			Should -Invoke New-SixelImage -Times 1 -Exactly -Scope It -ParameterFilter {
				$MaxPixelWidth -eq (6 * 10) -and $MaxPixelHeight -eq (2 * 20)
			}
		}

		It "resolves this machine's entry when the key is a per-machine hashtable" {
			$env:TERM_PROGRAM = "WezTerm"
			$other = Join-Path $TestDrive "OtherMachine.png"
			Set-Content -LiteralPath $other -Value "other" -NoNewline
			$global:Configuration.Universal.FastFetchImageLogo = @{
				Test = $script:ImagePath
				Work = $other
			}

			$result = Get-FastfetchLogoArgument -OutputRedirected $false

			$result -join " " | Should -Match ([regex]::Escape($script:ImagePath))
			$result -join " " | Should -Not -Match ([regex]::Escape($other))
		}

		It "returns nothing when the per-machine hashtable has no entry for this machine" {
			# Adding one machine must never switch the feature on for the others: a missing entry is
			# the same no-op as leaving the key unset.
			$env:TERM_PROGRAM = "WezTerm"
			$global:Configuration.Universal.FastFetchImageLogo = @{ Work = $script:ImagePath }

			Get-FastfetchLogoArgument -OutputRedirected $false | Should -BeNullOrEmpty
		}

		It "returns nothing when a per-machine hashtable is set but the machine type is unknown" {
			$env:TERM_PROGRAM = "WezTerm"
			$global:MachineType = $null
			$global:Configuration.Universal.FastFetchImageLogo = @{ Test = $script:ImagePath }

			Get-FastfetchLogoArgument -OutputRedirected $false | Should -BeNullOrEmpty
		}

		It "prefers an explicitly passed image over the configured one" {
			$env:TERM_PROGRAM = "WezTerm"
			$global:Configuration.Universal.FastFetchImageLogo = Join-Path $TestDrive "Configured.png"
			Set-Content -LiteralPath $global:Configuration.Universal.FastFetchImageLogo -Value "x" -NoNewline

			$result = Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false

			$result -join " " | Should -Match ([regex]::Escape($script:ImagePath))
		}
	}

	Context "in WezTerm" {
		It "passes the image through with the iTerm inline-image protocol" {
			$env:TERM_PROGRAM = "WezTerm"

			$result = Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false

			$result -join " " |
			Should -Be "--logo-type iterm --logo $script:ImagePath --logo-width 36 --logo-padding-right 4"
		}

		It "never measures or encodes anything, because WezTerm scales the image itself" {
			$env:TERM_PROGRAM = "WezTerm"
			Mock Get-TerminalCellSize { [pscustomobject]@{ Width = 10; Height = 20 } }
			Mock New-SixelImage { "should-not-be-called.six" }

			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false | Out-Null

			Should -Invoke Get-TerminalCellSize -Times 0 -Exactly -Scope It
			Should -Invoke New-SixelImage -Times 0 -Exactly -Scope It
		}
	}

	Context "in Windows Terminal" {
		BeforeEach {
			$env:WT_SESSION = "test-session"
			Mock Get-TerminalCellSize { [pscustomobject]@{ Width = 10; Height = 20 } }
			Mock New-SixelImage { Join-Path $TestDrive "Logo_360x320.six" }
		}

		It "hands a pre-encoded sixel through with --logo-type raw" {
			# raw is what makes this work at all: fastfetch prints the payload verbatim instead of
			# trying to measure a character cell, which it cannot do on Windows.
			$expectedSixel = Join-Path $TestDrive "Logo_360x320.six"

			$result = Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false

			$result -join " " |
			Should -Be "--logo-type raw --logo $expectedSixel --logo-width 36 --logo-height 16 --logo-padding-right 4"
		}

		It "converts the cell block into the pixel box the image is encoded to fit" {
			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false | Out-Null

			Should -Invoke New-SixelImage -Times 1 -Exactly -Scope It -ParameterFilter {
				$MaxPixelWidth -eq (36 * 10) -and $MaxPixelHeight -eq (16 * 20)
			}
		}

		It "re-reads the cell size on every call, because the font size can change between them" {
			# Invoke-ClearAndFastfetch's auto-fit presses Ctrl+0 / Ctrl+Minus between measuring the
			# panel and displaying it, so a cell size cached from an earlier call would encode the
			# image against a font the terminal has already stopped using.
			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false | Out-Null
			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false | Out-Null

			Should -Invoke Get-TerminalCellSize -Times 2 -Exactly -Scope It
		}

		It "honours an explicit cell block and padding" {
			$result = Get-FastfetchLogoArgument -ImagePath $script:ImagePath -OutputRedirected $false `
				-CellWidth 20 -CellHeight 10 -PaddingRight 2

			($result -join " ") | Should -Match "--logo-width 20 --logo-height 10 --logo-padding-right 2$"
			Should -Invoke New-SixelImage -Times 1 -Exactly -Scope It -ParameterFilter {
				$MaxPixelWidth -eq 200 -and $MaxPixelHeight -eq 200
			}
		}
	}

	Context "measuring the reference text logo" {
		BeforeEach {
			$env:WT_SESSION = "test-session"
			Mock Get-TerminalCellSize { [pscustomobject]@{ Width = 10; Height = 20 } }
			Mock New-SixelImage { Join-Path $TestDrive "measured.six" }
		}

		It "takes the cell block from the text logo the fastfetch config would have rendered" {
			# Matching the text logo's footprint is what keeps the two interchangeable: the panel has
			# the same geometry either way, so the auto-fit measurement (which runs on the text
			# logo) stays valid for the image panel it is deciding about.
			$textLogo = Join-Path $TestDrive "FastFetchLogo_Test.txt"
			Set-Content -LiteralPath $textLogo -Value @(
				'$1  ####',
				'$2  ##',
				'$1  ########'
			)

			Get-FastfetchLogoArgument -ImagePath $script:ImagePath -ReferenceLogoPath $textLogo -OutputRedirected $false |
			Out-Null

			# 3 lines tall, and 10 columns wide once the two-character $N color placeholders are
			# discounted - they are fastfetch markup, not glyphs.
			Should -Invoke New-SixelImage -Times 1 -Exactly -Scope It -ParameterFilter {
				$MaxPixelWidth -eq (10 * 10) -and $MaxPixelHeight -eq (3 * 20)
			}
		}

		It "falls back to the explicit cell block when the reference logo cannot be read" {
			Get-FastfetchLogoArgument -ImagePath $script:ImagePath `
				-ReferenceLogoPath (Join-Path $TestDrive "NoSuchLogo.txt") `
				-CellWidth 12 -CellHeight 6 -OutputRedirected $false | Out-Null

			Should -Invoke New-SixelImage -Times 1 -Exactly -Scope It -ParameterFilter {
				$MaxPixelWidth -eq 120 -and $MaxPixelHeight -eq 120
			}
		}
	}
}
