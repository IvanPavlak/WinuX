function Resolve-MonitorLabel {
	<#
	.SYNOPSIS
		Converts between a monitor's ordinal position and its standardized label.

	.DESCRIPTION
		Single source of truth for the Primary / Secondary / Monitor3 / Monitor4 / ... label
		scheme that Get-MonitorSpecs emits and that layout files, Apply-FancyZones and
		Resolve-TargetMonitor all key on. Converts in both directions, one per parameter set:

		- -Index <int>    0-based ordinal => label. Ordinal 0 is "Primary", 1 is "Secondary",
		                  and every ordinal past that is "Monitor<Index + 1>" - so ordinal 2
		                  is "Monitor3".
		- -Label <string> label => 0-based ordinal, i.e. the sort key that orders monitors
		                  Primary, Secondary, Monitor3, Monitor4, ... Unrecognized labels
		                  return [int]::MaxValue so they sort last.

		Both directions live here because the ordering used to be duplicated as a three-way
		Primary=0 / Secondary=1 / everything-else=2 mapping in Update-LayoutSectionHeaders and
		Visualize-Layouts. Monitor3, Monitor4 and Monitor5 all tied at 2 under that mapping and
		fell back to input order, which made generated section headers and visualizations look
		randomly ordered on a setup with more than two displays.

		"Monitor1" and "Monitor2" resolve to ordinals 0 and 1 - the same slots as "Primary" and
		"Secondary" - so a hand-written layout file using them still sorts sensibly.
		Get-MonitorSpecs itself never emits those two forms.

		The scheme is POSITIONAL, not a hardware identity. Get-MonitorSpecs assigns the ordinals:
		the primary display always takes ordinal 0, and the remaining displays are ordered by
		physical position (left to right, then top to bottom). A label therefore follows the
		physical arrangement rather than a specific panel - rearranging displays in Windows
		display settings reassigns them.

	.PARAMETER Index
		0-based monitor ordinal to convert into a label. Must be 0 or greater.

	.PARAMETER Label
		Monitor label to convert into its 0-based ordinal. Matched case-insensitively and
		trimmed. Empty, whitespace-only and unrecognized labels return [int]::MaxValue.

	.OUTPUTS
		System.String when called with -Index (the label).
		System.Int32 when called with -Label (the 0-based ordinal).

	.EXAMPLE
		Resolve-MonitorLabel -Index 0
		# => Primary

	.EXAMPLE
		Resolve-MonitorLabel -Index 2
		# => Monitor3

	.EXAMPLE
		Resolve-MonitorLabel -Label "Monitor3"
		# => 2

	.EXAMPLE
		# Sort layout entries into Primary, Secondary, Monitor3, ... order.
		$entries | Sort-Object { Resolve-MonitorLabel -Label $_.Monitor }
	#>
	[CmdletBinding(DefaultParameterSetName = 'FromIndex')]
	param (
		[Parameter(Mandatory = $true, ParameterSetName = 'FromIndex', Position = 0)]
		[int]$Index,

		[Parameter(Mandatory = $true, ParameterSetName = 'FromLabel', Position = 0)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]$Label
	)

	if ($PSCmdlet.ParameterSetName -eq 'FromIndex') {
		if ($Index -lt 0) {
			Write-Error "Monitor ordinal must be 0 or greater (got [$Index])."
			return $null
		}

		switch ($Index) {
			0 { return 'Primary' }
			1 { return 'Secondary' }
			default { return "Monitor$($Index + 1)" }
		}
	}

	if ([string]::IsNullOrWhiteSpace($Label)) {
		return [int]::MaxValue
	}

	$trimmedLabel = $Label.Trim()

	if ($trimmedLabel -ieq 'Primary') { return 0 }
	if ($trimmedLabel -ieq 'Secondary') { return 1 }

	# MonitorN is 1-based in the label and 0-based as an ordinal, so Monitor3 sorts at 2.
	if ($trimmedLabel -match '^Monitor(?<Ordinal>\d+)$') {
		$labelNumber = [int]$Matches['Ordinal']
		if ($labelNumber -ge 1) {
			return $labelNumber - 1
		}
	}

	return [int]::MaxValue
}
