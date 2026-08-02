#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Import-AppCsv.ps1"

	# Import-AppCsv reports its layering counts through the Logging module. Reading a CSV has no
	# other dependency on logging, so a no-op stub keeps these tests free of that import entirely.
	function Write-LogDebug {
		param(
			[Parameter(ValueFromRemainingArguments = $true)]
			$Arguments
		)
	}

	# Writes a fixture the way the committed app lists are written: CRLF, UTF-8 without a byte-order
	# mark. The COLUMN header is line 1 and any commentary follows it, because Import-Csv takes line
	# 1 as the header unconditionally.
	function Write-AppCsvFixture {
		param(
			[Parameter(Mandatory = $true)]
			[string]$Path,

			# AllowEmptyString is required: a mandatory [string[]] validates NotNullOrEmpty on every
			# ELEMENT, so the blank separator lines the committed files use would fail to bind.
			[Parameter(Mandatory = $true)]
			[AllowEmptyString()]
			[string[]]$Line
		)

		$text = ($Line -join "`r`n") + "`r`n"
		[System.IO.File]::WriteAllText($Path, $text, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
	}

	# Row order is part of the contract - committed rows first, then overlay-only additions - so the
	# assertions compare the whole id sequence rather than only a count.
	function Get-AppIdSequence {
		param(
			[Parameter(Mandatory = $true)]
			[AllowEmptyCollection()]
			[psobject[]]$Row
		)

		return (($Row | ForEach-Object { "$($_.App)" }) -join ',')
	}

	# Three active rows, one commented-out row and one blank separator line. Written by hand rather
	# than copied from the repository on purpose: a synthetic base makes every layering count obvious
	# and keeps the assertions independent of the real app list, which grows whenever an app is added.
	function Get-BaseWinGetLines {
		return @(
			'App,Version,Scope,Interactive,Source,Machine'
			''
			'# Synthetic base list - the header is line 1 and the comments come after it'
			'# exactly like the committed CSVs.'
			'Base.One,Latest,d,n,w,All'
			'Base.Two,1.0.0,d,n,w,PC/Work'
			'#Base.Disabled,Latest,d,n,w,All'
			'Base.Three,Latest,m,n,w,All'
		)
	}

	function Get-BaseScoopLines {
		return @(
			'App,Version,Global,Machine'
			''
			'scoop.one,latest,false,All'
		)
	}

	function Get-BaseChocolateyLines {
		return @(
			'App,Version,Params,Force,Machine'
			''
			'choco.one,latest,,false,All'
		)
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Import-AppCsv" {
	BeforeEach {
		# A synthetic repository under TestDrive, rebuilt for every test so no overlay can leak from
		# one case into the next. The real Data folder is never used: an overlay lives beside its base
		# file, so a fixture written there would sit next to - and could shadow - a committed app list.
		$script:repoRoot = Join-Path $TestDrive "repo"
		$script:dataRoot = Join-Path $script:repoRoot "Windows\PowerShell\Modules\Bootstrap\Data"

		if (Test-Path -Path $script:repoRoot) {
			Remove-Item -Path $script:repoRoot -Recurse -Force
		}

		New-Item -ItemType Directory -Path $script:dataRoot -Force | Out-Null

		$script:winGetBase = Join-Path $script:dataRoot "WinGetApps.csv"
		$script:winGetOverlay = Join-Path $script:dataRoot "WinGetApps.local.csv"
		$script:scoopBase = Join-Path $script:dataRoot "ScoopApps.csv"
		$script:scoopOverlay = Join-Path $script:dataRoot "ScoopApps.local.csv"
		$script:chocoBase = Join-Path $script:dataRoot "ChocolateyApps.csv"

		Write-AppCsvFixture -Path $script:winGetBase -Line (Get-BaseWinGetLines)
		Write-AppCsvFixture -Path $script:scoopBase -Line (Get-BaseScoopLines)
		Write-AppCsvFixture -Path $script:chocoBase -Line (Get-BaseChocolateyLines)

		# The two globals the function reads. MachineSpecificPaths is pointed at the sandbox as well,
		# so even a call that forgot -RepoRoot could not reach the real repository.
		$global:Configuration = @{
			BootstrapConfig   = @{
				DataFiles = @{
					WinGetApps     = 'Windows\PowerShell\Modules\Bootstrap\Data\WinGetApps.csv'
					ScoopApps      = 'Windows\PowerShell\Modules\Bootstrap\Data\ScoopApps.csv'
					ChocolateyApps = 'Windows\PowerShell\Modules\Bootstrap\Data\ChocolateyApps.csv'
				}
			}
			ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		}
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $script:repoRoot } } }
	}

	Context "Reading the committed list" {
		It "returns the committed rows in file order when there is no overlay" {
			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three'
		}

		It "does not treat a missing overlay as an error" {
			# The overlay is opt-in and most machines never write one, so its absence has to be the
			# normal path rather than something every caller has to guard against.
			Test-Path -Path $script:winGetOverlay | Should -BeFalse

			{ Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot } | Should -Not -Throw
		}

		It "drops comment rows and blank App cells" {
			# The callers used to do this individually; centralizing it is half the reason this
			# function exists, so it is asserted here rather than in each installer's tests.
			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			@($rows | Where-Object { "$($_.App)".TrimStart().StartsWith('#') }).Count | Should -Be 0
			@($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.App) }).Count | Should -Be 0
			Get-AppIdSequence -Row $rows | Should -Not -Match 'Base\.Disabled'
		}
	}

	Context "Failure modes" {
		It "throws when the committed list is missing" {
			# The base file is tracked, so its absence is a broken checkout rather than a choice.
			Remove-Item -Path $script:winGetBase -Force

			{ Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*App list not found*'
		}

		It "throws when the DataFiles key is not configured" {
			$global:Configuration.BootstrapConfig.DataFiles.Remove('ChocolateyApps')

			{ Import-AppCsv -DataFileKey ChocolateyApps -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*is not configured*'
		}

		It "rejects a data file key that is not one of the three lists" {
			# ValidateSet is the gate: a typo has to fail at bind time, not resolve to an unconfigured
			# key and be reported as something else.
			{ Import-AppCsv -DataFileKey 'WinGetApp' -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*DataFileKey*'
		}
	}

	Context "Additions" {
		It "appends an overlay row for a new App after the committed rows" {
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Overlay.New,Latest,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			# Base-first order keeps the shipped install sequence intact and puts this machine's own
			# apps at the end.
			$rows.Count | Should -Be 4
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three,Overlay.New'
		}
	}

	Context "Replacements" {
		It "replaces the matching committed row in place and the overlay's values win" {
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Base.Two,2.5.0,m,y,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			# Replacement rather than addition: the count is unchanged and the row keeps its position,
			# which is what lets an overlay pin a version or re-target a machine without reordering
			# the install.
			$rows.Count | Should -Be 3
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three'
			@($rows | Where-Object { $_.App -eq 'Base.Two' }).Count | Should -Be 1

			$rows[1].Version | Should -Be '2.5.0'
			$rows[1].Scope | Should -Be 'm'
			$rows[1].Interactive | Should -Be 'y'
			$rows[1].Machine | Should -Be 'All'
		}

		It "matches an existing App case-insensitively" {
			# Package ids are case-insensitive, so an overlay written with different casing has to
			# replace the shipped row instead of adding a second row for the same app.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'base.TWO,3.0.0,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			@($rows | Where-Object { $_.App -eq 'Base.Two' }).Count | Should -Be 1
			$rows[1].App | Should -BeExactly 'base.TWO'
			$rows[1].Version | Should -Be '3.0.0'
		}
	}

	Context "Removals" {
		It "removes the committed row when the overlay marks the App with a leading dash" {
			# Without this there would be no way to opt out of a shipped app, since a layer that can
			# only add or replace cannot subtract.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'-Base.Two,Latest,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 2
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Three'
		}

		It "never returns a row whose App starts with the removal marker" {
			# The marker is an instruction, not an app id. If one leaked through, the installer would
			# try to install a package literally named -Base.Two.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'-Base.Two,Latest,d,n,w,All'
				'-Ghost.App,Latest,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			@($rows | Where-Object { "$($_.App)".TrimStart().StartsWith('-') }).Count | Should -Be 0
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Three'
		}

		It "ignores a removal for an App the committed list does not contain" {
			# An overlay outlives the base list it was written against, so a removal for an app that
			# upstream has since dropped has to be harmless rather than an error.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'-Ghost.App,Latest,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three'
		}
	}

	Context "Overlays that say nothing" {
		It "leaves the committed list unchanged when the overlay has no data rows" {
			# Exactly what Save-AppCsvOverlay writes for an empty selection: a header and nothing else.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three'
		}

		It "leaves the committed list unchanged when the overlay contains only comments" {
			# A commented-out overlay row is inert on both sides of the layering: it neither adds a
			# row nor replaces the base row that shares its id.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'# Nothing active on this machine yet.'
				'#Base.One,9.9.9,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 3
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Two,Base.Three'
			$rows[0].Version | Should -Be 'Latest'
		}
	}

	Context "List independence" {
		It "applies an overlay only to the list it belongs to" {
			# One overlay per list, resolved through the DataFiles key, so a Scoop choice can never
			# add to or subtract from the WinGet install.
			Write-AppCsvFixture -Path $script:scoopOverlay -Line @(
				'App,Version,Global,Machine'
				''
				'scoop.two,latest,false,All'
				'-scoop.one,latest,false,All'
			)

			$scoopRows = @(Import-AppCsv -DataFileKey ScoopApps -RepoRoot $script:repoRoot)
			$winGetRows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			Get-AppIdSequence -Row $scoopRows | Should -Be 'scoop.two'
			Get-AppIdSequence -Row $winGetRows | Should -Be 'Base.One,Base.Two,Base.Three'
		}
	}

	Context "An App both replaced and removed by the same overlay" {
		It "lets the removal win" {
			# Asserted rather than assumed: the base pass tests the removal index before the
			# replacement index, and the additions pass skips removed ids as well, so a removal
			# cannot be undone by a normal row for the same App.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'-Base.Two,Latest,d,n,w,All'
				'Base.Two,9.9.9,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 2
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Three'
		}

		It "lets the removal win whichever of the two rows comes first" {
			# Both rows are indexed before either is applied, so the outcome does not depend on the
			# order a person happened to write them in.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Base.Two,9.9.9,d,n,w,All'
				'-Base.Two,Latest,d,n,w,All'
			)

			$rows = @(Import-AppCsv -DataFileKey WinGetApps -RepoRoot $script:repoRoot)

			$rows.Count | Should -Be 2
			Get-AppIdSequence -Row $rows | Should -Be 'Base.One,Base.Three'
		}
	}
}
