function Collect-BrowserUrls {
	<#
	.SYNOPSIS
		Recursively collect all URLs from nested browser group hashtables.

	.DESCRIPTION
		Flattens hierarchical browser group structures (from Configuration.BrowserGroups) into flat URL arrays.
		Handles nested hashtables with Name/Url pairs and tracks opened subgroup names.

	.PARAMETER Value
		The browser group structure (array or hashtable) to process.

	.PARAMETER Depth
		Recursion depth counter (internal use, default 0).

	.EXAMPLE
		$urls = Collect-BrowserUrls -Value $Configuration.BrowserGroups.SocialMedia
		Write-Host "Found $($urls.Urls.Count) URLs"
	#>
	param(
		[Parameter(Mandatory)]
		$Value,

		[Parameter(Mandatory = $false)]
		[int]$Depth = 0
	)

	$urlsToOpen = @()
	$openedSubgroups = @()

	if ($Value -is [Array]) {
		foreach ($item in $Value) {
			if ($item -is [hashtable]) {
				if ($item.ContainsKey('Name') -and $item.ContainsKey('Url')) {
					$urlsToOpen += $item.Url
					if ($Depth -eq 0) {
						$openedSubgroups += $item.Name
					}
				}
				else {
					foreach ($key in $item.Keys) {
						if ($Depth -eq 0) {
							$openedSubgroups += $key
						}
						$result = Collect-BrowserUrls -Value $item[$key] -Depth ($Depth + 1)
						$urlsToOpen += $result.Urls
						if ($Depth -eq 0) {
							$openedSubgroups += $result.Subgroups
						}
					}
				}
			}
			elseif ($item -is [string]) {
				$urlsToOpen += $item
			}
		}
	}
	elseif ($Value -is [hashtable]) {
		if ($Value.ContainsKey('Url')) {
			$urlsToOpen += $Value.Url
		}
	}
	elseif ($Value -is [string]) {
		$urlsToOpen += $Value
	}

	return @{
		Urls      = $urlsToOpen
		Subgroups = $openedSubgroups
	}
}
