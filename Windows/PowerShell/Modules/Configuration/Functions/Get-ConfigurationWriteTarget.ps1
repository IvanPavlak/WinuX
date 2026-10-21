function Get-ConfigurationWriteTarget {
	<#
	.SYNOPSIS
		Resolves the configuration file an Add-* writer edits, and its lines ready for the edit.
	.DESCRIPTION
		The Add-* functions write into Configuration.local.psd1 by default: the base
		Configuration.psd1 is upstream's tracked file, and a fork's own entries belong in its
		local override. This returns that file's path and lines, prepared so the writer can insert
		its entry into the section it targets:

		- A section named in -CopySection that the local file lacks is copied whole from the base
		  first. Those sections are arrays, and an array in the local file replaces the base array
		  wholesale at load, so a local list that held only the new entry would hide every base
		  entry. The copy starts as the base's complete list.
		- A dotted -HashtableSection (Parent.Child, e.g. PathTemplates.SymbolicLinks) the local
		  file lacks is added as an empty hashtable, inside Parent when the local file has it.
		  Hashtables deep-merge, so the base entries stay without being copied.
		- A local file that does not exist yet starts as an empty @{ } hashtable.

		Nothing is written here; the writer saves the lines through Save-ConfigurationFile.

		-ConfigurationFilePath names the file explicitly (tests use it) and -Base selects the base
		Configuration.psd1; both return that file's lines untouched, the behavior before the
		local default.

	.PARAMETER ConfigurationFilePath
		An explicit file to edit. Returned as it is, with no section copied in.
	.PARAMETER Base
		Edit the base Configuration.psd1 instead of Configuration.local.psd1 (engine work).
	.PARAMETER CopySection
		Top-level array sections the writer inserts into, copied from the base when missing.
	.PARAMETER HashtableSection
		Dotted Parent.Child hashtable sections the writer inserts into, added empty when missing.
	.PARAMETER BaseConfigurationPath
		The base Configuration.psd1. Defaults to the module's own; the local file is its sibling.
	.OUTPUTS
		[pscustomobject] with Path, FileName, Lines, IsLocal, Created and CopiedSections, or $null
		(the reason logged) when the file cannot be resolved.
	.EXAMPLE
		$target = Get-ConfigurationWriteTarget -CopySection 'BrowserGroups'
		Returns Configuration.local.psd1 with a BrowserGroups section in its lines.
	.EXAMPLE
		$target = Get-ConfigurationWriteTarget -HashtableSection 'PathTemplates.SymbolicLinks'
		Returns Configuration.local.psd1 with a (possibly empty) SymbolicLinks block in PathTemplates.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[string]$ConfigurationFilePath,

		[switch]$Base,

		[string[]]$CopySection = @(),

		[string[]]$HashtableSection = @(),

		[string]$BaseConfigurationPath = $script:ConfigurationPath
	)

	if ($ConfigurationFilePath -or $Base) {
		$path = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $BaseConfigurationPath }
		if (-not $path -or -not (Test-Path $path)) {
			Write-LogError "Error: Configuration file not found at '$path'!"
			return $null
		}
		return [pscustomobject]@{
			Path           = $path
			FileName       = Split-Path -Path $path -Leaf
			Lines          = @(Get-Content -Path $path)
			IsLocal        = $false
			Created        = $false
			CopiedSections = @()
		}
	}

	if (-not $BaseConfigurationPath -or -not (Test-Path $BaseConfigurationPath)) {
		Write-LogError "Error: Configuration file not found at '$BaseConfigurationPath'!"
		return $null
	}

	$path = Join-Path -Path (Split-Path -Path $BaseConfigurationPath -Parent) -ChildPath "Configuration.local.psd1"
	$created = -not (Test-Path $path)
	$lines = [System.Collections.Generic.List[string]]::new()
	if ($created) {
		$lines.Add("@{")
		$lines.Add("}")
	}
	else {
		foreach ($line in @(Get-Content -Path $path)) { $lines.Add([string]$line) }
	}

	$baseLines = $null
	$copiedSections = [System.Collections.Generic.List[string]]::new()

	foreach ($sectionName in $CopySection) {
		if (Find-ConfigurationSection -Lines $lines -SectionName $sectionName) { continue }

		if ($null -eq $baseLines) { $baseLines = @(Get-Content -Path $BaseConfigurationPath) }
		$baseSection = Find-ConfigurationSection -Lines $baseLines -SectionName $sectionName
		# Not in the base either: the writer reports the missing section itself.
		if (-not $baseSection) { continue }

		$closeIndex = $lines.FindLastIndex([Predicate[string]] { param($l) $l -match '^\}\s*$' })
		if ($closeIndex -lt 0) {
			Write-LogError "Error: '$path' has no closing '}' of its top-level hashtable!"
			return $null
		}

		$block = @(
			""
			"`t# Copied whole from Configuration.psd1: an array here replaces the base array at load,"
			"`t# so this list is the complete $sectionName."
		) + @($baseLines[$baseSection.StartIndex..$baseSection.EndIndex])
		$lines.InsertRange($closeIndex, [string[]]$block)
		$copiedSections.Add($sectionName)
	}

	foreach ($dottedName in $HashtableSection) {
		$parentName, $childName = $dottedName.Split('.', 2)
		$parent = Find-ConfigurationSection -Lines $lines -SectionName $parentName
		$child = if ($parent) {
			Find-ConfigurationSection -Lines @($lines.GetRange($parent.StartIndex, $parent.EndIndex - $parent.StartIndex + 1)) -SectionName $childName
		}
		if ($child) { continue }

		if ($parent -and $parent.BracketType -eq '{') {
			$lines.InsertRange($parent.EndIndex, [string[]]@(
					"$($parent.Indent)`t$childName = @{"
					"$($parent.Indent)`t}"
				))
		}
		else {
			$closeIndex = $lines.FindLastIndex([Predicate[string]] { param($l) $l -match '^\}\s*$' })
			if ($closeIndex -lt 0) {
				Write-LogError "Error: '$path' has no closing '}' of its top-level hashtable!"
				return $null
			}
			$lines.InsertRange($closeIndex, [string[]]@(
					""
					"`t$parentName = @{"
					"`t`t$childName = @{"
					"`t`t}"
					"`t}"
				))
		}
		$copiedSections.Add($dottedName)
	}

	return [pscustomobject]@{
		Path           = $path
		FileName       = Split-Path -Path $path -Leaf
		Lines          = @($lines)
		IsLocal        = $true
		Created        = $created
		CopiedSections = @($copiedSections)
	}
}
