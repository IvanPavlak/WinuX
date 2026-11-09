function Test-StartupCondition {
	<#
	.SYNOPSIS
		Waits until a named startup condition is met, or its timeout passes.

	.DESCRIPTION
		A startup task lists the conditions it needs in `Requires` (the network, a VPN, a
		service). Each name is an entry of `Startup.Conditions`:

		  Startup = @{ Conditions = @{ MyVpn = @{ Test = 'myvpn status *> $null; $LASTEXITCODE -eq 0'; Timeout = 120; Interval = 2 } } }

		`Test` is a command line. The condition is met when its output is truthy, exactly like
		the condition of an `if`: `$true`, a non-empty string, a process object. A command that
		throws, or prints nothing, has not met it. For a program whose exit code is the answer,
		end the test with `$LASTEXITCODE -eq 0`. Errors the test writes are not shown, and the
		caller's `$LASTEXITCODE` is put back afterwards.

		The test runs every `Interval` seconds (default 2) until it is met or `Timeout` seconds
		(default 60) have passed. A `Timeout` of 0 tests once. -NoWait tests once whatever the
		timeout says, which is what `Invoke-StartupTasks -WhatIf` shows.

		A name with no entry, an entry without `Test` or a test that does not parse is reported
		and counts as not met, so a typo never lets a task run early.

	.PARAMETER Name
		The condition's name, as written in a task's `Requires`.

	.PARAMETER Definitions
		The conditions to look the name up in: name => @{ Test; Timeout; Interval }. Defaults to
		`Startup.Conditions` of the configuration.

	.PARAMETER NoWait
		Test once and return, without waiting for the timeout.

	.OUTPUTS
		[bool] - $true when the condition was met in time.

	.EXAMPLE
		Test-StartupCondition -Name Network
		Waits up to the configured timeout for the network, and returns whether it came up.

	.EXAMPLE
		Test-StartupCondition -Name MyVpn -NoWait
		Whether MyVpn is up right now.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,

		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$Definitions,

		[Parameter()]
		[switch]$NoWait
	)

	if ($null -eq $Definitions) {
		$Definitions = Get-ConfigSetting -Path 'Startup.Conditions' -Default @{}
	}

	$definition = $null
	foreach ($key in @($Definitions.Keys)) {
		if ([string]$key -eq $Name) { $definition = $Definitions[$key]; break }
	}

	if (-not ($definition -is [System.Collections.IDictionary])) {
		Write-LogError "Unknown startup condition [$Name] - define it under Startup.Conditions"
		return $false
	}

	$testText = [string]$definition['Test']
	if ([string]::IsNullOrWhiteSpace($testText)) {
		Write-LogError "Startup condition [$Name] has no Test command"
		return $false
	}

	try {
		$test = [scriptblock]::Create($testText)
	}
	catch {
		Write-LogError "Startup condition [$Name] has a Test that does not parse => $($_.Exception.Message)"
		return $false
	}

	$timeout = 60.0
	$parsed = 0.0
	if ($null -ne $definition['Timeout'] -and [double]::TryParse("$($definition['Timeout'])", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -and $parsed -ge 0) {
		$timeout = $parsed
	}

	$interval = 2.0
	if ($null -ne $definition['Interval'] -and [double]::TryParse("$($definition['Interval'])", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -and $parsed -gt 0) {
		$interval = $parsed
	}

	$exitCode = $global:LASTEXITCODE
	$deadline = (Get-Date).AddSeconds($timeout)
	$announced = $false
	try {
		while ($true) {
			$met = $false
			try { $met = [bool](& $test 2>$null) } catch { $met = $false }
			if ($met) { return $true }

			if ($NoWait -or (Get-Date) -ge $deadline) { return $false }

			if (-not $announced) {
				Write-LogStep "Waiting for [$Name] (up to $([int]$timeout) s)"
				$announced = $true
			}
			Start-Sleep -Milliseconds ([int]($interval * 1000))
		}
	}
	finally {
		$global:LASTEXITCODE = $exitCode
	}
}
