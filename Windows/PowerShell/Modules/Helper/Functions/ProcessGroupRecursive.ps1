function ProcessGroupRecursive {
	<#
	.SYNOPSIS
		Recursively processes nested group hierarchies for menu display.

	.DESCRIPTION
		Internal function used by Resolve-Selection to flatten and navigate hierarchical group structures.
		Detects group structure types (mixed/nested/flat/string array), generates indexed display items,
		and builds a lookup map for rapid name→selection resolution.

		NOTE: This is an internal helper. Call via Resolve-Selection with `-GroupsConfig`.

	.PARAMETER GroupValue
		The current group to process (hashtable, array, or string).

	.PARAMETER IndexPath
		The dot-notation path (e.g., "1.2.3") representing the item's position in the hierarchy.

	.PARAMETER DisplayItems
		Array list accumulating menu display lines. Passed by reference and modified.

	.PARAMETER LookupMap
		Hashtable mapping friendly names to selection objects. Passed by reference and modified.

	.PARAMETER PathNames
		Array list of names representing the current path in the hierarchy.

	.PARAMETER Depth
		Current nesting depth (0 at root). Used to control indentation in display.
	#>
	param(
		[Parameter(Mandatory)]
		$GroupValue,

		[Parameter(Mandatory)]
		[string]$IndexPath,

		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[System.Collections.ArrayList]$DisplayItems,

		[Parameter(Mandatory)]
		[hashtable]$LookupMap,

		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[System.Collections.ArrayList]$PathNames,

		[Parameter(Mandatory = $false)]
		[int]$Depth = 0
	)

	$currentName = $PathNames[$PathNames.Count - 1]

	$hasNameUrl = $false
	$hasNestedHashtable = $false
	$hasString = $false

	if ($GroupValue -is [Array] -and $GroupValue.Count -gt 0) {
		foreach ($element in $GroupValue) {
			if ($element -is [hashtable]) {
				if ($element.ContainsKey('Name') -and $element.ContainsKey('Url')) {
					$hasNameUrl = $true
				}
				else {
					$hasNestedHashtable = $true
				}
			}
			elseif ($element -is [string]) {
				$hasString = $true
			}
		}
	}

	$isMixedStructure = ($hasNameUrl -and $hasNestedHashtable)
	$isNameUrlStructure = $hasNameUrl -and -not $hasNestedHashtable
	$isNestedHashtableStructure = $hasNestedHashtable -and -not $hasNameUrl
	$isStringArray = $hasString -and -not $hasNameUrl -and -not $hasNestedHashtable

	$DisplayItems.Add([PSCustomObject]@{
			IndexPath = $IndexPath
			Text      = $currentName
			Depth     = $Depth
		}) | Out-Null

	$structureType = if ($isStringArray) { "StringArray" }
	elseif ($isNameUrlStructure) { "NameUrlArray" }
	elseif ($isNestedHashtableStructure) { "NestedHashtables" }
	elseif ($isMixedStructure) { "MixedArray" }
	else { "Unknown" }

	$lookupEntry = [PSCustomObject]@{
		GroupName      = $PathNames[0]
		SubgroupName   = if ($PathNames.Count -gt 1) { $PathNames[1] } else { $null }
		IsParent       = -not $isStringArray
		Path           = $IndexPath
		Depth          = $Depth
		PathNames      = $PathNames.ToArray()
		StructureType  = $structureType
		DirectChildren = [System.Collections.ArrayList]::new()
	}

	$LookupMap[$IndexPath] = $lookupEntry
	$LookupMap[$currentName] = $lookupEntry

	if ($isNameUrlStructure -or $isMixedStructure) {
		$subIndex = 1
		foreach ($item in $GroupValue) {
			if ($item -is [hashtable] -and $item.ContainsKey('Name') -and $item.ContainsKey('Url')) {
				$itemName = $item.Name
				$childIndexPath = "$IndexPath.$subIndex"
				$childPathNames = [System.Collections.ArrayList]::new($PathNames)
				$childPathNames.Add($itemName) | Out-Null

				$DisplayItems.Add([PSCustomObject]@{
						IndexPath = $childIndexPath
						Text      = $itemName
						Depth     = $Depth + 1
					}) | Out-Null

				$childLookupEntry = [PSCustomObject]@{
					GroupName      = $PathNames[0]
					SubgroupName   = if ($childPathNames.Count -gt 1) { $childPathNames[1] } else { $null }
					IsParent       = $false
					Path           = $childIndexPath
					Depth          = $Depth + 1
					PathNames      = $childPathNames.ToArray()
					StructureType  = "Leaf"
					DirectChildren = [System.Collections.ArrayList]::new()
				}

				$LookupMap[$childIndexPath] = $childLookupEntry
				$LookupMap[$itemName] = $childLookupEntry
				$lookupEntry.DirectChildren.Add($childIndexPath) | Out-Null

				$subIndex++
			}
			elseif ($item -is [hashtable]) {
				$subGroupName = @($item.Keys)[0]
				$subGroupValue = $item[$subGroupName]
				$childIndexPath = "$IndexPath.$subIndex"
				$childPathNames = [System.Collections.ArrayList]::new($PathNames)
				$childPathNames.Add($subGroupName) | Out-Null

				ProcessGroupRecursive `
					-GroupValue $subGroupValue `
					-IndexPath $childIndexPath `
					-DisplayItems $DisplayItems `
					-LookupMap $LookupMap `
					-PathNames $childPathNames `
					-Depth ($Depth + 1)

				$lookupEntry.DirectChildren.Add($childIndexPath) | Out-Null

				$subIndex++
			}
		}
	}
	elseif ($isNestedHashtableStructure) {
		$subIndex = 1
		foreach ($subItem in $GroupValue) {
			$subGroupName = @($subItem.Keys)[0]
			$subGroupValue = $subItem[$subGroupName]
			$childIndexPath = "$IndexPath.$subIndex"
			$childPathNames = [System.Collections.ArrayList]::new($PathNames)
			$childPathNames.Add($subGroupName) | Out-Null

			ProcessGroupRecursive `
				-GroupValue $subGroupValue `
				-IndexPath $childIndexPath `
				-DisplayItems $DisplayItems `
				-LookupMap $LookupMap `
				-PathNames $childPathNames `
				-Depth ($Depth + 1)

			$lookupEntry.DirectChildren.Add($childIndexPath) | Out-Null

			$subIndex++
		}
	}
	elseif ($GroupValue -is [Array] -and $GroupValue.Count -gt 0 -and $GroupValue[0] -is [string]) {
	}
}
