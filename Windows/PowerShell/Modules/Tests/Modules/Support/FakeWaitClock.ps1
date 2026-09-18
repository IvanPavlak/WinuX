# Shared fake for the wait clock (New-WaitClock). Dot-source it in a test's BeforeAll after the
# function under test, then `Mock New-WaitClock { $script:clock }` or pass `-Clock $clock`.
#
# Sleep advances a virtual time instead of blocking, so a wait with a 750 ms budget and a 10 ms
# poll runs instantly and a test asserts the exact number of polls through $clock.Sleeps.
# Optional hooks let a test script the world: -OnSleep runs after every advance with the new
# elapsed milliseconds, which is how "the window appears at 120 ms" is expressed.

function New-FakeWaitClock {
	param(
		[datetime]$StartUtc = [datetime]::new(2026, 1, 1, 12, 0, 0, [System.DateTimeKind]::Utc),
		[scriptblock]$OnSleep
	)
	$state = @{ ElapsedMs = [long]0; StartUtc = $StartUtc; Sleeps = [System.Collections.Generic.List[int]]::new(); OnSleep = $OnSleep }
	$clock = [pscustomobject]@{ Kind = 'Fake' }
	$clock | Add-Member -MemberType ScriptMethod -Name Now -Value { $state.StartUtc.AddMilliseconds($state.ElapsedMs) }.GetNewClosure()
	$clock | Add-Member -MemberType ScriptMethod -Name ElapsedMs -Value { $state.ElapsedMs }.GetNewClosure()
	$clock | Add-Member -MemberType ScriptMethod -Name Sleep -Value {
		param([int]$Milliseconds)
		$state.Sleeps.Add($Milliseconds)
		$state.ElapsedMs += [math]::Max(0, $Milliseconds)
		if ($state.OnSleep) { & $state.OnSleep $state.ElapsedMs }
	}.GetNewClosure()
	# Advance without a sleep: models time passing while the code under test did other work.
	$clock | Add-Member -MemberType ScriptMethod -Name Advance -Value {
		param([int]$Milliseconds)
		$state.ElapsedMs += [math]::Max(0, $Milliseconds)
	}.GetNewClosure()
	$clock | Add-Member -MemberType ScriptProperty -Name Sleeps -Value { $state.Sleeps }.GetNewClosure()
	return $clock
}
