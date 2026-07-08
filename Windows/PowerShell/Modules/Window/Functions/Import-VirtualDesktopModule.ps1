function Import-VirtualDesktopModule {
	<#
	.SYNOPSIS
		Lazily imports the VirtualDesktop module with caching.

	.DESCRIPTION
		Checks if VirtualDesktop module is available and imports it only once.
		Returns $true if module is loaded and ready, $false otherwise.
		Uses module-scoped state to avoid repeated Get-Module calls.

	.PARAMETER Silent
		Suppresses warning messages if the module is not found or fails to load.

	.OUTPUTS
		Boolean indicating whether the VirtualDesktop module is loaded and ready.

	.EXAMPLE
		if (Import-VirtualDesktopModule) {
			# Use VirtualDesktop cmdlets
		}

	.EXAMPLE
		$hasModule = Import-VirtualDesktopModule -Silent
		Checks for module availability without displaying warnings.
	#>
	param(
		[Parameter()]
		[switch]$Silent
	)

	# If already loaded, return immediately
	if ($script:VirtualDesktopState.Loaded) {
		return $true
	}

	# Check availability only once per session
	if (-not $script:VirtualDesktopState.Checked) {
		$script:VirtualDesktopState.Available = $null -ne (Get-Module -ListAvailable -Name VirtualDesktop)
		$script:VirtualDesktopState.Checked = $true
	}

	if (-not $script:VirtualDesktopState.Available) {
		if (-not $Silent) {
			Write-Warning "VirtualDesktop module not found. Install with: Install-Module -Name VirtualDesktop -Scope CurrentUser"
		}
		return $false
	}

	# Check if already loaded by another source
	if (Get-Module -Name VirtualDesktop) {
		$script:VirtualDesktopState.Loaded = $true
		return $true
	}

	# Import the module
	try {
		Import-Module VirtualDesktop -ErrorAction Stop -WarningAction SilentlyContinue
		$script:VirtualDesktopState.Loaded = $true
		return $true
	}
	catch {
		if (-not $Silent) {
			Write-Warning "Failed to load VirtualDesktop module: $_"
		}
		return $false
	}
}
