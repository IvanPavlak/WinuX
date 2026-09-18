function Get-ConfigSetting {
	<#
	.SYNOPSIS
		Reads one value from the configuration by dotted path, with a default when it is absent.

	.DESCRIPTION
		The one seam every function reads Configuration.psd1 through. A dotted path names the
		value ('Universal.VisibleWindowExclusions'); the walk is null-safe at every segment, so
		the caller never writes the `if ($Configuration -and $Configuration.Universal -and
		$Configuration.Universal.X)` guard again, and a missing branch yields -Default instead
		of an error or an accidental $null.

		Missing versus empty: when any segment is absent, or the leaf is present but $null, the
		default is returned. Anything else comes back verbatim - $false, 0, an empty string, an
		empty array and an empty hashtable are all real configured values (several keys ship
		deliberately empty and off), so a caller that wants "empty means default" says so itself.

		Output is enumerated like every other command's: an array-valued key is emitted element by
		element, so wrap the call in @(...) when you need a collection - `@(Get-ConfigSetting -Path
		'Universal.VisibleWindowExclusions' -Default @())` is one element per configured name and
		zero for an empty list, never a nested array and never $null.

		The source defaults to $global:Configuration, the merged configuration Load-PathConfiguration
		built. Pass -Configuration to read another hashtable the same way: a function that takes
		its own `[hashtable]$Configuration` parameter forwards it, a test hands in a fake without
		touching global state, and the machine-specific paths hashtable resolves with the same
		walk ('Projects.MyProject.Root' against $global:MachineSpecificPaths).

		A key that itself contains a dot ('claude.ai' under a browser-group map) is reached by
		passing the segments separately: -Path 'BrowserGroups', 'claude.ai'. A single string is
		split on '.'; several strings are taken as literal segments.

	.PARAMETER Path
		The dotted path to read ('Section.Key'), or the individual segments as separate strings
		when a key contains a dot. Mandatory and never empty.

	.PARAMETER Default
		What to return when the path does not resolve. $null when omitted.

	.PARAMETER Configuration
		The hashtable (or object) to read from. Defaults to $global:Configuration.

	.OUTPUTS
		The configured value, verbatim, or -Default; a collection is enumerated into the pipeline.

	.EXAMPLE
		$exclusions = @(Get-ConfigSetting -Path 'Universal.VisibleWindowExclusions' -Default @())
		Reads the exclusion list; an unconfigured list is an empty array, never $null.

	.EXAMPLE
		$actions = @(Get-ConfigSetting -Path 'WorkspaceActions' -Default @())
		Get-OrderedEntry $actions $workspaceName
		Reads a whole ordered section; the empty default removes the guard around every consumer.

	.EXAMPLE
		Get-ConfigSetting -Path $entry.Solution -Configuration $global:MachineSpecificPaths
		Resolves a configuration value that names another value, against a different source.

	.EXAMPLE
		Get-ConfigSetting -Path 'Obsidian', 'Vaults', 'Notes.Work' -Default $null
		Reads a key whose name contains a dot by passing the segments separately.
	#>
	[CmdletBinding()]
	[OutputType([object])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string[]]$Path,

		[Parameter(Position = 1)]
		[AllowNull()]
		[object]$Default = $null,

		[Parameter()]
		[AllowNull()]
		[object]$Configuration = $global:Configuration
	)

	$segments = if ($Path.Count -eq 1) { @($Path[0] -split '\.') } else { @($Path) }
	if (@($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
		throw "Get-ConfigSetting: path [$($Path -join '.')] contains an empty segment."
	}

	# Plain assignments throughout: `$x = if (...) { $array }` runs the array through a
	# pipeline and unrolls it, turning a one-element list into a scalar and an empty one into
	# $null - exactly the distinctions this function exists to preserve.
	$current = $Configuration
	foreach ($segment in $segments) {
		if ($null -eq $current) { break }

		if ($current -is [System.Collections.IDictionary]) {
			if ($current.Contains($segment)) { $current = $current[$segment] } else { $current = $null }
			continue
		}

		$property = $current.PSObject.Properties[$segment]
		if ($null -ne $property) { $current = $property.Value } else { $current = $null }
	}

	if ($null -eq $current) { return $Default }

	# Output is enumerated exactly like every other cmdlet's: an array value is emitted element
	# by element, so a caller that needs a collection wraps the call in @(...) and gets one
	# element per configured item, zero for an empty list. Emitting the array as one wrapped
	# object instead would make @(...) nest it and a pipeline see a single item - which is how
	# an exclusion list stops excluding.
	return $current
}
