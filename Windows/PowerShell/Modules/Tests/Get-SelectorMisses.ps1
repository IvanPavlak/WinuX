function Get-SelectorMisses {
	<#
	.SYNOPSIS
		The failing test files a -Changed selection did not include: the selector's misses.

	.DESCRIPTION
		The audit that turns "the selector is conservative" from an assumption into a measurement.
		Locally, a full run compares its failing files with what the last Run-Tests -Changed selected;
		in CI, the full run compares them with what -Changed would have selected for the PR's diff.
		Every failing file outside the selection is a miss - a rule in Get-TestImpact that should have
		picked it. A selection that fell back to the full suite cannot miss anything.

		Pure. Paths are compared case-insensitively, as given (pass both lists in the same form).

	.PARAMETER FailedFiles
		The files with at least one failing test.

	.PARAMETER SelectedFiles
		The files the selection picked.

	.PARAMETER FullSuite
		The selection was the full suite.

	.OUTPUTS
		The missed files, one per pipeline object, in the order given.

	.EXAMPLE
		Get-SelectorMisses -FailedFiles $failed -SelectedFiles $lastSelection.files
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$FailedFiles = @(),

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$SelectedFiles = @(),

		[Parameter()]
		[switch]$FullSuite
	)

	if ($FullSuite) { return }
	$picked = [System.Collections.Generic.HashSet[string]]::new([string[]]@($SelectedFiles | Where-Object { $_ }), [StringComparer]::OrdinalIgnoreCase)
	@($FailedFiles | Where-Object { $_ -and -not $picked.Contains($_) })
}
