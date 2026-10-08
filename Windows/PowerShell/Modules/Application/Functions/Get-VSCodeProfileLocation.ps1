function Get-VSCodeProfileLocation {
	<#
	.SYNOPSIS
		Returns the folder of a VS Code profile, optionally registering the profile when VS Code does not know it yet.

	.DESCRIPTION
		VS Code keeps the Default profile directly in its user data folder (User\) and every
		other profile in User\profiles\<location>, where <location> is recorded next to the
		profile's name in the userDataProfiles list of User\globalStorage\storage.json. This
		function maps a profile name onto that folder:

		- "Default" (any case) is the user data folder itself.
		- Any other name is looked up in userDataProfiles (case-insensitive) and its folder
		  returned, whoever created it - VS Code, an import, or an earlier run of this function.
		- A name that is not registered returns $null, unless -Register is given: then the
		  profile is added to userDataProfiles with the location winux-<name> (lowercased,
		  anything but letters, digits and hyphens turned into hyphens) and its folder is
		  created, so a later `code --profile <name>` and the extension commands find it.

		Registration edits VS Code's own state file, which VS Code keeps in memory and writes
		back while it runs - an edit made then would be lost. So -Register refuses (an error,
		$null returned) while a Code process is running. Before the file is rewritten it is
		copied into the repository's backup sink (Backup-RepositoryItem, category
		VSCodeProfiles), and every other key in it is kept as read. A missing storage.json
		(VS Code never started) is created holding only the new profile.

	.PARAMETER Name
		The VS Code profile name, e.g. Default or Work.

	.PARAMETER UserData
		VS Code's user data folder. Defaults to Resolve-VSCodeProfilesConfig's UserData.

	.PARAMETER Register
		Registers the profile when VS Code does not know it yet, instead of returning $null.

	.EXAMPLE
		Get-VSCodeProfileLocation -Name Default
		Returns e.g. C:\Users\You\AppData\Roaming\Code\User.

	.EXAMPLE
		Get-VSCodeProfileLocation -Name Writing -Register
		Returns e.g. ...\Code\User\profiles\winux-writing, registering the profile first if needed.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[Parameter()]
		[string]$UserData,

		[Parameter()]
		[switch]$Register
	)

	if (-not $UserData) {
		$UserData = (Resolve-VSCodeProfilesConfig).UserData
	}

	if ($Name -eq 'Default') {
		return $UserData
	}

	$storagePath = Join-Path $UserData "globalStorage\storage.json"
	$state = [ordered]@{}
	if (Test-Path -LiteralPath $storagePath) {
		try {
			$state = Get-Content -LiteralPath $storagePath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
		}
		catch {
			Write-LogError "Could not read VS Code's profile list [$storagePath] => $($_.Exception.Message)"
			return $null
		}
		if ($null -eq $state) { $state = [ordered]@{} }
	}

	$profiles = @()
	if ($state.Contains('userDataProfiles')) {
		$profiles = @($state['userDataProfiles'])
	}
	foreach ($registered in $profiles) {
		if ($registered -is [System.Collections.IDictionary] -and [string]$registered['name'] -eq $Name -and $registered['location']) {
			return Join-Path (Join-Path $UserData "profiles") ([string]$registered['location'])
		}
	}

	if (-not $Register) {
		return $null
	}

	if (Get-Process -Name "Code" -ErrorAction SilentlyContinue) {
		Write-LogError "VS Code is running - close it so profile [$Name] can be registered (VS Code rewrites its profile list from memory while it runs)!"
		return $null
	}

	$location = "winux-" + ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-')
	$folder = Join-Path (Join-Path $UserData "profiles") $location

	try {
		if (Test-Path -LiteralPath $storagePath) {
			$backupDir = Backup-RepositoryItem -Path $storagePath -Category "VSCodeProfiles" -Key "storage.json"
			Write-LogDebug "Backed up VS Code's profile list => [$backupDir]"
		}

		$state['userDataProfiles'] = @($profiles) + @([ordered]@{ location = $location; name = $Name })
		Initialize-Directory (Split-Path -Parent $storagePath)
		$state | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $storagePath -Encoding utf8NoBOM
		Initialize-Directory $folder
		Write-LogSuccess "Registered VS Code profile [$Name] => [$folder]"
	}
	catch {
		Write-LogError "Could not register VS Code profile [$Name] => $($_.Exception.Message)"
		return $null
	}

	return $folder
}
