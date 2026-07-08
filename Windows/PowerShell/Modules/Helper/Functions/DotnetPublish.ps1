function DotnetPublish {
	<#
    .SYNOPSIS
        Publish a .NET project using saved publish profiles.

    .DESCRIPTION
        Discovers solution file, finds all projects with publish profiles, and guides user through
        selection of project and profile. Executes `dotnet publish` with selected profile.
        Uses Find-Item to locate solution, Resolve-Selection for project/profile menus.

    .EXAMPLE
        DotnetPublish
        # Prompts for project with profiles, then profile selection, then publishes
    #>
	$solution = Find-Item -Pattern "*.sln" -SearchTarget "File" -MaxDownwardDepth 5 -MaxUpwardDepth 5 -SearchMessage "[Searching for a solution file]" -SuccessMessage "Found solution file [{0}]"

	if (-not $solution) {
		Write-LogError "Please ensure this method is ran within a repository that contains a .NET solution!"
		return
	}

	$solutionFile = $solution.Item
	$solutionPath = $solution.Path
	$solutionName = $solution.BaseName

	Write-LogStep "[Publishing $($solutionName.ToUpper())] from $solutionPath"

	Push-Location $solutionPath

	try {
		$projectsWithProfiles = @()

		$allProjects = Get-ChildItem -Path . -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue

		if ($allProjects.Count -eq 0) {
			Write-LogError "No .csproj files found in the solution directory!"
			return
		}

		Write-LogSuccess "Found $($allProjects.Count) project(s) in solution"

		foreach ($project in $allProjects) {
			$projectDir = Split-Path -Path $project.FullName -Parent
			$publishProfilesPath = Join-Path -Path $projectDir -ChildPath "Properties\PublishProfiles"

			if (Test-Path -Path $publishProfilesPath) {
				$publishProfiles = Get-ChildItem -Path $publishProfilesPath -Filter "*.pubxml" -ErrorAction SilentlyContinue
				if ($publishProfiles.Count -gt 0) {
					$projectsWithProfiles += [PSCustomObject]@{
						Name         = [System.IO.Path]::GetFileNameWithoutExtension($project.Name)
						Path         = $projectDir
						ProjectFile  = $project.FullName
						ProfilesPath = $publishProfilesPath
						Profiles     = $publishProfiles
					}
				}
			}
		}

		if ($projectsWithProfiles.Count -eq 0) {
			Write-LogError "No projects with publish profiles found in the solution!"
			return
		}

		$selectedProject = $null
		if ($projectsWithProfiles.Count -eq 1) {
			$selectedProject = $projectsWithProfiles[0]
			Write-LogSuccess "Found project with a publishing profile => [$($selectedProject.Name)]"
		}
		else {
			$projectOptions = $projectsWithProfiles | ForEach-Object {
				$profileCount = $_.Profiles.Count
				"$($_.Name) ($profileCount profile$(if($profileCount -ne 1){'s'}))"
			}

			$selectedProjectName = Resolve-Selection -OptionList $projectOptions -MenuTitle "[Available Projects with Publish Profiles]" -PromptMessage "Enter the number of the project to publish"

			if (-not $selectedProjectName) {
				Write-LogError "No project selected. Exiting..."
				return
			}

			$projectName = ($selectedProjectName -split ' \(')[0]
			$selectedProject = $projectsWithProfiles | Where-Object { $_.Name -eq $projectName }
		}

		$selectedProfile = $null
		if ($selectedProject.Profiles.Count -eq 1) {
			$selectedProfile = [System.IO.Path]::GetFileNameWithoutExtension($selectedProject.Profiles[0].Name)
			Write-LogSuccess "Using profile: $selectedProfile"
		}
		else {
			$profileOptions = $selectedProject.Profiles | ForEach-Object {
				[System.IO.Path]::GetFileNameWithoutExtension($_.Name)
			}

			$selectedProfile = Resolve-Selection -OptionList $profileOptions -MenuTitle "[Available Publish Profiles for $($selectedProject.Name)]" -PromptMessage "Enter the number of the publish profile to use"

			if (-not $selectedProfile) {
				Write-LogError "No profile selected. Exiting..."
				return
			}
		}

		$date = Get-Date -Format "yyyy_MM_dd"
		$outputFolderName = "$($selectedProject.Name)_${selectedProfile}_${date}"
		$outputPath = Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath $outputFolderName

		Push-Location $selectedProject.Path

		try {
			Write-LogSuccess "Publishing [$($selectedProject.Name)] with profile [$selectedProfile]..." -BlankLineAfter
			dotnet publish -p:PublishProfile=$selectedProfile -o "$outputPath"

			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess "Successfully published to $outputPath"

				$openFolder = Resolve-Selection -MenuTitle "[Open Output Folder]"

				if ($openFolder -eq "Yes") {
					Start-Process explorer.exe $outputPath
				}
			}
			else {
				Write-LogError "Publish failed with exit code $LASTEXITCODE"
			}
		}
		finally {
			Pop-Location
		}
	}
	finally {
		Pop-Location
	}
}
