#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"
	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. "$FunctionsPath\Test-AppliedFancyZonesLayouts.ps1"
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")

	$script:D1 = '{11111111-1111-1111-1111-111111111111}'
	$script:D2 = '{22222222-2222-2222-2222-222222222222}'
	$script:D3 = '{33333333-3333-3333-3333-333333333333}'
	$script:UuidOne = '{AAAAAAAA-0000-0000-0000-000000000001}'
	$script:UuidZero = '{AAAAAAAA-0000-0000-0000-000000000000}'
	$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

	function New-FixtureEntry {
		param([string]$Monitor, [string]$Instance, [string]$Desktop, [string]$Uuid)
		[PSCustomObject]@{
			device           = [PSCustomObject]@{ monitor = $Monitor; 'monitor-instance' = $Instance; 'serial-number' = 'SER1'; 'monitor-number' = 2; 'virtual-desktop' = $Desktop }
			'applied-layout' = [PSCustomObject]@{ uuid = $Uuid; type = 'custom'; 'show-spacing' = $true; spacing = 3; 'zone-count' = 2; 'sensitivity-radius' = 20 }
		}
	}

	function Write-AppliedFixture {
		param([string]$Path, [object[]]$Entries)
		$json = [PSCustomObject]@{ 'applied-layouts' = [object[]]$Entries } | ConvertTo-Json -Depth 10 -Compress
		[System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
	}

	function New-Target {
		param([string]$Desktop, [string]$Uuid, [string]$Instance = '4&abc&0&uid1', [string]$Monitor = 'TESTMON')
		[PSCustomObject]@{ Monitor = $Monitor; MonitorInstance = $Instance; VirtualDesktop = $Desktop; Uuid = $Uuid; Label = "desktop $Desktop" }
	}
}

