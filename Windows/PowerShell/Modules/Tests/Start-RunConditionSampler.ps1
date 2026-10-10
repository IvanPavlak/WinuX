function Start-RunConditionSampler {
	<#
	.SYNOPSIS
		Starts sampling the machine's conditions in the background for the duration of a test run.

	.DESCRIPTION
		The same suite can take 2.7 times longer from one run to the next, and the cause is the
		machine, not the suite. This records what the machine was doing, so a slow run can be
		explained from its run log alone. Every IntervalMs (2 s) it samples:

		- total CPU use (\Processor Information(_Total)\% Processor Time);
		- \Processor Information(_Total)\% Processor Performance, which reads below 100 when the
		  CPU runs under its rated speed;
		- available memory (\Memory\Available MBytes);
		- the CPU time every process outside the test run used since the previous sample, from
		  Process.TotalProcessorTime deltas. A process belongs to the test run when it, or one of
		  its ancestors, is in the State's ExcludePids set (the orchestrator and its workers).

		It runs in its own runspace on a background thread: opening the performance counters
		takes seconds the first time in a process, and the orchestrator's spinner must not stall
		for it. Any counter that cannot be opened (for example on a Windows installation with
		localized counter names) is simply left out; nothing here can fail a run.

	.PARAMETER ExcludePids
		Process ids that belong to the test run. The orchestrator adds each worker's id to the
		returned State.ExcludePids as it spawns it.

	.PARAMETER IntervalMs
		Milliseconds between samples. Defaults to 2000.

	.OUTPUTS
		[pscustomobject] the sampler handle: State (synchronized; Samples, ExcludePids, Stop),
		PowerShell, AsyncResult. Pass it to Stop-RunConditionSampler.

	.EXAMPLE
		$sampler = Start-RunConditionSampler -ExcludePids $PID
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[int[]]$ExcludePids = @(),

		[Parameter()]
		[int]$IntervalMs = 2000
	)

	$state = [hashtable]::Synchronized(@{
			Stop        = $false
			IntervalMs  = $IntervalMs
			ExcludePids = [System.Collections.Concurrent.ConcurrentDictionary[int, byte]]::new()
			Samples     = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
			Error       = $null
		})
	foreach ($id in $ExcludePids) { [void]$state.ExcludePids.TryAdd($id, 0) }

	$sampleLoop = {
		param($State)

		# Processes whose CPU is caused by the run itself on any machine - Defender scanning the
		# files and processes the tests create, the kernel - stay in the top-consumer list but
		# are kept out of the foreign load that decides whether a run was too noisy to learn from.
		$induced = @('MsMpEng', 'MpDefenderCoreService', 'System', 'Registry', 'Memory Compression', 'Idle')

		$openCounter = {
			param([string]$Category, [string]$Counter, [string]$Instance)
			try {
				$performanceCounter = if ($Instance) { [System.Diagnostics.PerformanceCounter]::new($Category, $Counter, $Instance) } else { [System.Diagnostics.PerformanceCounter]::new($Category, $Counter) }
				$null = $performanceCounter.NextValue()
				$performanceCounter
			}
			catch { $null }
		}

		try {
			$cpuCounter = & $openCounter 'Processor Information' '% Processor Time' '_Total'
			$performanceCounter = & $openCounter 'Processor Information' '% Processor Performance' '_Total'
			$memoryCounter = & $openCounter 'Memory' 'Available MBytes' $null

			$parents = @{}
			$previous = @{}
			$clock = [System.Diagnostics.Stopwatch]::StartNew()
			$previousAt = 0.0

			while (-not $State.Stop) {
				$processes = [System.Diagnostics.Process]::GetProcesses()
				$nowMs = $clock.Elapsed.TotalMilliseconds
				$current = @{}
				foreach ($process in $processes) {
					try { $current[$process.Id] = @{ Name = $process.ProcessName; CpuMs = $process.TotalProcessorTime.TotalMilliseconds; Process = $process } } catch { }
				}

				if ($previous.Count -gt 0) {
					$byName = @{}
					$foreignMs = 0.0
					$inducedMs = 0.0
					foreach ($id in $current.Keys) {
						if (-not $previous.ContainsKey($id) -or $previous[$id].Name -ne $current[$id].Name) { continue }
						$delta = $current[$id].CpuMs - $previous[$id].CpuMs
						if ($delta -le 0) { continue }

						# Walk up the parent chain (cached per process id) looking for the run.
						$ownedByRun = $false
						$walk = $id
						for ($depth = 0; $depth -lt 6 -and $walk; $depth++) {
							if ($State.ExcludePids.ContainsKey($walk)) { $ownedByRun = $true; break }
							if (-not $parents.ContainsKey($walk)) {
								$parentId = 0
								if ($current.ContainsKey($walk)) { try { $parentId = [int]$current[$walk].Process.Parent.Id } catch { $parentId = 0 } }
								$parents[$walk] = $parentId
							}
							$walk = $parents[$walk]
						}
						if ($ownedByRun) { continue }

						$name = $current[$id].Name
						if ($byName.ContainsKey($name)) { $byName[$name] += $delta } else { $byName[$name] = $delta }
						if ($induced -contains $name) { $inducedMs += $delta } else { $foreignMs += $delta }
					}

					$sample = [pscustomobject]@{
						IntervalMs         = $nowMs - $previousAt
						CpuPercent         = $(if ($cpuCounter) { try { [double]$cpuCounter.NextValue() } catch { $null } })
						PerformancePercent = $(if ($performanceCounter) { try { [double]$performanceCounter.NextValue() } catch { $null } })
						AvailableMB        = $(if ($memoryCounter) { try { [double]$memoryCounter.NextValue() } catch { $null } })
						ForeignMs          = $foreignMs
						InducedMs          = $inducedMs
						ByName             = $byName
					}
					[void]$State.Samples.Add($sample)
				}

				foreach ($entry in $previous.Values) { try { $entry.Process.Dispose() } catch { } }
				$previous = $current
				$previousAt = $nowMs

				$waited = 0
				while (-not $State.Stop -and $waited -lt $State.IntervalMs) {
					Start-Sleep -Milliseconds 100
					$waited += 100
				}
			}
			foreach ($entry in $previous.Values) { try { $entry.Process.Dispose() } catch { } }
		}
		catch {
			$State.Error = $_.Exception.Message
		}
	}

	try {
		$powershell = [powershell]::Create()
		[void]$powershell.AddScript($sampleLoop.ToString()).AddArgument($state)
		$asyncResult = $powershell.BeginInvoke()
		return [pscustomobject]@{ State = $state; PowerShell = $powershell; AsyncResult = $asyncResult }
	}
	catch {
		return [pscustomobject]@{ State = $state; PowerShell = $null; AsyncResult = $null }
	}
}
