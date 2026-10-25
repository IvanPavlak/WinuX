function List-Skills {
	<#
	.SYNOPSIS
		Deprecated since 1.6.0 (removed in 2.0.0): runs List-AiArtifacts -Kind Skills.

	.DESCRIPTION
		List-Skills listed the skills under AiSkills.Root and checked their links in the
		AiSkills.Harnesses folders. Skills are one kind of AI artifact now: List-AiArtifacts lists
		every kind (-Kind Skills for the skills) and -ListDiscrepancies checks every destination
		of the harnesses AiArtifacts.Deploy names. Migration: call List-AiArtifacts -Kind Skills,
		with -Name in place of -Skill.

		Warns once per session, then forwards: -Source as -Source, -Skill as -Name,
		-ListDiscrepancies and -Quiet as they are. See docs/ai/artifacts.md.

	.PARAMETER Source
		Filter to specific sources. Pass an empty value (-Source @()) to pick from the menu.

	.PARAMETER Skill
		Filter to specific skill names, forwarded as -Name.

	.PARAMETER ListDiscrepancies
		Compare the skills on disk against what is deployed into the skills destinations.

	.PARAMETER Quiet
		Suppress the success banner when -ListDiscrepancies finds nothing wrong.

	.EXAMPLE
		List-Skills -Source own
		Warns, then runs List-AiArtifacts -Kind Skills -Source own.
	#>
	[CmdletBinding(DefaultParameterSetName = 'ListAll')]
	param (
		[Parameter(Mandatory = $false, ParameterSetName = 'BySource')]
		[string[]]$Source,

		[Parameter(Mandatory = $false, ParameterSetName = 'BySkill')]
		[string[]]$Skill,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$ListDiscrepancies,

		[Parameter(Mandatory = $false, ParameterSetName = 'DiscrepancyCheck')]
		[switch]$Quiet
	)

	if (-not $script:AiDeprecationWarnings) { $script:AiDeprecationWarnings = @{} }
	if (-not $script:AiDeprecationWarnings.ContainsKey('List-Skills')) {
		$script:AiDeprecationWarnings['List-Skills'] = $true
		Write-LogWarning "List-Skills is deprecated since 1.6.0 and removed in 2.0.0 - use List-AiArtifacts -Kind Skills (docs/ai/artifacts.md)!"
	}

	$forward = @{ Kind = 'Skills' }
	switch ($PSCmdlet.ParameterSetName) {
		'BySource' { $forward.Source = @($Source) }
		'BySkill' { $forward.Name = @($Skill) }
		'DiscrepancyCheck' {
			$forward.ListDiscrepancies = $true
			$forward.Quiet = $Quiet
		}
	}
	List-AiArtifacts @forward
}
