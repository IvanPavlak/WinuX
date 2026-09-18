function New-WaitClock {
	<#
	.SYNOPSIS
		Creates the clock every poll loop reads time from and sleeps through.

	.DESCRIPTION
		The seam that makes waiting testable. A wait loop that calls Start-Sleep and reads a
		Stopwatch directly can only be tested by actually waiting; one that goes through this
		clock can be handed a fake whose Sleep advances a virtual time instead, so a 750 ms
		timeout ladder runs in microseconds and asserts the exact number of polls.

		The real clock is a Stopwatch started at creation plus Start-Sleep. Its three members are
		the whole contract, and a fake implements the same three:

		  - Now()          [datetime] UTC now
		  - ElapsedMs()    [long] milliseconds since the clock was created
		  - Sleep([int])   blocks for that many milliseconds (a fake advances instead)

		Wait-Until takes a -Clock; the functions built on it accept one too and default to this.

	.OUTPUTS
		[pscustomobject] with Now, ElapsedMs and Sleep script methods.

	.EXAMPLE
		$clock = New-WaitClock
		while ($clock.ElapsedMs() -lt 500) { $clock.Sleep(10) }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	$clock = [pscustomobject]@{ Kind = 'Real' }
	$clock | Add-Member -MemberType ScriptMethod -Name Now -Value { [datetime]::UtcNow }.GetNewClosure()
	$clock | Add-Member -MemberType ScriptMethod -Name ElapsedMs -Value { $stopwatch.ElapsedMilliseconds }.GetNewClosure()
	$clock | Add-Member -MemberType ScriptMethod -Name Sleep -Value {
		param([int]$Milliseconds)
		if ($Milliseconds -gt 0) { Start-Sleep -Milliseconds $Milliseconds }
	}.GetNewClosure()
	return $clock
}
