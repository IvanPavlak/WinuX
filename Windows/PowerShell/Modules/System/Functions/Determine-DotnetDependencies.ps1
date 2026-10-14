function Determine-DotnetDependencies {
	<#
	.SYNOPSIS
		Scans .NET projects and reports which .NET SDKs they need and which are missing.

	.DESCRIPTION
		Recursively scans a directory for `.csproj`, `.fsproj` and `.vbproj` files, parses their
		TargetFramework / TargetFrameworks, and lists the target frameworks found with a project
		count. It then lists the installed SDKs and runtimes (`dotnet --list-sdks` /
		`--list-runtimes`), compares the modern .NET versions the projects target against the
		installed SDKs, and for every missing SDK prints a `winget install
		Microsoft.DotNet.SDK.<major>` command and the matching WinGetApps.csv row.

		Excludes common non-source directories (node_modules, bin, obj, etc.) by default; an
		exclusion matches anywhere in a project's full path, not only a whole folder name.
		With `-ListProjects`, each target framework is followed by the projects that use it.

	.PARAMETER SearchPath
		Root directory to scan for .NET projects. Defaults to `MachineSpecificPaths.DotnetProjectsSearchPath`
		(only present when that key is placed under PathTemplates) or `$env:USERPROFILE\Development`
		if not configured.

	.PARAMETER ExcludePaths
		Array of directory names to exclude from scanning. Defaults to common build/cache folders.

	.PARAMETER ListProjects
		Also outputs the projects found, grouped under their target framework.

	.EXAMPLE
		Determine-DotnetDependencies
		Scans the configured .NET projects directory for dependencies.

	.EXAMPLE
		Determine-DotnetDependencies -SearchPath "C:\repos" -ListProjects
		Scans the repos folder and lists each project under its target framework.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$SearchPath = $null,

		[Parameter()]
		[string[]]$ExcludePaths = @("node_modules", "bin", "obj", ".git", ".vs", "packages"),

		[Parameter()]
		[switch]$ListProjects = $false
	)

	if ([string]::IsNullOrWhiteSpace($SearchPath)) {
		if ($global:MachineSpecificPaths -and $global:MachineSpecificPaths.DotnetProjectsSearchPath) {
			$SearchPath = $global:MachineSpecificPaths.DotnetProjectsSearchPath
		}
		else {
			$SearchPath = "$env:USERPROFILE\Development"
		}
	}

	if (-not (Test-Path $SearchPath)) {
		Write-LogError "Search path [$SearchPath] does not exist!"
		return
	}

	Write-LogTitle ".NET Dependency Analyzer"
	Write-LogStep "Search Path => [$SearchPath]"
	Write-LogWarning "Excluded => [$($ExcludePaths -join ', ')]"

	Write-LogStep " Finding .NET project files..."
	$projectExtensions = @("*.csproj", "*.fsproj", "*.vbproj")
	$allProjects = @()

	foreach ($ext in $projectExtensions) {
		$projects = Get-ChildItem -Path $SearchPath -Filter $ext -Recurse -ErrorAction SilentlyContinue |
			Where-Object {
				$excluded = $false
				foreach ($excludePath in $ExcludePaths) {
					if ($_.FullName -match [regex]::Escape($excludePath)) {
						$excluded = $true
						break
					}
				}
				-not $excluded
			}
		$allProjects += $projects
	}

	if ($allProjects.Count -eq 0) {
		Write-LogWarning "No .NET project files found in [$SearchPath]"
		return
	}

	Write-LogSuccess "Found $($allProjects.Count) project file(s)!"

	$targetFrameworks = @{}
	$projectsByFramework = @{}

	foreach ($project in $allProjects) {
		try {
			[xml]$projectXml = Get-Content $project.FullName -ErrorAction Stop

			$tfm = $projectXml.Project.PropertyGroup.TargetFramework
			$tfms = $projectXml.Project.PropertyGroup.TargetFrameworks

			$frameworks = @()
			if ($tfm) { $frameworks += $tfm }
			if ($tfms) { $frameworks += $tfms -split ';' }

			foreach ($framework in $frameworks) {
				$framework = $framework.Trim()
				if ([string]::IsNullOrWhiteSpace($framework)) { continue }

				if (-not $targetFrameworks.ContainsKey($framework)) {
					$targetFrameworks[$framework] = 0
					$projectsByFramework[$framework] = @()
				}
				$targetFrameworks[$framework]++
				$projectsByFramework[$framework] += $project.Name
			}
		}
		catch {
			Write-Warning "Failed to parse project => [$($project.FullName)]"
		}
	}

	Write-LogTitle "Target Frameworks Found" -BlankLineAfter

	foreach ($framework in ($targetFrameworks.Keys | Sort-Object)) {
		$count = $targetFrameworks[$framework]
		Write-LogStep "  $framework ($count project(s))" -NoLeadingNewline

		if ($ListProjects -eq $true) {
			$projects = $projectsByFramework[$framework] | Sort-Object
			foreach ($proj in $projects) {
				Write-LogStep "    - $proj" -NoLeadingNewline
			}
			Write-Host ""
		}
	}

	$requiredVersions = @()
	foreach ($tfm in $targetFrameworks.Keys) {
		$parsed = Get-DotnetVersionFromTFM -TFM $tfm
		if ($parsed -and $parsed.IsModern) {
			$requiredVersions += $parsed
		}
	}

	$requiredVersions = $requiredVersions |
		Sort-Object -Property Major, Minor -Unique |
		Sort-Object -Property Major, Minor

	Write-LogTitle "Installed .NET SDKs" -BlankLineAfter

	$installedSdks = @{}
	$sdkOutput = dotnet --list-sdks 2>&1

	if ($LASTEXITCODE -eq 0 -and $sdkOutput) {
		foreach ($line in $sdkOutput) {
			if ($line -match '^(\d+)\.(\d+)\.(\d+)') {
				$major = [int]$matches[1]
				$minor = [int]$matches[2]
				$version = "$major.$minor"

				if (-not $installedSdks.ContainsKey($version)) {
					$installedSdks[$version] = $line.Trim()
					Write-LogStep "  $line" -NoLeadingNewline
				}
			}
		}
	}

	if ($installedSdks.Count -eq 0) {
		Write-LogError "No .NET SDKs found!" -NoLeadingNewline
	}

	Write-LogTitle "Installed .NET Runtimes" -BlankLineAfter

	$installedRuntimes = @{}
	$runtimeOutput = dotnet --list-runtimes 2>&1

	if ($LASTEXITCODE -eq 0 -and $runtimeOutput) {
		foreach ($line in $runtimeOutput) {
			if ($line -match '^(\S+)\s+(\d+)\.(\d+)\.(\d+)') {
				$runtimeType = $matches[1]
				$major = [int]$matches[2]
				$minor = [int]$matches[3]
				$version = "$major.$minor"
				$key = "$runtimeType-$version"

				if (-not $installedRuntimes.ContainsKey($key)) {
					$installedRuntimes[$key] = $line.Trim()
					Write-LogStep "  $line" -NoLeadingNewline
				}
			}
		}
	}

	if ($installedRuntimes.Count -eq 0) {
		Write-LogError "No .NET Runtimes found!" -NoLeadingNewline
	}

	$missingVersions = @()
	$installedRequiredVersions = @()

	foreach ($required in $requiredVersions) {
		if ($installedSdks.ContainsKey($required.Version)) {
			$installedRequiredVersions += $required.Version
		}
		else {
			$missingVersions += $required.Version
		}
	}

	if ($installedRequiredVersions.Count -gt 0) {
		Write-Host -ForegroundColor Green "`n[Installed & Required]`n"
		foreach ($ver in $installedRequiredVersions) {
			Write-Host -ForegroundColor White "  .NET $ver SDK " -NoNewline
			Write-Host -ForegroundColor Green "[OK]"
		}
	}

	if ($missingVersions.Count -gt 0) {
		Write-Host -ForegroundColor Red "`n[Missing SDKs]`n"
		foreach ($ver in $missingVersions) {
			Write-Host -ForegroundColor Yellow "  .NET $ver SDK " -NoNewline
			Write-Host -ForegroundColor Red "[MISSING]"
		}
	}
	else {
		Write-LogSuccess "All required .NET SDKs are installed!"
	}

	if ($missingVersions.Count -gt 0) {

		Write-LogTitle "Installation Commands"
		Write-LogStep " WinGet"

		foreach ($ver in $missingVersions) {
			$majorVersion = $ver.Split('.')[0]
			$packageId = "Microsoft.DotNet.SDK.$majorVersion"
			Write-LogStep "  winget install $packageId" -NoLeadingNewline
		}

		Write-LogStep " WinGetApps.csv"
		foreach ($ver in $missingVersions) {
			$majorVersion = $ver.Split('.')[0]
			$packageId = "Microsoft.DotNet.SDK.$majorVersion"
			Write-LogStep "  $packageId,Latest,d,n,w,All" -NoLeadingNewline
		}
	}

	Write-LogSuccess "Analysis Complete!"
}
