#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Window\Functions"
	. "$FunctionsPath\Get-CachedFancyZonesLayouts.ps1"
	. "$FunctionsPath\Write-AppliedFancyZonesLayouts.ps1"

	# FancyZones-shaped fixtures. Monitor TESTMON (instance written lower-case, as FancyZones does)
	# has entries on desktops D1 and D2, OTHER01 has one on D1. Layouts: One is a 1x2 grid (cells 0
	# and 1), Zero a 1x1 grid, Free a three-zone canvas.
	$script:D1 = '{11111111-1111-1111-1111-111111111111}'
	$script:D2 = '{22222222-2222-2222-2222-222222222222}'
	$script:D3 = '{33333333-3333-3333-3333-333333333333}'
	$script:UuidOne = '{AAAAAAAA-0000-0000-0000-000000000001}'
	$script:UuidZero = '{AAAAAAAA-0000-0000-0000-000000000000}'
	$script:UuidFree = '{AAAAAAAA-0000-0000-0000-00000000000F}'
	$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

	function New-FixtureEntry {
		param([string]$Monitor, [string]$Instance, [string]$Serial, [int]$Number, [string]$Desktop, [string]$Uuid, [string]$Type = 'custom', [int]$ZoneCount = 1)
		[PSCustomObject]@{
			device           = [PSCustomObject]@{ monitor = $Monitor; 'monitor-instance' = $Instance; 'serial-number' = $Serial; 'monitor-number' = $Number; 'virtual-desktop' = $Desktop }
			'applied-layout' = [PSCustomObject]@{ uuid = $Uuid; type = $Type; 'show-spacing' = $true; spacing = 3; 'zone-count' = $ZoneCount; 'sensitivity-radius' = 20 }
		}
	}

	function New-AppliedLayoutsFixture {
		param([string]$Path)
		$entries = @(
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Serial 'SER1' -Number 2 -Desktop $script:D1 -Uuid $script:UuidOne -ZoneCount 2),
			(New-FixtureEntry -Monitor 'OTHER01' -Instance '4&abc&0&uid2' -Serial '' -Number 1 -Desktop $script:D1 -Uuid '{00000000-0000-0000-0000-000000000000}' -Type 'priority-grid' -ZoneCount 3),
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Serial 'SER1' -Number 2 -Desktop $script:D2 -Uuid $script:UuidZero -ZoneCount 1)
		)
		$json = [PSCustomObject]@{ 'applied-layouts' = [object[]]$entries } | ConvertTo-Json -Depth 10 -Compress
		[System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
	}

	function New-CustomLayoutsFixture {
		param([string]$Path)
		$layouts = @(
			[PSCustomObject]@{ uuid = $script:UuidZero; name = 'Zero'; type = 'grid'; info = [PSCustomObject]@{ rows = 1; columns = 1; 'rows-percentage' = @(10000); 'columns-percentage' = @(10000); 'cell-child-map' = @(, @(0)); 'show-spacing' = $true; spacing = 3; 'sensitivity-radius' = 20 } },
			[PSCustomObject]@{ uuid = $script:UuidOne; name = 'One'; type = 'grid'; info = [PSCustomObject]@{ rows = 1; columns = 2; 'rows-percentage' = @(10000); 'columns-percentage' = @(5000, 5000); 'cell-child-map' = @(, @(0, 1)); 'show-spacing' = $false; spacing = 7; 'sensitivity-radius' = 25 } },
			[PSCustomObject]@{ uuid = $script:UuidFree; name = 'Free'; type = 'canvas'; info = [PSCustomObject]@{ 'ref-width' = 1920; 'ref-height' = 1080; zones = @([PSCustomObject]@{ X = 0; Y = 0; width = 10; height = 10 }, [PSCustomObject]@{ X = 10; Y = 0; width = 10; height = 10 }, [PSCustomObject]@{ X = 20; Y = 0; width = 10; height = 10 }); 'sensitivity-radius' = 30 } }
		)
		$json = [PSCustomObject]@{ 'custom-layouts' = [object[]]$layouts } | ConvertTo-Json -Depth 10 -Compress
		[System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
	}

	function Read-AppliedFixture {
		param([string]$Path)
		@((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).'applied-layouts')
	}
}

