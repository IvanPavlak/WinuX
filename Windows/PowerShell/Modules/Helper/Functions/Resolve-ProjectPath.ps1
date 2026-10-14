function Resolve-ProjectPath {
	<#
	.SYNOPSIS
		Resolve project path from configuration mappings.

	.DESCRIPTION
		Looks up the project in Configuration.ProjectTerminals (by Name) and walks its dot-notation
		BasePath through MachineSpecificPaths, returning the path for -PathKey or every path listed in
		the entry's Paths. With -ForRepository it looks the name up in Configuration.RepositoryGroups
		instead, resolves LocalPath through MachineSpecificPaths and UrlPath through
		Universal.GitHub, and returns a [PSCustomObject] with RepositoryUrl (Universal.GitHub.Base +
		the resolved UrlPath) and LocalPath. An unknown name, an unknown -PathKey, or a null path
		segment logs an error and stops.

	.PARAMETER ProjectName
		Project name (ProjectTerminals Name) or, with -ForRepository, repository name
		(RepositoryGroups entry Name). Required.

	.PARAMETER PathKey
		Optional single path key to return - one of the project's ProjectTerminals Paths entries
		(e.g. 'Api', 'Root'). When omitted, every path in Paths is returned. Ignored with
		-ForRepository.

	.PARAMETER ForRepository
		If specified, use RepositoryGroups instead of ProjectTerminals and return RepositoryUrl
		and LocalPath.

	.EXAMPLE
		$path = Resolve-ProjectPath -ProjectName "MyProject" -PathKey "Api"
		Write-Host "Project at: $path"

		$repo = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository
		# $repo.RepositoryUrl, $repo.LocalPath
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$ProjectName,

		[Parameter(Mandatory = $false)]
		[string]$PathKey,

		[Parameter(Mandatory = $false)]
		[switch]$ForRepository
	)

	if ($ForRepository) {
		$mapping = $null
		$repositoryGroups = @(Get-ConfigSetting -Path 'RepositoryGroups' -Default @())
		foreach ($repositoryGroup in $repositoryGroups) {
			$groupName = @($repositoryGroup.Keys)[0]
			foreach ($repository in $repositoryGroup[$groupName]) {
				if ($repository.Name -eq $ProjectName) {
					$mapping = $repository
					break
				}
			}
			if ($null -ne $mapping) { break }
		}

		if ($null -eq $mapping) {
			Write-LogError "Error: Repository [$ProjectName] not found in configuration!"
			break
		}

		$currentLocal = $MachineSpecificPaths
		foreach ($property in $mapping.LocalPath.Split('.')) {
			if ($null -eq $currentLocal) {
				Write-LogError "Error: Could not resolve LocalPath [$($mapping.LocalPath)] for repository [$ProjectName]. Path segment [$property] is null!"
				break
			}
			$currentLocal = $currentLocal.$property
		}

		$githubBase = Get-ConfigSetting -Path 'Universal.GitHub.Base'
		$currentUrl = Get-ConfigSetting -Path 'Universal.GitHub'

		$urlPathParts = $mapping.UrlPath.Split('.')

		while ($urlPathParts.Length -gt 0 -and $urlPathParts[0] -in @("Universal", "GitHub")) {
			$urlPathParts = $urlPathParts[1..($urlPathParts.Length - 1)]
		}

		foreach ($property in $urlPathParts) {
			if ($null -eq $currentUrl) {
				Write-LogError "Error: Could not resolve UrlPath [$($mapping.UrlPath)] for repository [$ProjectName]. Path segment [$property] is null!"
				break
			}
			$currentUrl = $currentUrl.$property
		}

		if ($null -eq $currentLocal) {
			Write-LogError "Error: Resolved LocalPath for repository [$ProjectName] is null!"
			break
		}
		if ($null -eq $currentUrl) {
			Write-LogError "Error: Resolved UrlPath for repository [$ProjectName] is null!"
			break
		}

		$fullUrl = $githubBase + $currentUrl

		return [PSCustomObject]@{
			RepositoryUrl = $fullUrl
			LocalPath     = $currentLocal
		}
	}
	else {
		$projectTerminals = @(Get-ConfigSetting -Path 'ProjectTerminals' -Default @())
		$mapping = $projectTerminals | Where-Object { $_.Name -eq $ProjectName }
		if (-not $mapping) {
			Write-LogError "Error: Project [$ProjectName] not found in configuration!" -BlankLineAfter
			break
		}

		$current = $MachineSpecificPaths
		foreach ($property in $mapping.BasePath.Split('.')) {
			if ($null -eq $current) {
				Write-LogError "Error: Could not resolve BasePath [$($mapping.BasePath)] for project [$ProjectName]. Path segment [$property] is null!" -BlankLineAfter
				break
			}
			$current = $current.$property
		}

		$baseObject = $current

		if ($null -eq $baseObject) {
			Write-LogError "Error: Resolved BasePath for project [$ProjectName] is null!" -BlankLineAfter
			break
		}

		if ($PathKey) {
			if ($mapping.Paths -notcontains $PathKey) {
				Write-LogError "Error: PathKey [$PathKey] not found for project [$ProjectName] in configuration!." -BlankLineAfter
				break
			}
			return $baseObject.$PathKey
		}
		else {
			$allPaths = @()
			foreach ($key in $mapping.Paths) {
				$allPaths += $baseObject.$key
			}
			return $allPaths
		}
	}
}
