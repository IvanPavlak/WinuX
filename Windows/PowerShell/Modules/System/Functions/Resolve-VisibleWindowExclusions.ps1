function Resolve-VisibleWindowExclusions {
	<#
	.SYNOPSIS
		Returns the process names of Universal.VisibleWindowExclusions that apply to this machine.

	.DESCRIPTION
		The one reader of Configuration.Universal.VisibleWindowExclusions, the process names a
		teardown leaves alone: Terminate-AllProcessesWithVisibleWindows never force-kills them,
		Report-KillAllSurvivors does not report them, and Get-WorkspaceOpenDelta never adopts them.

		An entry is either a process name, which applies on every machine, or a hashtable
		@{ Name = "<process>"; Machine = "PC/Work" } that applies only on the machine types its
		Machine scope names (Test-MachineTypeScope, so an unknown type is reported and never
		matches). A hashtable without a Machine key applies everywhere; one without a Name is
		skipped. Blank names are dropped and duplicates collapse, case-insensitively.

	.PARAMETER MachineType
		Machine type the Machine scopes are tested against. Defaults to $global:MachineType.

	.OUTPUTS
		[string[]] The process names, in configuration order. Empty when nothing applies.

	.EXAMPLE
		Resolve-VisibleWindowExclusions
		With VisibleWindowExclusions = @("Rainmeter", @{ Name = "MyAgentApp"; Machine = "PC" }),
		returns Rainmeter and MyAgentApp on a PC, and Rainmeter alone everywhere else.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter()]
		[string]$MachineType = $global:MachineType
	)

	$names = [System.Collections.Generic.List[string]]::new()
	$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($entry in @(Get-ConfigSetting -Path 'Universal.VisibleWindowExclusions' -Default @())) {
		if ($null -eq $entry) { continue }
		$name = [string]$entry
		if ($entry -is [System.Collections.IDictionary]) {
			$name = [string]$entry.Name
			if ([string]::IsNullOrWhiteSpace($name)) { continue }
			if ($entry.Machine -and -not (Test-MachineTypeScope -Scope ([string]$entry.Machine) -MachineType $MachineType -Context "Universal.VisibleWindowExclusions [$name]")) { continue }
		}
		$name = $name.Trim()
		if ($name -and $seen.Add($name)) { $names.Add($name) }
	}
	return [string[]]$names.ToArray()
}
