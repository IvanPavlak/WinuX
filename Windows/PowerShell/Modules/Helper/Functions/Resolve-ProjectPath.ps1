function Resolve-ProjectPath {
	<#
	.SYNOPSIS
		Resolve project path from configuration mappings.

	.DESCRIPTION
		Looks up project in Configuration.ProjectPathMappings and resolves local/remote paths

using dot-notation through MachineSpecificPaths. Supports both local and repository mappings.

	.PARAMETER ProjectName
		Project key from configuration (required).

	.PARAMETER PathKey
		Optional specific path key ('LocalPath', 'RemotePath'). Defaults to LocalPath.

	.PARAMETER ForRepository
		If specified, use RepositoryGroups instead of ProjectPathMappings.

	.EXAMPLE
		$path = Resolve-ProjectPath -ProjectName "MyApp" -PathKey "LocalPath"
		Write-Host "Project at: $path"

		$repoPath = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository
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
		foreach ($repositoryGroup in $Configuration.RepositoryGroups) {
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

		$githubBase = $Configuration.Universal.GitHub.Base
		$currentUrl = $Configuration.Universal.GitHub

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
		$mapping = $Configuration.ProjectTerminals | Where-Object { $_.Name -eq $ProjectName }
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
