#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$ConfigFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigFunctionsPath\Save-AppCsvOverlay.ps1"

	# Writes a fixture the way the committed app lists are written: CRLF, UTF-8 without a byte-order
	# mark, COLUMN header on line 1 with any commentary after it.
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

	# Exact byte snapshot, so "the committed list was not touched" and "the backup is the pre-save
	# content" are real assertions rather than text comparisons that could hide an encoding or
	# line-ending change.
	function Get-FileFingerprint {
		param(
			[Parameter(Mandatory = $true)]
			[string]$Path
		)

		return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
	}

	# Reads a CSV the way the installers do, so a row that only the reader's filter would drop cannot
	# be counted here as saved data. Deliberately a local copy of the filter rather than a call into
	# Import-AppCsv: these tests assert what landed on disk, not what the reader makes of it.
	function Get-OverlayDataRow {
		param(
			[Parameter(Mandatory = $true)]
			[string]$Path
		)

		return @(Import-Csv -Path $Path | Where-Object {
				-not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#')
			})
	}

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

	function Get-BaseChocolateyLines {
		return @(
			'App,Version,Params,Force,Machine'
			''
			'choco.one,latest,,false,All'
		)
	}

	# One fully populated row, used wherever the test is about the write rather than the values.
	function Get-SampleWinGetRow {
		return @(
			@{ App = 'Overlay.One'; Version = 'Latest'; Scope = 'd'; Interactive = 'n'; Source = 'w'; Machine = 'All' }
		)
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Save-AppCsvOverlay" {
	BeforeEach {
		# A synthetic repository under TestDrive, rebuilt from scratch for every test. This function
		# WRITES files, and the overlay it writes lands beside the base file, so pointing it at the
		# working tree would drop overlays into the tracked Data folder where they would shadow the
		# committed app lists. The folder is cleared first as well, so no stale overlay or .bak can
		# make an assertion pass for the wrong reason.
		$script:repoRoot = Join-Path $TestDrive "repo"
		$script:dataRoot = Join-Path $script:repoRoot "Windows\PowerShell\Modules\Bootstrap\Data"

		if (Test-Path -Path $script:repoRoot) {
			Remove-Item -Path $script:repoRoot -Recurse -Force
		}

		New-Item -ItemType Directory -Path $script:dataRoot -Force | Out-Null

		$script:winGetBase = Join-Path $script:dataRoot "WinGetApps.csv"
		$script:winGetOverlay = Join-Path $script:dataRoot "WinGetApps.local.csv"
		$script:winGetBackup = "$($script:winGetOverlay).bak"
		$script:chocoBase = Join-Path $script:dataRoot "ChocolateyApps.csv"
		$script:chocoOverlay = Join-Path $script:dataRoot "ChocolateyApps.local.csv"

		Write-AppCsvFixture -Path $script:winGetBase -Line (Get-BaseWinGetLines)
		Write-AppCsvFixture -Path $script:chocoBase -Line (Get-BaseChocolateyLines)

		# The two globals the function reads. MachineSpecificPaths is pointed at the sandbox as well,
		# so even a call that forgot -RepoRoot could not write into the real repository.
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

	Context "Writing the overlay" {
		It "writes the overlay and reports Written, RowCount and OverlayPath" {
			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot

			$result.Written | Should -BeTrue
			$result.RowCount | Should -Be 1
			$result.OverlayPath | Should -Be $script:winGetOverlay
			Test-Path -Path $script:winGetOverlay | Should -BeTrue

			$saved = @(Get-OverlayDataRow -Path $script:winGetOverlay)
			$saved.Count | Should -Be 1
			$saved[0].App | Should -Be 'Overlay.One'
			$saved[0].Machine | Should -Be 'All'
		}

		It "never modifies the committed CSV" {
			# The single most important property of the whole overlay design. The committed list is
			# read to take its header and validate against, and is never written, which is what keeps
			# a fork's app choices out of a tracked file and stops an upstream pull from conflicting
			# on one. Compared as bytes, so an encoding or line-ending change would count as a change.
			$before = Get-FileFingerprint -Path $script:winGetBase

			Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(
				@{ App = 'Overlay.One'; Version = 'Latest'; Scope = 'd'; Interactive = 'n'; Source = 'w'; Machine = 'All' }
				@{ App = 'Base.Two'; Version = '2.5.0'; Scope = 'm'; Interactive = 'n'; Source = 'w'; Machine = 'All' }
				@{ App = '-Base.Three'; Version = 'Latest'; Scope = 'd'; Interactive = 'n'; Source = 'w'; Machine = 'All' }
			) -RepoRoot $script:repoRoot | Out-Null

			# A row that replaces a base row and a row that removes one are the two cases most likely
			# to tempt an implementation into editing the base file, so both are in this save.
			Get-FileFingerprint -Path $script:winGetBase | Should -Be $before
		}

		It "writes the column header as the very first line, matching the committed header exactly" {
			# Import-Csv takes line 1 as the header UNCONDITIONALLY. A leading comment line would
			# therefore be read as the header, every data row would parse under a bogus column name,
			# every row would come back with an empty App, and the reader's blank-App filter would
			# silently drop the entire overlay. That was a real bug, caught before release, which is
			# why the banner goes after the header and why this is asserted on the file itself.
			Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot | Out-Null

			$baseHeader = @(Get-Content -Path $script:winGetBase -TotalCount 1)[0]
			$overlayLines = @(Get-Content -Path $script:winGetOverlay)

			$overlayLines[0] | Should -BeExactly $baseHeader
			$overlayLines[0] | Should -Not -Match '^\s*#'
		}

		It "writes the managed comment banner after the header" {
			# The banner is what tells a person reading the file who owns it and what a -<id> row
			# means. It sits below the header, and the reader drops it as commentary.
			Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot | Out-Null

			$text = [System.IO.File]::ReadAllText($script:winGetOverlay)
			$text | Should -Match '# WinGetApps\.local\.csv'
			$text | Should -Match 'Written by Save-AppCsvOverlay'
			$text | Should -Match 'The committed CSV is never edited'

			@(Get-OverlayDataRow -Path $script:winGetOverlay).Count | Should -Be 1
		}
	}

	Context "Backups" {
		It "copies the previous overlay to a .bak whose content is the pre-save content" {
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Overlay.Previous,Latest,d,n,w,All'
			)

			$before = Get-FileFingerprint -Path $script:winGetOverlay

			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot

			$result.BackupPath | Should -Be $script:winGetBackup
			Test-Path -Path $script:winGetBackup | Should -BeTrue

			# Restoring the .bak is the complete undo, so it has to be the exact pre-save bytes.
			Get-FileFingerprint -Path $script:winGetBackup | Should -Be $before
			@(Get-OverlayDataRow -Path $script:winGetBackup)[0].App | Should -Be 'Overlay.Previous'
		}

		It "does not create a .bak when there was no overlay to back up" {
			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot

			Test-Path -Path $script:winGetBackup | Should -BeFalse
			$result.BackupPath | Should -BeNullOrEmpty
		}

		It "does not create a .bak when -NoBackup is given" {
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Overlay.Previous,Latest,d,n,w,All'
			)

			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot -NoBackup

			Test-Path -Path $script:winGetBackup | Should -BeFalse
			$result.BackupPath | Should -BeNullOrEmpty
			@(Get-OverlayDataRow -Path $script:winGetOverlay)[0].App | Should -Be 'Overlay.One'
		}
	}

	Context "WhatIf" {
		It "writes nothing, backs up nothing, reports Written as false and leaves no .tmp behind" {
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Overlay.Previous,Latest,d,n,w,All'
			)

			$before = Get-FileFingerprint -Path $script:winGetOverlay

			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot $script:repoRoot -WhatIf

			$result.Written | Should -BeFalse
			$result.RowCount | Should -Be 1
			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $before
			Test-Path -Path $script:winGetBackup | Should -BeFalse

			# The candidate is still staged and parsed under -WhatIf, because reporting what would be
			# written is only useful if the same validation ran, so the cleanup has to happen anyway.
			@(Get-ChildItem -Path $script:dataRoot -Filter '*.tmp' -Force).Count | Should -Be 0
		}
	}

	Context "Validation" {
		BeforeEach {
			# A refusal has to leave whatever was already on disk exactly as it was, so every case
			# here runs against an existing overlay rather than a missing one.
			Write-AppCsvFixture -Path $script:winGetOverlay -Line @(
				'App,Version,Scope,Interactive,Source,Machine'
				''
				'Overlay.Previous,Latest,d,n,w,All'
			)

			$script:overlayBefore = Get-FileFingerprint -Path $script:winGetOverlay
		}

		It "refuses a row with no App id" {
			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = ''; Machine = 'All' }) -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*no App id*'

			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $script:overlayBefore
			Test-Path -Path $script:winGetBackup | Should -BeFalse
		}

		It "refuses a row that is not assigned to any machine" {
			# A blank Machine cell matches nothing, so the row would sit in the overlay looking
			# installed and never install - the most confusing possible outcome. It is refused where
			# the overlay is written, not left for the installer to skip silently.
			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.One'; Machine = '' }) -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*not assigned to any PC*'

			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $script:overlayBefore
			Test-Path -Path $script:winGetBackup | Should -BeFalse
		}

		It "refuses an unknown machine type" {
			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.One'; Machine = 'Labtop' }) -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage '*not a known machine type*'

			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $script:overlayBefore
			Test-Path -Path $script:winGetBackup | Should -BeFalse
		}

		It "refuses an unknown token inside a slash-joined machine list" {
			# Every token is checked, not just the first, because one good token would otherwise make
			# a typo in the rest of the cell invisible.
			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.One'; Machine = 'PC/Labtop' }) -RepoRoot $script:repoRoot } |
				Should -Throw -ExpectedMessage "*targets 'Labtop'*"

			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $script:overlayBefore
			Test-Path -Path $script:winGetBackup | Should -BeFalse
		}

		It "refuses a -RepoRoot that was given but is empty" {
			# Falling back to this machine's own clone here would write an overlay beside the TRACKED
			# app lists when the caller plainly meant to work in a sandbox. Omitting the parameter
			# still uses the fallback; passing it blank is always an accident.
			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row (Get-SampleWinGetRow) -RepoRoot '' } |
				Should -Throw -ExpectedMessage '*-RepoRoot was given but is empty*'

			Get-FileFingerprint -Path $script:winGetOverlay | Should -Be $script:overlayBefore
		}

		It "accepts All" {
			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.One'; Machine = 'All' }) -RepoRoot $script:repoRoot

			$result.Written | Should -BeTrue
			@(Get-OverlayDataRow -Path $script:winGetOverlay)[0].Machine | Should -Be 'All'
		}

		It "accepts a slash-joined list of known machine types" {
			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.One'; Machine = 'PC/Work' }) -RepoRoot $script:repoRoot

			$result.Written | Should -BeTrue
			@(Get-OverlayDataRow -Path $script:winGetOverlay)[0].Machine | Should -Be 'PC/Work'
		}
	}

	Context "An empty overlay" {
		It "writes a header-only overlay for an empty -Row and reports RowCount 0" {
			# "This machine adds nothing" is a real state, and it is not the same as having no overlay
			# file at all: the file exists, so the reader layers an empty overlay and the caller knows
			# it is managing this list.
			$result = Save-AppCsvOverlay -DataFileKey WinGetApps -Row @() -RepoRoot $script:repoRoot

			$result.Written | Should -BeTrue
			$result.RowCount | Should -Be 0
			Test-Path -Path $script:winGetOverlay | Should -BeTrue

			$baseHeader = @(Get-Content -Path $script:winGetBase -TotalCount 1)[0]

			@(Get-OverlayDataRow -Path $script:winGetOverlay).Count | Should -Be 0
			@(Get-Content -Path $script:winGetOverlay)[0] | Should -BeExactly $baseHeader
		}
	}

	Context "Quoting" {
		It "quotes a value containing a comma so it round-trips through Import-Csv" {
			# A Chocolatey Params cell is the realistic case. Unquoted, its comma would split the row
			# into more fields than the header has, and the round-trip count check would refuse the
			# save rather than write a file that parses into the wrong shape.
			$chocolateyParams = '/InstallDir:C:\Tools,/NoDesktop'

			$result = Save-AppCsvOverlay -DataFileKey ChocolateyApps -Row @(
				@{ App = 'choco.two'; Version = 'latest'; Params = $chocolateyParams; Force = 'false'; Machine = 'All' }
			) -RepoRoot $script:repoRoot

			$result.Written | Should -BeTrue
			$result.RowCount | Should -Be 1

			$saved = @(Get-OverlayDataRow -Path $script:chocoOverlay)
			$saved.Count | Should -Be 1
			$saved[0].Params | Should -BeExactly $chocolateyParams
			$saved[0].Machine | Should -Be 'All'
		}

		It "round-trips a value containing a double quote" {
			$chocolateyParams = '/Args:"--silent --no-desktop"'

			$result = Save-AppCsvOverlay -DataFileKey ChocolateyApps -Row @(
				@{ App = 'choco.two'; Version = 'latest'; Params = $chocolateyParams; Force = 'false'; Machine = 'All' }
			) -RepoRoot $script:repoRoot

			$result.RowCount | Should -Be 1

			$saved = @(Get-OverlayDataRow -Path $script:chocoOverlay)
			$saved.Count | Should -Be 1
			$saved[0].Params | Should -BeExactly $chocolateyParams
		}
	}

	Context "Columns" {
		It "takes the columns from the committed header, so an unknown extra key adds no column" {
			# The overlay can never drift into a shape the installer does not read, because the header
			# is copied from the committed file rather than derived from the rows it is handed.
			Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(
				@{ App = 'Overlay.One'; Version = 'Latest'; Scope = 'd'; Interactive = 'n'; Source = 'w'; Machine = 'All'; Nonsense = 'ignored' }
			) -RepoRoot $script:repoRoot | Out-Null

			$baseHeader = @(Get-Content -Path $script:winGetBase -TotalCount 1)[0]
			@(Get-Content -Path $script:winGetOverlay)[0] | Should -BeExactly $baseHeader

			$saved = @(Get-OverlayDataRow -Path $script:winGetOverlay)
			@($saved[0].PSObject.Properties.Name).Count | Should -Be 6
			$saved[0].PSObject.Properties.Name | Should -Not -Contain 'Nonsense'
			[System.IO.File]::ReadAllText($script:winGetOverlay) | Should -Not -Match 'ignored'
		}
	}

	Context "Temporary files" {
		It "leaves no .tmp file in the data folder, whether the save succeeds, is refused or is a -WhatIf" {
			# The candidate is staged in the destination folder so the replace is a same-volume rename
			# a reader can never observe half-written. Every exit path has to clean that staging file
			# up, including the ones that throw.
			$row = Get-SampleWinGetRow

			Save-AppCsvOverlay -DataFileKey WinGetApps -Row $row -RepoRoot $script:repoRoot | Out-Null
			Save-AppCsvOverlay -DataFileKey WinGetApps -Row $row -RepoRoot $script:repoRoot -WhatIf | Out-Null

			{ Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = 'Overlay.Two'; Machine = 'Labtop' }) -RepoRoot $script:repoRoot } |
				Should -Throw

			@(Get-ChildItem -Path $script:dataRoot -Filter '*.tmp' -Force).Count | Should -Be 0
		}
	}
}