Describe "Test-AppliedFancyZonesLayouts" {
	BeforeEach {
		Mock Write-LogDebug { }
		# Time is virtual: the last-write poll and the parse retry sleep through this clock.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
		$script:appliedPath = Join-Path $TestDrive ("applied-{0}.json" -f [guid]::NewGuid().ToString('N'))
		Write-AppliedFixture -Path $script:appliedPath -Entries @(
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Desktop $script:D1 -Uuid $script:UuidOne),
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Desktop $script:D2 -Uuid $script:UuidZero)
		)
	}

	It "reports Verified, Mismatch and Missing per target" {
		$result = Test-AppliedFancyZonesLayouts -Targets @(
			(New-Target -Desktop $script:D1 -Uuid $script:UuidOne),
			(New-Target -Desktop $script:D2 -Uuid $script:UuidOne),
			(New-Target -Desktop $script:D3 -Uuid $script:UuidOne)
		) -AppliedLayoutsPath $script:appliedPath

		$result.Readable | Should -BeTrue
		$result.SaveObserved | Should -BeNullOrEmpty
		$result.AllVerified | Should -BeFalse
		$result.VerifiedCount | Should -Be 1
		$result.Targets[0].Status | Should -Be 'Verified'
		$result.Targets[1].Status | Should -Be 'Mismatch'
		$result.Targets[1].ActualUuid | Should -Be $script:UuidZero
		$result.Targets[2].Status | Should -Be 'Missing'
	}

	It "is AllVerified when every target matches" {
		$result = Test-AppliedFancyZonesLayouts -Targets @(
			(New-Target -Desktop $script:D1 -Uuid $script:UuidOne),
			(New-Target -Desktop $script:D2 -Uuid $script:UuidZero)
		) -AppliedLayoutsPath $script:appliedPath

		$result.AllVerified | Should -BeTrue
		$result.VerifiedCount | Should -Be 2
	}

	It "reports Duplicate when two entries claim the same monitor and desktop" {
		# A second entry for the same monitor/desktop is what FancyZones adds when an entry written
		# from outside carries a device block it does not recognize as its own.
		Write-AppliedFixture -Path $script:appliedPath -Entries @(
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Desktop $script:D1 -Uuid $script:UuidOne),
			(New-FixtureEntry -Monitor 'TESTMON' -Instance '4&abc&0&uid1' -Desktop $script:D1 -Uuid $script:UuidZero)
		)

		$result = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath $script:appliedPath

		$result.AllVerified | Should -BeFalse
		$result.Targets[0].Status | Should -Be 'Duplicate'
		$result.Targets[0].ActualUuid | Should -Match ([regex]::Escape($script:UuidZero))
	}

	It "matches the instance case-insensitively and the desktop GUID with or without braces" {
		$result = Test-AppliedFancyZonesLayouts -Targets @(
			(New-Target -Desktop '11111111-1111-1111-1111-111111111111' -Uuid 'aaaaaaaa-0000-0000-0000-000000000001' -Instance '4&ABC&0&UID1' -Monitor 'testmon')
		) -AppliedLayoutsPath $script:appliedPath

		$result.Targets[0].Status | Should -Be 'Verified'
		$result.Targets[0].VirtualDesktop | Should -Be $script:D1
		$result.Targets[0].Uuid | Should -Be $script:UuidOne
	}

	It "observes a write that is later than the given stamp and reports none when there is no later write" {
		$older = (Get-Date).ToUniversalTime().AddMinutes(-2)
		$later = (Get-Date).ToUniversalTime().AddMinutes(5)

		$observed = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath $script:appliedPath -WaitForWriteAfterUtc $older -TimeoutMs 200 -PollIntervalMs 25
		$observed.SaveObserved | Should -BeTrue
		$observed.AllVerified | Should -BeTrue
		# An already-later write is seen on the first check: no polling.
		$script:clock.Sleeps.Count | Should -Be 0

		$waitClock = New-FakeWaitClock
		$notObserved = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath $script:appliedPath -WaitForWriteAfterUtc $later -TimeoutMs 60 -PollIntervalMs 20 -Clock $waitClock

		# A [datetime] parameter that was never bound is not null in PowerShell, so the wait must key
		# off PSBoundParameters: without the parameter SaveObserved stays null (see the first test),
		# with a stamp in the future it times out to $false rather than reporting a phantom save.
		$notObserved.SaveObserved | Should -BeFalse
		$notObserved.AllVerified | Should -BeTrue
		# 60 ms at 20 ms polls: three sleeps, and the clock handed in is the one used - the only
		# New-WaitClock call in this test is the first call above, which was given no clock.
		@($waitClock.Sleeps) | Should -Be @(20, 20, 20)
		Should -Invoke New-WaitClock -Times 1 -Exactly
	}

	It "polls the last-write time until FancyZones saves the file" {
		# The save lands 50 ms of virtual time after the check starts: at 25 ms polls that is
		# the third check, after two sleeps.
		$stamp = (Get-Date).ToUniversalTime().AddMinutes(5)
		$script:clock = New-FakeWaitClock -OnSleep {
			param($elapsedMs)
			if ($elapsedMs -ge 50) { [System.IO.File]::SetLastWriteTimeUtc($script:appliedPath, (Get-Date).ToUniversalTime().AddMinutes(10)) }
		}
		Mock New-WaitClock { $script:clock }

		$result = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath $script:appliedPath -WaitForWriteAfterUtc $stamp -TimeoutMs 750 -PollIntervalMs 25

		$result.SaveObserved | Should -BeTrue
		$result.AllVerified | Should -BeTrue
		@($script:clock.Sleeps) | Should -Be @(25, 25)
	}

	It "reports Unreadable when the file is malformed or missing" {
		[System.IO.File]::WriteAllText($script:appliedPath, '{ "applied-layouts": [ oops', $script:Utf8NoBom)

		$malformed = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath $script:appliedPath
		$missing = Test-AppliedFancyZonesLayouts -Targets @((New-Target -Desktop $script:D1 -Uuid $script:UuidOne)) -AppliedLayoutsPath (Join-Path $TestDrive 'nowhere.json')

		$malformed.Readable | Should -BeFalse
		$malformed.AllVerified | Should -BeFalse
		$malformed.Targets[0].Status | Should -Be 'Unreadable'
		$missing.Readable | Should -BeFalse
		$missing.Targets[0].Status | Should -Be 'Unreadable'
		# The malformed file is re-read four times with a 25 ms pause after each failure (a
		# mid-write file is expected to parse on a retry); a missing file is not retried at all.
		@($script:clock.Sleeps) | Should -Be @(25, 25, 25, 25)
	}
}