Describe "Write-AppliedFancyZonesLayouts" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Test-LogVerbose { $false }

		# Fresh files per test. The custom-layouts cache is keyed by path, so a new path per test
		# means no stale hit; the applied-layouts cache starts populated to prove invalidation.
		$script:FancyZonesCache = @{ Path = $null; Data = $null; Timestamp = [datetime]::MinValue; MaxAgeSec = 60 }
		$script:AppliedLayoutsCache = @{ Data = @{ stale = $true }; Timestamp = [datetime]::Now; MaxAgeSec = 10 }
		$script:appliedPath = Join-Path $TestDrive ("applied-{0}.json" -f [guid]::NewGuid().ToString('N'))
		$script:customPath = Join-Path $TestDrive ("custom-{0}.json" -f [guid]::NewGuid().ToString('N'))
		New-AppliedLayoutsFixture -Path $script:appliedPath
		New-CustomLayoutsFixture -Path $script:customPath
	}

	It "writes a new desktop entry by cloning the monitor's own device block" {
		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&ABC&0&UID1'; VirtualDesktop = $script:D3; LayoutName = 'One'; Label = 'Primary/desktop 3' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeTrue
		$result.WrittenCount | Should -Be 1
		$result.WrittenAtUtc | Should -Not -BeNullOrEmpty
		$result.Targets[0].Status | Should -Be 'Written'
		$result.Targets[0].Uuid | Should -Be $script:UuidOne
		$result.Targets[0].Label | Should -Be 'Primary/desktop 3'

		$entries = Read-AppliedFixture $script:appliedPath
		$entries.Count | Should -Be 4
		$new = $entries[3]
		$new.device.monitor | Should -Be 'TESTMON'
		# FancyZones' own casing of the instance, serial number and monitor number: the entry must
		# equal the work-area id FancyZones matches against, so they are cloned, never rebuilt.
		$new.device.'monitor-instance' | Should -BeExactly '4&abc&0&uid1'
		$new.device.'serial-number' | Should -Be 'SER1'
		$new.device.'monitor-number' | Should -Be 2
		$new.device.'virtual-desktop' | Should -Be $script:D3
		# CustomLayouts::GetLayout equivalent: custom type, the grid's own spacing settings,
		# highest cell index + 1 zones.
		$new.'applied-layout'.uuid | Should -Be $script:UuidOne
		$new.'applied-layout'.type | Should -Be 'custom'
		$new.'applied-layout'.'zone-count' | Should -Be 2
		$new.'applied-layout'.spacing | Should -Be 7
		$new.'applied-layout'.'show-spacing' | Should -BeFalse
		$new.'applied-layout'.'sensitivity-radius' | Should -Be 25
	}

	It "replaces an existing entry in place and leaves every other entry where it was" {
		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D2; LayoutName = 'One' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeTrue
		$entries = Read-AppliedFixture $script:appliedPath
		$entries.Count | Should -Be 3
		$entries[0].device.'virtual-desktop' | Should -Be $script:D1
		$entries[0].'applied-layout'.uuid | Should -Be $script:UuidOne
		$entries[1].device.monitor | Should -Be 'OTHER01'
		$entries[1].'applied-layout'.type | Should -Be 'priority-grid'
		$entries[2].device.'virtual-desktop' | Should -Be $script:D2
		$entries[2].'applied-layout'.uuid | Should -Be $script:UuidOne
		$entries[2].'applied-layout'.'zone-count' | Should -Be 2
	}

	It "reports AlreadyApplied and leaves the file untouched when the entry already holds the layout" {
		$stampBefore = [System.IO.File]::GetLastWriteTimeUtc($script:appliedPath)

		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D1; LayoutName = 'One' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeFalse
		$result.WrittenAtUtc | Should -BeNullOrEmpty
		$result.AlreadyAppliedCount | Should -Be 1
		$result.Targets[0].Status | Should -Be 'AlreadyApplied'
		[System.IO.File]::GetLastWriteTimeUtc($script:appliedPath) | Should -Be $stampBefore
		# Nothing was written, so the cache still describes the file.
		$script:AppliedLayoutsCache.Data | Should -Not -BeNullOrEmpty
	}

	It "rewrites an identical entry under -Force and bumps the last-write time so FancyZones reloads" {
		$stampBefore = (Get-Date).ToUniversalTime().AddMinutes(-1)
		[System.IO.File]::SetLastWriteTimeUtc($script:appliedPath, $stampBefore)

		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D1; LayoutName = 'One' }
		) -Force -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeTrue
		$result.Targets[0].Status | Should -Be 'Written'
		[System.IO.File]::GetLastWriteTimeUtc($script:appliedPath) | Should -BeGreaterThan $stampBefore
		$result.WrittenAtUtc | Should -BeGreaterThan $stampBefore
		$entries = Read-AppliedFixture $script:appliedPath
		$entries.Count | Should -Be 3
		$entries[0].'applied-layout'.uuid | Should -Be $script:UuidOne
	}

	It "reports NoDeviceEntry and UnknownLayout without writing anything" {
		$stampBefore = [System.IO.File]::GetLastWriteTimeUtc($script:appliedPath)

		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'NEVERSEEN'; MonitorInstance = '4&abc&0&uid9'; VirtualDesktop = $script:D3; LayoutName = 'One' },
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D3; LayoutName = 'NotALayout' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeFalse
		$result.UnresolvedCount | Should -Be 2
		$result.Targets[0].Status | Should -Be 'NoDeviceEntry'
		$result.Targets[1].Status | Should -Be 'UnknownLayout'
		[System.IO.File]::GetLastWriteTimeUtc($script:appliedPath) | Should -Be $stampBefore
		(Read-AppliedFixture $script:appliedPath).Count | Should -Be 3
	}

	It "never overwrites a file it cannot parse" {
		# FancyZones reads a malformed applied-layouts.json as "no layouts at all", so a write on top
		# of one would wipe every layout it knows about.
		[System.IO.File]::WriteAllText($script:appliedPath, '{ "applied-layouts": [ oops', $script:Utf8NoBom)

		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D3; LayoutName = 'One' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeFalse
		$result.Error | Should -Match 'not valid JSON'
		$result.Targets[0].Status | Should -Be 'NoDeviceEntry'
		Get-Content -LiteralPath $script:appliedPath -Raw | Should -Be '{ "applied-layouts": [ oops'
	}

	It "derives a canvas layout's zone count from its zones and takes FancyZones' spacing defaults" {
		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D3; LayoutName = 'Free' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeTrue
		$new = (Read-AppliedFixture $script:appliedPath)[3]
		$new.'applied-layout'.uuid | Should -Be $script:UuidFree
		$new.'applied-layout'.'zone-count' | Should -Be 3
		$new.'applied-layout'.spacing | Should -Be 16
		$new.'applied-layout'.'show-spacing' | Should -BeTrue
		$new.'applied-layout'.'sensitivity-radius' | Should -Be 30
	}

	It "matches monitor and desktop case-insensitively and accepts a GUID without braces" {
		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'testmon'; MonitorInstance = '4&ABC&0&UID1'; VirtualDesktop = '11111111-1111-1111-1111-111111111111'; LayoutName = 'Zero' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$result.Written | Should -BeTrue
		$result.Targets[0].VirtualDesktop | Should -Be $script:D1
		$entries = Read-AppliedFixture $script:appliedPath
		$entries.Count | Should -Be 3
		$entries[0].'applied-layout'.uuid | Should -Be $script:UuidZero
		$entries[0].'applied-layout'.'zone-count' | Should -Be 1
	}

	It "invalidates the module's applied-layouts cache after a write" {
		$null = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D3; LayoutName = 'One' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$script:AppliedLayoutsCache.Data | Should -BeNullOrEmpty
		$script:AppliedLayoutsCache.Timestamp | Should -Be ([datetime]::MinValue)
	}

	It "writes the shape FancyZones writes: one compact line, UTF-8 without a byte order mark, no temp file left" {
		$null = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'TESTMON'; MonitorInstance = '4&abc&0&uid1'; VirtualDesktop = $script:D3; LayoutName = 'One' }
		) -AppliedLayoutsPath $script:appliedPath -CustomLayoutsPath $script:customPath

		$raw = Get-Content -LiteralPath $script:appliedPath -Raw
		$raw | Should -Not -Match "`n"
		$raw | Should -Match '^\{"applied-layouts":\['
		$bytes = [System.IO.File]::ReadAllBytes($script:appliedPath)
		$bytes[0] | Should -Be 0x7B
		@(Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp').Count | Should -Be 0
	}
}
