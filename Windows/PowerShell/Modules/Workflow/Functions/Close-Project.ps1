function Close-Project {
	<#
	.SYNOPSIS
		Closes all project-specific resources opened by Open-Project.

	.DESCRIPTION
		Closes Visual Studio windows, VSCode windows, terminal tabs, and browser tabs/windows
		associated with the specified project(s). Enables fast switching between projects by
		closing only project-specific resources while keeping workspace-level applications running.

		Terminal tabs are closed automatically by cycling through Windows Terminal tabs and
		sending Ctrl+W to tabs matching the project name pattern (e.g., "AnotherProject.Api", "AnotherProject.Ui").

		Browser tabs are closed by detecting tabs with the project name in the title. Additionally,
		if a swagger mapping exists, it also closes tabs with "Swagger UI" in the title (when
		backend is running) or "Problem loading page" (when backend is not running).

	.PARAMETER Project
		Array of project names to close. Projects must be defined in $Configuration.Projects.
		If not specified, displays an interactive selection menu.

	.EXAMPLE
		Close-Project -Project "AnotherProject"
		Closes all AnotherProject project resources (Visual Studio, VSCode, terminals, swagger).

	.EXAMPLE
		Close-Project
		Displays interactive menu to select project(s) to close.

	.EXAMPLE
		Close-Project -Project "ExampleProject", "AnotherProject"
		Closes resources for both ExampleProject and AnotherProject projects.

	.NOTES
		This function is designed to work in conjunction with Open-Project for fast project switching.
		It only closes project-specific resources, leaving workspace-level applications (like Obsidian,
		DBeaver, WhatsApp, etc.) running.

		Successfully closes:
		- Visual Studio windows (by solution name)
		- VSCode windows (by folder name)
		- Terminal tabs (by project name pattern using Ctrl+W)
		- Browser tabs (by project name, "Swagger UI", or "Problem loading page" in titles)
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Project
	)

	# Define Win32 API functions for window closing
	if (-not ([System.Management.Automation.PSTypeName]'CloseProjectWin32').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;
			public class CloseProjectWin32 {
				[DllImport("user32.dll")]
				public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

				public const uint WM_CLOSE = 0x0010;
			}
"@
	}

	$resolveParams = @{
		InputObject              = $Project
		OptionList               = $Configuration.Projects
		MenuTitle                = "[Available projects to close]"
		PromptMessage            = "Enter project(s) to close or press Enter to cancel"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}

	$projects = Resolve-Selection @resolveParams

	if ($null -eq $projects -or $projects.Count -eq 0) {
		Write-LogWarning "No projects selected to close!"
		return
	}

	foreach ($projectName in $projects) {
		Write-LogTitle "Closing $projectName Project Resources"

		$projectActions = $Configuration.ProjectActions[$projectName]

		if (-not $projectActions) {
			Write-LogWarning "No actions configured for project [$projectName], skipping..."
			continue
		}

		$closedAny = $false

		# Close Visual Studio windows
		$vsActions = $projectActions | Where-Object { $_.Action -eq "Open-VisualStudio" }
		foreach ($vsAction in $vsActions) {
			$solutionParam = $vsAction.Parameters.Solution
			if ($solutionParam) {
				# Replace {ProjectName} placeholder
				$solutionName = $solutionParam -replace '\{ProjectName\}', $projectName
				$resolvedSolutionPath = $null
				$solutionEntry = $Configuration.VisualStudioSolutions | Where-Object { $_.Name -eq $solutionName }
				if ($solutionEntry) {
					$resolvedSolutionPath = Resolve-ConfigPathValue -PathExpression $solutionEntry.Solution
				}

				$solutionTitleCandidates = Get-WindowTitleCandidates -Names @(
					$solutionName,
					$resolvedSolutionPath
				)

				Write-LogDebug " Looking for Visual Studio with solution [$solutionName]..."
				Write-LogDebug "  Solution title candidates => $($solutionTitleCandidates -join ', ')" -Style Step

				$vsWindows = Get-WindowHandle -ProcessName "devenv" -ErrorAction SilentlyContinue |
					Where-Object { Test-WindowTitleCandidates -WindowTitle $_.Title -Candidates $solutionTitleCandidates }

				if ($vsWindows) {
					foreach ($window in $vsWindows) {
						Write-LogDebug "  Closing Visual Studio window => [$($window.Title)]" -Style Step
						[CloseProjectWin32]::PostMessage($window.Handle, [CloseProjectWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
						$closedAny = $true
					}
					Write-LogSuccess "Closed Visual Studio with solution [$solutionName]"
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "No Visual Studio windows found for [$solutionName]" -Style Warning
				}
			}
		}

		# Close VSCode windows
		$vscodeActions = $projectActions | Where-Object { $_.Action -eq "Open-VSCode" }
		foreach ($vscodeAction in $vscodeActions) {
			$folderParam = $vscodeAction.Parameters.Folder
			if ($folderParam) {
				# Replace {ProjectName} placeholder
				$folderName = $folderParam -replace '\{ProjectName\}', $projectName
				$resolvedFolderPath = $null
				$vscodeEntry = $Configuration.VSCodeProjects | Where-Object { $_.Name -eq $folderName }
				if ($vscodeEntry) {
					$resolvedFolderPath = Resolve-ConfigPathValue -PathExpression $vscodeEntry.Path
				}

				$folderTitleCandidates = Get-WindowTitleCandidates -Names @(
					$folderName,
					$resolvedFolderPath
				)

				Write-LogDebug " Looking for VSCode with folder [$folderName]..."
				Write-LogDebug "  VSCode title candidates => $($folderTitleCandidates -join ', ')" -Style Step

				$vscodeWindows = Get-WindowHandle -ProcessName "Code" -ErrorAction SilentlyContinue |
					Where-Object { Test-WindowTitleCandidates -WindowTitle $_.Title -Candidates $folderTitleCandidates }

				if ($vscodeWindows) {
					foreach ($window in $vscodeWindows) {
						Write-LogDebug "  Closing VSCode window => [$($window.Title)]" -Style Step
						[CloseProjectWin32]::PostMessage($window.Handle, [CloseProjectWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
						$closedAny = $true
					}
					Write-LogSuccess "Closed VSCode with folder [$folderName]"
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "No VSCode windows found for [$folderName]" -Style Warning
				}
			}
		}

		# Close terminal tabs for this project
		# Terminal tabs are named "ProjectName.PathKey" (e.g., "AnotherProject.Api", "AnotherProject.Ui")
		$hasTerminalActions = $projectActions | Where-Object {
			$_.Action -eq "Open-ProjectTerminals-Or-RunProject" -or
			$_.Action -eq "Open-ProjectTerminals" -or
			$_.Action -eq "Run-Project"
		}

		if ($hasTerminalActions) {
			$closedCount = Close-ProjectTerminals -ProjectName $projectName
			if ($closedCount -gt 0) {
				$closedAny = $true
			}
		}

		# Close browser tabs/windows for this project
		# This includes Swagger UI tabs and any other tabs with the project name
		Write-LogDebug " Looking for browser tabs for project [$projectName]..."

		# Get the default browser
		$browser = $Configuration.Universal.DefaultBrowser
		$browserConfig = $Configuration.Universal.Browsers[$browser]

		Write-LogDebug "  Default browser => [$browser]" -Style Step

		if ($browserConfig) {
			$processName = switch ($browser) {
				"Chrome" { "chrome" }
				"Firefox" { "firefox" }
				"Edge" { "msedge" }
				"Tor" { "firefox" }
				default { $browser.ToLower() }
			}

			Write-LogDebug "  Process name to search => [$processName]" -Style Step

			# Build patterns to match - always include project name
			$patterns = @("(?i)$([regex]::Escape($projectName))")

			# Check if there's a swagger group matching this project (case-insensitive)
			$urlGroups = $Configuration.BrowserGroups
			$swaggerParentGroup = $urlGroups | Where-Object { $_.Keys -contains "Swagger" }
			$swaggerGroup = if ($swaggerParentGroup) {
				($swaggerParentGroup["Swagger"] | Where-Object { $_.Name -ieq $projectName }).Name
			}
			if ($swaggerGroup) {
				Write-LogDebug "  Found swagger group => [$swaggerGroup]"

				# Get the swagger URLs
				$swaggerUrls = $null
				if ($swaggerParentGroup) {
					$swaggerItems = $swaggerParentGroup["Swagger"]
					$swaggerItem = $swaggerItems | Where-Object { $_.Name -eq $swaggerGroup }

					if ($swaggerItem) {
						$swaggerUrls = @($swaggerItem.Url)
					}
				}

				if ($swaggerUrls) {
					Write-LogDebug "  Swagger URLs => $($swaggerUrls -join ', ')" -Style Step

					# Check if any URLs are localhost (for swagger detection)
					$hasLocalhostUrls = $swaggerUrls | Where-Object {
						try {
							$uri = [System.Uri]$_
							$uri.Host -eq "localhost" -or $uri.Host -eq "127.0.0.1"
						}
						catch {
							$false
						}
					}

					if (Test-LogVerbose) {
						$localhostStatus = if ($hasLocalhostUrls) { "YES" } else { "NO" }
						Write-LogDebug "Has localhost URLs => [$localhostStatus]" -Style Step
					}

					# Add swagger-specific patterns
					$patterns += "(?i)swagger ui"
					if ($hasLocalhostUrls) {
						$patterns += "(?i)problem loading page"
					}
				}
			}

			Write-LogDebug "  Patterns to match => $($patterns -join ' | ')" -Style Step

			# Close browser tabs matching the patterns
			$closedCount = Close-BrowserTabsByPattern -ProcessName $processName -TitlePatterns $patterns

			if ($closedCount -gt 0) {
				Write-LogSuccess "Closed $closedCount browser tab(s) for [$projectName]"
				$closedAny = $true
			}
			elseif (Test-LogVerbose) {
				Write-LogDebug "No browser tabs found for [$projectName]" -Style Warning
			}
		}
		elseif (Test-LogVerbose) {
			Write-LogDebug "Browser config not found for [$browser]" -Style Warning
		}

		if ($closedAny) {
			Write-LogSuccess "Successfully closed [$projectName] project resources!"
		}
		else {
			Write-LogWarning "No resources found to close for [$projectName]"
		}
	}

	Write-LogSuccess "Project closed completely!"

	Focus-TerminalTab
}
