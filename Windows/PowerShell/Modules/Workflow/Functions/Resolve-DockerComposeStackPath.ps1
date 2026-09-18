function Resolve-DockerComposeStackPath {
	<#
	.SYNOPSIS
		Resolves a Configuration.DockerComposeFiles stack name to its compose file path.

	.DESCRIPTION
		The single place that turns a DockerComposeFiles entry into a path: a rooted value
		is used as-is, a relative one is joined under MachineSpecificPaths.DockerDirectory.
		That split is what lets a stack live anywhere - a centralized compose file shipped
		in the repository's Docker directory, or a project's own compose file elsewhere on
		disk - and it used to exist twice, correctly in Start-Containers and not at all in
		Resolve-ProjectDockerCompose, which joined unconditionally and so mangled every
		absolute entry.

		Returns $null for a name that is not a configured stack, so callers can branch
		without reading DockerComposeFiles themselves. Existence is deliberately NOT
		checked: Start-Containers reports a missing file per stack and DockerWizard turns
		one into a failed start, and those two messages are not interchangeable.

	.PARAMETER Name
		Stack name to resolve - a key of Configuration.DockerComposeFiles.

	.EXAMPLE
		Resolve-DockerComposeStackPath -Name "PostgreSQL"

	.EXAMPLE
		$composeFile = Resolve-DockerComposeStackPath MyStack
		if (-not $composeFile) { Write-LogWarning "No such stack!" }
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name
	)

	# Defaulted because ContainsKey-free indexing below is still a method call on the
	# result: a setup that drops DockerComposeFiles entirely would throw on a null
	$composeStacks = Get-ConfigSetting -Path 'DockerComposeFiles' -Default @{}

	$configuredPath = $composeStacks[$Name]
	if ([string]::IsNullOrWhiteSpace($configuredPath)) {
		return $null
	}

	if ([System.IO.Path]::IsPathRooted($configuredPath)) {
		return $configuredPath
	}

	return Join-Path $MachineSpecificPaths.DockerDirectory $configuredPath
}
