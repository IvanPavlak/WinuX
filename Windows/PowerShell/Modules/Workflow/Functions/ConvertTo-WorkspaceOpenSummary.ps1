function ConvertTo-WorkspaceOpenSummary {
	<#
	.SYNOPSIS
		Turns the per-run rows of one experiment into one summary per variant, judged against a reference.

	.DESCRIPTION
		The arithmetic behind Measure-WorkspaceOpen's closing table and Get-WorkspaceOpenMeasurement's
		read-back, kept in one place so a table replayed from the file says the same thing the live
		run said. Takes the per-run rows of ONE session (warm-ups are dropped by their Measured flag)
		and returns, per variant in the order the variants first ran: the number of measured runs,
		Clean (ended Applied on the first attempt), Retries, NotApplied, median/min/max total, the
		median total over the clean runs only, and the medians of the phases the layout flags
		control (Layout, FancyZones, Wait, Position+Snap, Verify). Medians, not averages, so one
		40-second outlier cannot decide the experiment.

		Every variant is also compared with the reference - the first variant by default, which is
		Baseline in the one-factor-at-a-time set, or -Reference by name:
		  Effect  - the variant's clean median minus the reference's, in seconds (negative is
		            faster). Falls back to the plain median for a variant with no clean run.
		  Spread  - the range (max minus min) of the variant's own clean-run totals: how much two
		            opens of the SAME configuration differed.
		  Verdict - "Reference" for the reference itself; "Noise" when |Effect| is not larger than
		            half the larger of the two spreads, because a difference smaller than the
		            within-variant scatter is not evidence of anything; otherwise "Faster" or
		            "Slower". A coarse sanity check, not a significance test: with five runs per
		            variant it resolves effects of a few seconds, nothing finer.

		Read Clean, Retries and NotApplied before any seconds column: a variant that wins the median
		by needing a retry every third run has not won.

	.PARAMETER Row
		The per-run rows, as Measure-WorkspaceOpen produced them or Read-WorkspaceOpenMeasurement
		read them back. Rows with Measured = $false are ignored.

	.PARAMETER Reference
		The variant every other one is compared with. The first variant to run by default.

	.EXAMPLE
		Read-WorkspaceOpenMeasurement -Session 20260907-135804 | ConvertTo-WorkspaceOpenSummary | Format-Table -AutoSize

	.EXAMPLE
		ConvertTo-WorkspaceOpenSummary -Row $rows -Reference 'ApplyMethod=Hotkeys'
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Row,

		[Parameter()]
		[string]$Reference
	)

	begin {
		$collected = [System.Collections.Generic.List[object]]::new()
	}

	process {
		foreach ($item in @($Row)) { if ($null -ne $item) { $collected.Add($item) } }
	}

	end {
		$median = {
			param([double[]]$Values)
			$sorted = @($Values | Sort-Object)
			if ($sorted.Count -eq 0) { return 0.0 }
			$middle = [int][math]::Floor($sorted.Count / 2)
			$result = if ($sorted.Count % 2 -eq 1) { $sorted[$middle] } else { ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
			return [math]::Round([double]$result, 2)
		}

		$toBool = { param($Value) if ($Value -is [bool]) { $Value } else { ([string]$Value).Trim() -ieq 'True' } }
		$toDouble = { param($Value) $parsed = 0.0; if ($null -ne $Value -and [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { $parsed } else { 0.0 } }

		$measuredRows = @($collected | Where-Object { & $toBool $_.Measured })
		if ($measuredRows.Count -eq 0) { return @() }

		# Variants in the order they first ran, so the table reads like the plan did.
		$variantNames = [System.Collections.Generic.List[string]]::new()
		foreach ($item in @($measuredRows | Sort-Object -Property { [int](& $toDouble $_.Position) } -Stable)) {
			$name = [string]$item.Variant
			if (-not $variantNames.Contains($name)) { $variantNames.Add($name) }
		}

		$summaries = foreach ($name in $variantNames) {
			$items = @($measuredRows | Where-Object { [string]$_.Variant -eq $name })
			$clean = @($items | Where-Object { [string]$_.Outcome -eq 'Applied' -and [int](& $toDouble $_.Attempts) -eq 1 })
			$totals = [double[]]@($items | ForEach-Object { & $toDouble $_.TotalSeconds })
			$cleanTotals = [double[]]@($clean | ForEach-Object { & $toDouble $_.TotalSeconds })
			$spreadSource = if ($cleanTotals.Count -gt 0) { $cleanTotals } else { $totals }

			[PSCustomObject]@{
				Variant            = $name
				Runs               = $items.Count
				Clean              = $clean.Count
				Retries            = [int](@($items | ForEach-Object { [math]::Max(0, [int](& $toDouble $_.Attempts) - 1) }) | Measure-Object -Sum).Sum
				NotApplied         = @($items | Where-Object { [string]$_.Outcome -ne 'Applied' }).Count
				MedianTotal        = & $median $totals
				CleanMedianTotal   = & $median $cleanTotals
				MinTotal           = [math]::Round(($totals | Measure-Object -Minimum).Minimum, 2)
				MaxTotal           = [math]::Round(($totals | Measure-Object -Maximum).Maximum, 2)
				Effect             = 0.0
				Spread             = [math]::Round((($spreadSource | Measure-Object -Maximum).Maximum - ($spreadSource | Measure-Object -Minimum).Minimum), 2)
				Verdict            = ''
				MedianLayout       = & $median ([double[]]@($items | ForEach-Object { & $toDouble $_.LayoutSeconds }))
				MedianFancyZones   = & $median ([double[]]@($items | ForEach-Object { & $toDouble $_.FancyZonesSeconds }))
				MedianWait         = & $median ([double[]]@($items | ForEach-Object { & $toDouble $_.WaitSeconds }))
				MedianPositionSnap = & $median ([double[]]@($items | ForEach-Object { (& $toDouble $_.PositionSeconds) + (& $toDouble $_.SnapSeconds) }))
				MedianVerify       = & $median ([double[]]@($items | ForEach-Object { & $toDouble $_.VerifySeconds }))
				Settings           = [string]$items[0].Settings
			}
		}
		$summaries = @($summaries)

		# The comparison: every variant against the reference, on the clean medians when both have
		# one. A difference inside the within-variant scatter is noise, whatever its sign.
		$referenceName = if (-not [string]::IsNullOrWhiteSpace($Reference) -and $variantNames.Contains($Reference)) { $Reference } else { $variantNames[0] }
		$referenceSummary = @($summaries | Where-Object { $_.Variant -eq $referenceName })[0]
		$comparable = { param($Summary) if ($Summary.Clean -gt 0) { $Summary.CleanMedianTotal } else { $Summary.MedianTotal } }
		$referenceValue = & $comparable $referenceSummary

		foreach ($summary in $summaries) {
			if ($summary.Variant -eq $referenceName) {
				$summary.Verdict = 'Reference'
				continue
			}
			$effect = [math]::Round(((& $comparable $summary) - $referenceValue), 2)
			$summary.Effect = $effect
			$noiseFloor = [math]::Max($summary.Spread, $referenceSummary.Spread) / 2
			$summary.Verdict = if ([math]::Abs($effect) -le $noiseFloor) { 'Noise' } elseif ($effect -lt 0) { 'Faster' } else { 'Slower' }
		}

		return $summaries
	}
}
