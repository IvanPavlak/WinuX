function Expand-WorkspaceTemplates {
	<#
	.SYNOPSIS
		Expands every templated WorkspaceActions entry of a configuration in place.

	.DESCRIPTION
		Runs once per configuration load, right after Configuration.local.psd1 is merged
		(Load-PathConfiguration). Every templated entry (@{ Name = @{ Template = "..." } }) is
		replaced by the ordinary action list Resolve-WorkspaceTemplate stamps out of its
		WorkspaceTemplates entry, and every plain entry gets its {Workspace} token substituted, so
		every reader of WorkspaceActions - Open-Workspace, Close-Workspace, Measure-WorkspaceOpen,
		Open-Obsidian, Get-OrderedEntry and the rest - sees plain action lists and needs to know
		nothing about templates.

		The raw templated definitions are kept under the runtime key WorkspaceTemplateEntries
		(an ordered map of workspace name => definition), and the problems found under
		WorkspaceTemplateErrors. Open-Workspace expands from WorkspaceTemplateEntries again when the
		command line sets a template variable (w MyProject -Repository OtherGroup), and
		Test-ConfigurationSchema reports WorkspaceTemplateErrors instead of expanding everything a
		second time. Both keys are written by this function only; they are not configuration
		settings.

		A templated entry that cannot be expanded (unknown template, missing variable, ambiguous
		override, unknown placeholder, variable cycle, bad Before / After anchor) is reported
		through Write-LogError, naming the workspace and the problem, and resolves to an empty
		action list. It stays in the workspace menu; opening it repeats the error and opens
		nothing.

	.PARAMETER Configuration
		The configuration hashtable to expand in place. Defaults to $global:Configuration.

	.PARAMETER Quiet
		Suppresses the error output (Load-PathConfiguration -Quiet); the problems are still
		returned and Test-ConfigurationSchema reports them.

	.OUTPUTS
		[pscustomobject] with Expanded (the templated workspace names that expanded cleanly) and
		Errors (one message per problem).

	.EXAMPLE
		Expand-WorkspaceTemplates -Configuration $global:Configuration
		# WorkspaceActions now holds plain action lists only.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[switch]$Quiet
	)

	$summary = [PSCustomObject]@{
		Expanded = @()
		Errors   = @()
	}
	if ($null -eq $Configuration) { return $summary }

	$templates = $Configuration['WorkspaceTemplates']
	$section = $Configuration['WorkspaceActions']
	$sources = [ordered]@{}
	$expanded = [System.Collections.Generic.List[string]]::new()
	$errors = [System.Collections.Generic.List[string]]::new()

	# Expands one entry and writes the result back into the dictionary that holds it.
	$expandInto = {
		param([System.Collections.IDictionary]$Holder, $Key)
		$definition = $Holder[$Key]
		$workspaceName = [string]$Key
		$resolution = Resolve-WorkspaceTemplate -Name $workspaceName -Definition $definition -Templates $templates
		if ($resolution.IsTemplated) {
			$sources[$workspaceName] = $definition
			if ($resolution.Errors.Count -gt 0) {
				foreach ($message in $resolution.Errors) { $errors.Add($message) }
			}
			else {
				$expanded.Add($workspaceName)
			}
			$Holder[$Key] = $resolution.Actions
			return
		}
		if ($resolution.Changed) { $Holder[$Key] = $resolution.Actions }
	}

	if ($section -is [System.Collections.IDictionary]) {
		foreach ($key in @($section.Keys)) { & $expandInto $section $key }
	}
	elseif ($null -ne $section) {
		foreach ($item in @($section)) {
			if (-not ($item -is [System.Collections.IDictionary])) { continue }
			foreach ($key in @($item.Keys)) { & $expandInto $item $key }
		}
	}

	# A configuration this function already expanded has no templated values left; running it
	# again must not forget the raw definitions and errors recorded the first time.
	$alreadyExpanded = $sources.Count -eq 0 -and $Configuration['WorkspaceTemplateEntries'] -is [System.Collections.IDictionary] -and $Configuration['WorkspaceTemplateEntries'].Count -gt 0
	if ($alreadyExpanded) {
		return $summary
	}
	$Configuration['WorkspaceTemplateEntries'] = $sources
	$Configuration['WorkspaceTemplateErrors'] = $errors.ToArray()

	if (-not $Quiet) {
		foreach ($message in $errors) {
			Write-LogError "$message - the workspace opens nothing until this is fixed"
		}
	}

	$summary.Expanded = $expanded.ToArray()
	$summary.Errors = $errors.ToArray()
	return $summary
}
