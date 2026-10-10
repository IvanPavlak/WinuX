#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Get-RunConditionSummary.ps1")

	function New-Sample {
		param([double]$IntervalMs = 2000, $Cpu = 50, $Performance = 100, $Memory = 8000, [double]$ForeignMs = 0, [hashtable]$ByName = @{})
		[pscustomobject]@{ IntervalMs = $IntervalMs; CpuPercent = $Cpu; PerformancePercent = $Performance; AvailableMB = $Memory; ForeignMs = $ForeignMs; InducedMs = 0; ByName = $ByName }
	}
}

Describe "Get-RunConditionSummary" {
	It "averages CPU, and reports the lowest clock and the least free memory" {
		$samples = @(
			New-Sample -Cpu 40 -Performance 100 -Memory 9000
			New-Sample -Cpu 80 -Performance 85 -Memory 7000
		)
		$summary = Get-RunConditionSummary -Samples $samples -ProcessorCount 8
		$summary.SampleCount | Should -Be 2
		$summary.AvgCpuPercent | Should -Be 60
		$summary.MaxCpuPercent | Should -Be 80
		$summary.MinPerformancePercent | Should -Be 85
		$summary.MinAvailableMB | Should -Be 7000
	}

	It "expresses foreign CPU as a share of the whole machine over the sampled time" {
		# Two 2 s samples on 4 threads = 16 s of capacity; 1.6 s of foreign CPU is 10%.
		$samples = @(
			New-Sample -IntervalMs 2000 -ForeignMs 1000
			New-Sample -IntervalMs 2000 -ForeignMs 600
		)
		(Get-RunConditionSummary -Samples $samples -ProcessorCount 4).ForeignLoadPercent | Should -Be 10
	}

	It "ranks the processes outside the run by their summed CPU time across samples" {
		$samples = @(
			New-Sample -ByName @{ chrome = 3000; MsMpEng = 500 }
			New-Sample -ByName @{ chrome = 1000; Code = 2500; MsMpEng = 700 }
		)
		$top = @((Get-RunConditionSummary -Samples $samples -ProcessorCount 8 -Top 2).TopConsumers)
		$top.Count | Should -Be 2
		$top[0].Name | Should -Be 'chrome'
		$top[0].CpuSeconds | Should -Be 4
		$top[1].Name | Should -Be 'Code'
	}

	It "summarizes worker start-up and ignores missing values" {
		$summary = Get-RunConditionSummary -Samples @() -StartupSeconds 4, 6, 8 -ProcessorCount 8
		$summary.StartupMin | Should -Be 4
		$summary.StartupAvg | Should -Be 6
		$summary.StartupMax | Should -Be 8
	}

	It "reports an unknown load, not zero, when nothing was sampled" {
		$summary = Get-RunConditionSummary -Samples @() -ProcessorCount 8
		$summary.SampleCount | Should -Be 0
		$summary.ForeignLoadPercent | Should -Be -1
		$summary.AvgCpuPercent | Should -BeNullOrEmpty
		$summary.StartupAvg | Should -BeNullOrEmpty
	}

	It "skips counters the sampler could not read" {
		$samples = @(
			New-Sample -Cpu $null -Performance $null -Memory 5000
			New-Sample -Cpu $null -Performance $null -Memory 6000
		)
		$summary = Get-RunConditionSummary -Samples $samples -ProcessorCount 8
		$summary.AvgCpuPercent | Should -BeNullOrEmpty
		$summary.MinPerformancePercent | Should -BeNullOrEmpty
		$summary.MinAvailableMB | Should -Be 5000
	}
}
