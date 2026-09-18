#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-ConfigSetting.ps1"
}

Describe "Get-ConfigSetting" {
	BeforeEach {
		$script:Source = @{
			Universal = @{
				DefaultBrowser          = 'Firefox'
				VisibleWindowExclusions = @('Rainmeter', 'WindowsTerminal')
				OneItem                 = @('only')
				Nothing                 = @()
				Off                     = $false
				Zero                    = 0
				Blank                   = ''
				Unset                   = $null
				Browsers                = @{}
				UrlMap                  = @{ 'claude.ai' = @('claude') }
			}
			WorkspaceActions = @{ Server = @{ Layout = 'One' } }
		}
	}

	Context "Resolving a path" {
		It "returns a leaf value by dotted path" {
			Get-ConfigSetting -Path 'Universal.DefaultBrowser' -Configuration $script:Source | Should -Be 'Firefox'
		}

		It "returns a whole section as the hashtable it is" {
			$section = Get-ConfigSetting -Path 'WorkspaceActions' -Configuration $script:Source

			$section | Should -BeOfType [hashtable]
			$section.Server.Layout | Should -Be 'One'
		}

		It "walks PSCustomObject sources the same way as hashtables" {
			$paths = [pscustomobject]@{ Projects = [pscustomobject]@{ Self = [pscustomobject]@{ Root = 'C:\Dev\WinuX' } } }

			Get-ConfigSetting -Path 'Projects.Self.Root' -Configuration $paths | Should -Be 'C:\Dev\WinuX'
			Get-ConfigSetting -Path 'Projects.Self.Missing' -Configuration $paths -Default 'd' | Should -Be 'd'
		}

		It "reaches a key containing a dot when the segments are passed separately" {
			$hosts = Get-ConfigSetting -Path 'Universal', 'UrlMap', 'claude.ai' -Configuration $script:Source

			@($hosts)[0] | Should -Be 'claude'
		}

		It "throws on an empty path segment rather than silently reading the wrong key" {
			{ Get-ConfigSetting -Path 'Universal..DefaultBrowser' -Configuration $script:Source } | Should -Throw '*empty segment*'
		}
	}

	Context "Missing versus empty" {
		It "returns the default when a segment is absent, however deep" {
			Get-ConfigSetting -Path 'Universal.NoSuchKey' -Configuration $script:Source -Default 'd' | Should -Be 'd'
			Get-ConfigSetting -Path 'NoSection.Deep.Deeper' -Configuration $script:Source -Default 'd' | Should -Be 'd'
		}

		It "returns the default when the leaf is present but null" {
			Get-ConfigSetting -Path 'Universal.Unset' -Configuration $script:Source -Default 'd' | Should -Be 'd'
		}

		It "returns null when nothing resolves and no default is given" {
			Get-ConfigSetting -Path 'Universal.NoSuchKey' -Configuration $script:Source | Should -BeNullOrEmpty
		}

		It "returns the default when the whole source is null" {
			Get-ConfigSetting -Path 'Anything' -Configuration $null -Default 7 | Should -Be 7
		}

		It "returns false, zero and an empty string verbatim - they are configured values" {
			Get-ConfigSetting -Path 'Universal.Off' -Configuration $script:Source -Default $true | Should -BeFalse
			Get-ConfigSetting -Path 'Universal.Zero' -Configuration $script:Source -Default 9 | Should -Be 0
			Get-ConfigSetting -Path 'Universal.Blank' -Configuration $script:Source -Default 'd' | Should -Be ''
		}

		It "treats an empty array as a configured value: wrapped at the call site it has zero elements, and the default is not used" {
			$value = @(Get-ConfigSetting -Path 'Universal.Nothing' -Configuration $script:Source -Default @('fallback'))

			$value.Count | Should -Be 0
		}

		It "returns an empty hashtable verbatim" {
			$value = Get-ConfigSetting -Path 'Universal.Browsers' -Configuration $script:Source -Default $null

			$value | Should -BeOfType [hashtable]
			$value.Count | Should -Be 0
		}
	}

	Context "Collections are enumerated like any command output" {
		It "yields one element per configured item when wrapped at the call site, never a nested array" {
			$value = @(Get-ConfigSetting -Path 'Universal.VisibleWindowExclusions' -Configuration $script:Source)

			$value.Count | Should -Be 2
			$value -contains 'Rainmeter' | Should -BeTrue
			$value[0] | Should -BeOfType [string]
		}

		It "yields a one-element array as one element" {
			$value = @(Get-ConfigSetting -Path 'Universal.OneItem' -Configuration $script:Source)

			$value.Count | Should -Be 1
			$value[0] | Should -Be 'only'
		}

		It "yields an array default with zero elements when wrapped" {
			$value = @(Get-ConfigSetting -Path 'Nope' -Configuration $script:Source -Default @())

			$value.Count | Should -Be 0
		}

		It "streams the elements down a pipeline" {
			(Get-ConfigSetting -Path 'Universal.VisibleWindowExclusions' -Configuration $script:Source | Measure-Object).Count | Should -Be 2
		}
	}

	Context "Source selection" {
		It "reads the global configuration when no source is passed" {
			$previous = $global:Configuration
			try {
				$global:Configuration = @{ Probe = @{ Value = 'from-global' } }
				Get-ConfigSetting -Path 'Probe.Value' | Should -Be 'from-global'
			}
			finally {
				$global:Configuration = $previous
			}
		}

		It "never touches the global configuration when a source is passed" {
			$previous = $global:Configuration
			try {
				$global:Configuration = @{ Probe = @{ Value = 'from-global' } }
				Get-ConfigSetting -Path 'Probe.Value' -Configuration @{ Probe = @{ Value = 'from-param' } } | Should -Be 'from-param'
			}
			finally {
				$global:Configuration = $previous
			}
		}
	}
}
