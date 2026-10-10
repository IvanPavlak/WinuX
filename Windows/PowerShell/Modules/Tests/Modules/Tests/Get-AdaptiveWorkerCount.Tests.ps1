#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Get-AdaptiveWorkerCount.ps1")

	# Runs as Read-WorkerHistory returns them: one object per recorded run, oldest first.
	function New-Runs {
		param([object[]]$Pairs)
		foreach ($pair in $Pairs) { [pscustomobject]@{ workers = $pair[0]; wallSec = $pair[1] } }
	}
}

Describe "Get-AdaptiveWorkerCount" {
	Context "No history" {
		It "uses min(CPU, 12)" {
			(Get-AdaptiveWorkerCount -ProcessorCount 22 -FileCount 450).Count | Should -Be 12
			(Get-AdaptiveWorkerCount -ProcessorCount 8 -FileCount 450).Count | Should -Be 8
			(Get-AdaptiveWorkerCount -ProcessorCount 22 -FileCount 450).Phase | Should -Be 'Default'
		}

		It "never uses more workers than files" {
			(Get-AdaptiveWorkerCount -ProcessorCount 22 -FileCount 3).Count | Should -Be 3
		}
	}

	Context "Exploring" {
		It "tries the upper neighbour first, then the lower one" {
			$first = Get-AdaptiveWorkerCount -Runs (New-Runs @(, @(12, 60))) -Recorded 1 -ProcessorCount 22 -FileCount 450
			$first.Count | Should -Be 15
			$first.Phase | Should -Be 'Explore'

			$second = Get-AdaptiveWorkerCount -Runs (New-Runs @(@(12, 60), @(15, 70))) -Recorded 2 -ProcessorCount 22 -FileCount 450
			$second.Count | Should -Be 9
			$second.Phase | Should -Be 'Explore'
		}

		It "keeps the neighbours inside [2, CPU]" {
			# best 12 on a 12-thread machine: the upper neighbour clamps to 12 (the best itself) and is dropped.
			(Get-AdaptiveWorkerCount -Runs (New-Runs @(, @(12, 60))) -Recorded 1 -ProcessorCount 12 -FileCount 450).Count | Should -Be 9
			# best 2 on a 2-thread machine: both neighbours clamp onto the best itself, so nothing is explored.
			(Get-AdaptiveWorkerCount -Runs (New-Runs @(, @(2, 60))) -Recorded 1 -ProcessorCount 2 -FileCount 450 -DefaultCap 2).Count | Should -Be 2
		}
	}

	Context "Two samples before a count can displace the best" {
		It "confirms a neighbour whose single sample beat the best before switching to it" {
			$runs = New-Runs @(@(12, 60), @(15, 50), @(9, 70))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 3 -ProcessorCount 22 -FileCount 450
			$result.Count | Should -Be 15
			$result.Phase | Should -Be 'Confirm'
			$result.Best | Should -Be 12
		}

		It "takes a second sample of the default before settling on it when no neighbour looked better" {
			$runs = New-Runs @(@(12, 60), @(15, 70), @(9, 80))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 3 -ProcessorCount 22 -FileCount 450
			$result.Count | Should -Be 12
			$result.Phase | Should -Be 'Settle'
		}

		It "switches the best once the neighbour has two samples with a lower median" {
			$runs = New-Runs @(@(12, 60), @(15, 50), @(9, 70), @(15, 52), @(12, 61))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 5 -ProcessorCount 22 -FileCount 450
			$result.Best | Should -Be 15
			# The new best's own neighbours (19 and 11) have never run: they are explored next.
			$result.Count | Should -Be 19
			$result.Phase | Should -Be 'Explore'
		}
	}

	Context "Settling" {
		It "uses the median, so one outlier run does not move the best" {
			$runs = New-Runs @(@(12, 60), @(15, 70), @(9, 80), @(12, 61), @(12, 200), @(12, 59), @(15, 68), @(9, 79))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 8 -ProcessorCount 22 -FileCount 450
			$result.Best | Should -Be 12
			$result.Count | Should -Be 12
			$result.Phase | Should -Be 'Settle'
		}

		It "re-checks a neighbour on every 20th recorded run" {
			$runs = New-Runs @(@(12, 60), @(15, 70), @(9, 80), @(12, 61), @(15, 69), @(9, 79))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 20 -ProcessorCount 22 -FileCount 450
			$result.Phase | Should -Be 'Recheck'
			$result.Count | Should -BeIn @(15, 9)

			(Get-AdaptiveWorkerCount -Runs $runs -Recorded 21 -ProcessorCount 22 -FileCount 450).Phase | Should -Be 'Settle'
		}

		It "alternates the re-checked neighbour" {
			$runs = New-Runs @(@(12, 60), @(15, 70), @(9, 80), @(12, 61), @(15, 69), @(9, 79))
			$at20 = (Get-AdaptiveWorkerCount -Runs $runs -Recorded 20 -ProcessorCount 22 -FileCount 450).Count
			$at40 = (Get-AdaptiveWorkerCount -Runs $runs -Recorded 40 -ProcessorCount 22 -FileCount 450).Count
			$at20 | Should -Not -Be $at40
		}
	}

	Context "Scoped runs" {
		It "never explores, and caps the workers by the work they would get" {
			$runs = New-Runs @(, @(12, 60))
			$result = Get-AdaptiveWorkerCount -Runs $runs -Recorded 1 -ProcessorCount 22 -FileCount 40 -TotalWeightMs 10000 -Scoped
			$result.Phase | Should -Be 'Scoped'
			$result.Count | Should -Be 3
		}

		It "uses the learned best for a large scoped run" {
			$runs = New-Runs @(@(12, 60), @(15, 50), @(9, 70), @(15, 52))
			(Get-AdaptiveWorkerCount -Runs $runs -Recorded 4 -ProcessorCount 22 -FileCount 300 -TotalWeightMs 400000 -Scoped).Count | Should -Be 15
		}

		It "gives a tiny scoped run a single worker" {
			(Get-AdaptiveWorkerCount -ProcessorCount 22 -FileCount 5 -TotalWeightMs 900 -Scoped).Count | Should -Be 1
		}
	}
}
