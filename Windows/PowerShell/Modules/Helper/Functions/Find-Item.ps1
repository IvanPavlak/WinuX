function Find-Item {
	<#
    .SYNOPSIS
        Searches for files or directories recursively with bidirectional search capability.

    .DESCRIPTION
        A robust search function that can find files or directories by pattern, searching both
        downward (into subdirectories) and upward (through parent directories). Supports multiple
        matches with interactive selection and flexible filtering options.

    .PARAMETER Pattern
        File or directory pattern to search for (e.g., "*.csproj", "*.sln", "*Domain*")

    .PARAMETER StartPath
        Starting path for the search. Defaults to current directory.

    .PARAMETER MaxUpwardDepth
        Maximum number of parent directories to traverse upward. Default is 5.

    .PARAMETER MaxDownwardDepth
        Maximum depth to search downward recursively. Default is 5.

    .PARAMETER SearchTarget
        What to search for: "File", "Directory", or "Both". Default is "File".

    .PARAMETER NameFilter
        Additional filter to apply to item names (e.g., "Domain" for directories containing "Domain")

    .PARAMETER SelectFirst
        If specified, automatically selects the first match without prompting.

    .PARAMETER MenuTitle
        Custom title for the selection menu when multiple items are found.

    .PARAMETER PromptMessage
        Custom prompt message for the selection menu.

    .PARAMETER SearchMessage
        Custom message to display when starting the search.

    .PARAMETER SuccessMessage
        Custom format string for success message. Use {0} for item name and {1} for path.

    .PARAMETER ErrorMessage
        Custom error message when no items are found.

    .PARAMETER ReturnFullObject
        If specified, returns the full FileInfo/DirectoryInfo object instead of a custom object.

    .EXAMPLE
        Find-Item -Pattern "*.sln"
        Searches for solution files.

    .EXAMPLE
        Find-Item -Pattern "*.csproj" -NameFilter "Domain"
        Searches for .csproj files in directories containing "Domain".

    .EXAMPLE
        Find-Item -Pattern "*" -SearchTarget "Directory" -NameFilter "Database" -MaxDownwardDepth 3
        Searches for directories containing "Database" up to 3 levels deep.
    #>

	param(
		[Parameter(Mandatory = $true)]
		[string]$Pattern,

		[string]$StartPath = (Get-Location).Path,

		[int]$MaxUpwardDepth = 5,

		[int]$MaxDownwardDepth = 5,

		[ValidateSet("File", "Directory", "Both")]
		[string]$SearchTarget = "File",

		[string]$NameFilter = "",

		[switch]$SelectFirst,

		[string]$MenuTitle = "",

		[string]$PromptMessage = "Select an item",

		[string]$SearchMessage = "",

		[string]$SuccessMessage = "",

		[string]$ErrorMessage = "",

		[switch]$ReturnFullObject
	)

	$currentPath = $StartPath
	$levelsTraversed = 0
	$foundItems = @()

	if ([string]::IsNullOrWhiteSpace($SearchMessage)) {
		if ([string]::IsNullOrWhiteSpace($NameFilter)) {
			Write-LogTitle "Searching for items matching [$Pattern]" -BlankLineAfter
		}
		else {
			Write-LogTitle "Searching for [$NameFilter] matching [$Pattern]" -BlankLineAfter
		}
	}
	else {
		Write-LogStep "$SearchMessage" -BlankLineAfter
	}

	do {
		Write-LogStep " Searching in [$currentPath]" -NoLeadingNewline

		$searchParams = @{
			Path        = $currentPath
			Filter      = $Pattern
			ErrorAction = 'SilentlyContinue'
		}

		if ($SearchTarget -eq "File") {
			$searchParams.File = $true
		}
		elseif ($SearchTarget -eq "Directory") {
			$searchParams.Directory = $true
		}

		if ($MaxDownwardDepth -gt 0) {
			$searchParams.Recurse = $true
			$searchParams.Depth = $MaxDownwardDepth
		}

		$items = Get-ChildItem @searchParams

		if (-not [string]::IsNullOrWhiteSpace($NameFilter)) {
			if ($SearchTarget -eq "Directory") {
				$items = $items | Where-Object { $_.Name -like "*$NameFilter*" }
			}
			else {
				$items = $items | Where-Object { $_.Directory.Name -like "*$NameFilter*" }
			}
		}

		foreach ($item in $items) {
			$foundItems += $item
		}

		if ($foundItems.Count -gt 0) {
			break
		}

		$parentPath = Split-Path -Path $currentPath -Parent

		if (-not $parentPath -or $parentPath -eq $currentPath) {
			break
		}

		$currentPath = $parentPath
		$levelsTraversed++

	} while ($levelsTraversed -lt $MaxUpwardDepth)

	if ($foundItems.Count -eq 0) {
		if ([string]::IsNullOrWhiteSpace($ErrorMessage)) {
			$targetType = if ($SearchTarget -eq "Both") { "items" } else { $SearchTarget.ToLower() + "s" }
			$filterInfo = if ([string]::IsNullOrWhiteSpace($NameFilter)) { "" } else { " matching [$NameFilter]" }
			$ErrorMessage = "No $targetType matching [$Pattern]$filterInfo found within [$levelsTraversed] parent directories!"
		}
		Write-LogError "$ErrorMessage"
		return $null
	}
	elseif ($foundItems.Count -eq 1 -or $SelectFirst) {
		$selectedItem = $foundItems[0]

		if ([string]::IsNullOrWhiteSpace($SuccessMessage)) {
			Write-LogSuccess "Found [$($selectedItem.Name)] at [$($selectedItem.FullName)]"
		}
		else {
			$message = $SuccessMessage -f $selectedItem.Name, $selectedItem.FullName
			Write-LogSuccess "$message"
		}

		if ($ReturnFullObject) {
			return $selectedItem
		}

		return [PSCustomObject]@{
			Name      = $selectedItem.Name
			FullName  = $selectedItem.FullName
			Path      = if ($SearchTarget -eq "Directory") { $selectedItem.FullName } else { $selectedItem.DirectoryName }
			BaseName  = $selectedItem.BaseName
			Extension = $selectedItem.Extension
			Item      = $selectedItem
		}
	}
	else {
		if ([string]::IsNullOrWhiteSpace($MenuTitle)) {
			# TODO: Directories will never be Directorys
			#$targetType = if ($SearchTarget -eq "Both") { "items" } else { $SearchTarget.ToLower() + "s" }
			#$MenuTitle = "[Found $($foundItems.Count) $targetType]"
			$MenuTitle = "[Found $($foundItems.Count)]"
		}

		$itemOptions = $foundItems | ForEach-Object {
			$relativePath = $_.FullName.Replace("$StartPath\", "")
			if ($SearchTarget -eq "Directory") {
				$relativePath
			}
			else {
				"$($_.Name) - $relativePath"
			}
		}

		$selectedOption = Resolve-Selection -OptionList $itemOptions -MenuTitle $MenuTitle -PromptMessage $PromptMessage

		if (-not $selectedOption) {
			Write-LogError "No item selected. Exiting..."
			return $null
		}

		$selectedItem = $null
		if ($SearchTarget -eq "Directory") {
			$selectedItem = $foundItems | Where-Object { $_.FullName -like "*$selectedOption" } | Select-Object -First 1
		}
		else {
			$selectedName = ($selectedOption -split ' - ')[0]
			$selectedItem = $foundItems | Where-Object { $_.Name -eq $selectedName } | Select-Object -First 1
		}

		if ($selectedItem) {
			Write-LogSuccess "Selected [$($selectedItem.Name)] at [$($selectedItem.FullName)]"

			if ($ReturnFullObject) {
				return $selectedItem
			}

			return [PSCustomObject]@{
				Name      = $selectedItem.Name
				FullName  = $selectedItem.FullName
				Path      = if ($SearchTarget -eq "Directory") { $selectedItem.FullName } else { $selectedItem.DirectoryName }
				BaseName  = $selectedItem.BaseName
				Extension = $selectedItem.Extension
				Item      = $selectedItem
			}
		}
	}

	return $null
}
