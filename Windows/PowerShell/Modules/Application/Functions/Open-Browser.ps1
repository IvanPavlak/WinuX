function Open-Browser {
	<#
	.SYNOPSIS
		Opens a browser with URL groups from the configuration, or performs a Google search.

	.DESCRIPTION
		The primary browser launcher for the entire system. Reads URL groups from
		`BrowserGroups` in Configuration.psd1 and opens them in the configured browser.

		Idempotency: before opening any group, checks whether the group's URLs are already
		open by matching browser window titles against URL keywords. Already-open groups
		are skipped unless `-Override` is set.

		When `-Search` is provided, performs a Google search directly without showing the
		group menu. When `-NoMenu` is set, opens the browser bare (or opens the specified
		number of browser instances) without group selection.

		The default browser is read from `Configuration.Universal.DefaultBrowser`.
		Browser definitions (exe path, private arg, new-window arg) come from
		`Configuration.Universal.Browsers`.

	.PARAMETER Groups
		One or more group names to open, using dot-notation for nested groups
		(e.g. "Work.Backend"). Omit to show the interactive group selection menu.

	.PARAMETER Private
		Opens the browser in private/incognito mode. Cannot be combined with group opening.

	.PARAMETER NoMenu
		Skips the group selection menu and opens the browser directly (no URLs loaded).

	.PARAMETER Search
		Performs a Google search with the provided query string. Opens directly without menu.

	.PARAMETER Browser
		Browser to use. Defaults to `Configuration.Universal.DefaultBrowser`.
		Valid values correspond to keys in `Configuration.Universal.Browsers` (e.g. "Firefox", "Chrome", "Tor").

	.PARAMETER Override
		Bypasses idempotency - opens groups even if they appear to already be open.

	.PARAMETER Instances
		Target number of browser windows to have open when used with `-NoMenu`.
		Counts existing windows and opens only the deficit. 0 means open exactly one.

	.EXAMPLE
		Open-Browser
		Shows the browser group selection menu.

	.EXAMPLE
		Open-Browser Work Backend
		Opens the Work and Backend browser groups.

	.EXAMPLE
		Open-Browser -Search "powershell splatting"
		Searches Google for "powershell splatting" in the default browser.

	.EXAMPLE
		Open-Browser -NoMenu -Browser "Firefox" -Instances 2
		Ensures 2 Firefox windows are open.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
		[string[]]$Groups,

		[switch]$Private,

		[switch]$NoMenu,

		[Parameter()]
		[string]$Search,

		[Parameter()]
		[string]$Browser,

		[Parameter()]
		[switch]$Override,

		[Parameter()]
		[int]$Instances = 0
	)

	if (-not $PSBoundParameters.ContainsKey('Browser') -or [string]::IsNullOrWhiteSpace($Browser)) {
		$Browser = $Configuration.Universal.DefaultBrowser
	}

	$browserConfig = $Configuration.Universal.Browsers[$Browser]

	if (-not $browserConfig) {
		Write-LogError "Error: Browser [$Browser] not found in configuration! Available browsers => [$($Configuration.Universal.Browsers.Keys -join ', ')]"
		return
	}

	$browserPath = $browserConfig.Exe
	$privateArg = $browserConfig.PrivateArg
	$newWindowArg = $browserConfig.NewWindowArg
	$urlGroups = $Configuration.BrowserGroups
	$isTor = $Browser -eq "Tor"

	Try {
		if ($PSBoundParameters.ContainsKey('Search') -and -not [string]::IsNullOrWhiteSpace($Search)) {
			Write-LogStep "Searching [$Search]$(if ($Private -and -not $isTor) { " in private mode" })..."
			$encodedSearch = [System.Web.HttpUtility]::UrlEncode($Search)
			$searchUrl = "https://www.google.com/search?q=$encodedSearch"

			if ($isTor) {
				Start-Process $browserPath -ArgumentList $searchUrl -NoNewWindow -ErrorAction Stop
			}
			elseif ($Private) {
				Start-Process $browserPath -ArgumentList $privateArg, $searchUrl -NoNewWindow -ErrorAction Stop
			}
			else {
				Start-Process $browserPath -ArgumentList $newWindowArg, $searchUrl -NoNewWindow -ErrorAction Stop
			}

			Write-LogSuccess "$Browser opened with search for [$Search]$(if ($Private -and -not $isTor) { " in private mode" })!"
			return
		}

		if ($NoMenu) {
			Write-LogStep "Opening $Browser..."

			$browserProcessName = switch ($Browser) {
				"Chrome" { "chrome" }
				"Firefox" { "firefox" }
				"Edge" { "msedge" }
				"Tor" { "firefox" }
				default { $Browser.ToLower() }
			}

			$existingWindows = @()
			if ($Instances -gt 0) {
				$existingWindows = @(Get-WindowHandle -ProcessName $browserProcessName -ErrorAction SilentlyContinue)
				Write-LogDebug " [Open-Browser] Found $($existingWindows.Count) existing [$browserProcessName] window(s) before Instances launch"
			}

			$targetInstances = if ($Instances -gt 0) { $Instances } else { 1 }
			$toOpen = [Math]::Max(0, $targetInstances - $existingWindows.Count)

			if ($toOpen -eq 0) {
				Write-LogWarning "[$Browser] already has $($existingWindows.Count)/$targetInstances instance(s) open!"
				return
			}

			for ($inst = 0; $inst -lt $toOpen; $inst++) {
				if ($isTor) {
					Start-Process $browserPath -NoNewWindow -ErrorAction Stop
				}
				elseif ($Private) {
					Start-Process $browserPath -ArgumentList $privateArg -NoNewWindow -ErrorAction Stop
				}
				else {
					Start-Process $browserPath -NoNewWindow -ErrorAction Stop
				}
			}

			Write-LogSuccess "$Browser opened$(if ($Private -and -not $isTor) { " in private mode" })! ($toOpen instance(s) launched)"
			return
		}

		$validGroups = $Groups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

		$resolveParams = @{
			GroupsConfig             = $urlGroups
			MenuTitle                = "[Available $Browser groups]"
			PromptMessage            = "Enter group(s) by number or name, or press Enter to open default $Browser"
			AllowEmptyPromptResponse = $true
			AllowMultipleSelections  = $true
		}

		if ($PSBoundParameters.ContainsKey('Groups') -and $validGroups.Count -gt 0) {
			$resolveParams['InputObject'] = $validGroups
		}

		$resolvedGroups = Resolve-Selection @resolveParams

		if (-not $resolvedGroups) {
			Write-LogStep "Opening $Browser..."
			if ($isTor) {
				Start-Process $browserPath -NoNewWindow -ErrorAction Stop
			}
			elseif ($Private) {
				Start-Process $browserPath -ArgumentList $privateArg -NoNewWindow -ErrorAction Stop
			}
			else {
				Start-Process $browserPath -NoNewWindow -ErrorAction Stop
			}
		}
		else {
			if ($Private -and -not $isTor) {
				Write-LogWarning "Groups cannot be opened in private mode. Continuing with normal mode..."
				$Private = $false
			}

			Write-LogStep "Opening $Browser group(s)..."

			# Cache browser windows once for all duplicate checks (avoids re-enumerating per group)
			$cachedWindows = $null
			if (-not $Override -or $Instances -gt 0) {
				$browserProcessName = switch ($Browser) {
					"Chrome" { "chrome" }
					"Firefox" { "firefox" }
					"Edge" { "msedge" }
					"Tor" { "firefox" }
					default { $Browser.ToLower() }
				}
				$cachedWindows = @(Get-WindowHandle -ProcessName $browserProcessName -ErrorAction SilentlyContinue)
				Write-LogDebug " [Open-Browser] Cached $($cachedWindows.Count) [$browserProcessName] window(s) for $($resolvedGroups.Count) group check(s)"
			}

			foreach ($selection in $resolvedGroups) {
				$pathNames = $selection.PathNames
				$isParent = $selection.IsParent

				$groupItem = $urlGroups | Where-Object { $_.Keys -contains $pathNames[0] }
				$currentValue = $groupItem[$pathNames[0]]

				$navigateToIndex = if ($isParent) { $pathNames.Count } else { $pathNames.Count - 1 }

				for ($i = 1; $i -lt $navigateToIndex; $i++) {
					$nextName = $pathNames[$i]
					if ($currentValue -is [Array]) {
						$found = $false
						foreach ($item in $currentValue) {
							if ($item -is [hashtable]) {
								if ($item.ContainsKey($nextName)) {
									$currentValue = $item[$nextName]
									$found = $true
									break
								}
								elseif ($item.ContainsKey('Name') -and $item.Name -eq $nextName) {
									$currentValue = $item
									$found = $true
									break
								}
							}
						}
						if (-not $found) {
							Write-LogError "Error: Could not find path component '$nextName'"
							continue
						}
					}
				}

				$urlsToOpen = @()
				$openedSubgroups = @()
				$displayName = $pathNames -join " - "

				if ($isParent) {
					$result = Collect-BrowserUrls -Value $currentValue
					$urlsToOpen = $result.Urls
					$openedSubgroups = $result.Subgroups
				}
				else {
					if ($currentValue -is [Array] -and $currentValue.Count -gt 0 -and $currentValue[0] -is [string]) {
						$urlsToOpen = $currentValue
					}
					else {
						$leafName = $pathNames[-1]
						if ($currentValue -is [Array]) {
							$leafItem = $currentValue | Where-Object {
								($_ -is [hashtable] -and ($_.Name -eq $leafName -or $_.ContainsKey($leafName))) -or $_ -eq $leafName
							} | Select-Object -First 1

							if ($leafItem) {
								if ($leafItem -is [hashtable] -and $leafItem.ContainsKey('Url')) {
									$urlsToOpen = @($leafItem.Url)
								}
								elseif ($leafItem -is [hashtable] -and $leafItem.ContainsKey($leafName)) {
									$urlsToOpen = $leafItem[$leafName]
								}
								elseif ($leafItem -is [string]) {
									$urlsToOpen = @($leafItem)
								}
							}
						}
					}
				}

				if ($urlsToOpen.Count -eq 0) {
					Write-LogWarning "Warning: No URLs found for selection '$displayName'"
					continue
				}

				# Instances mode: open exactly N windows, accounting for already-open ones
				if ($Instances -gt 0) {
					$countParams = @{
						Urls             = $urlsToOpen
						Browser          = $Browser
						GroupDisplayName = $displayName
						ReturnCount      = $true
					}
					if ($cachedWindows) { $countParams['CachedBrowserWindows'] = $cachedWindows }

					$existingCount = Test-BrowserGroupAlreadyOpen @countParams
					$windowsToOpen = [Math]::Max(0, $Instances - $existingCount)

					if ($windowsToOpen -eq 0) {
						Write-LogWarning "[$displayName] already has $existingCount/$Instances instance(s) open!"
						continue
					}

					Write-LogDebug " [Open-Browser] Opening $windowsToOpen of $Instances instance(s) for [$displayName] ($existingCount already open)"

					for ($inst = 0; $inst -lt $windowsToOpen; $inst++) {
						if ($urlsToOpen.Count -eq 1) {
							if ($isTor) {
								Start-Process $browserPath -ArgumentList $urlsToOpen[0] -NoNewWindow -ErrorAction Stop
							}
							else {
								Start-Process $browserPath -ArgumentList $newWindowArg, $urlsToOpen[0] -NoNewWindow -ErrorAction Stop
							}
						}
						else {
							$urlString = $urlsToOpen -join " "
							if ($isTor -or $Browser -eq "Firefox") {
								Start-Process $browserPath -ArgumentList $urlString -NoNewWindow -ErrorAction Stop
							}
							else {
								Start-Process $browserPath -ArgumentList $newWindowArg, $urlString -NoNewWindow -ErrorAction Stop
							}
						}
					}

					Write-LogStep " Opened $windowsToOpen instance(s) of [$displayName]!$(if ($existingCount -gt 0) { " ($existingCount already existed)" })"
					continue
				}

				if (-not $Override) {
					$testParams = @{
						Urls             = $urlsToOpen
						Browser          = $Browser
						GroupDisplayName = $displayName
					}
					if ($cachedWindows) { $testParams['CachedBrowserWindows'] = $cachedWindows }

					$alreadyOpen = Test-BrowserGroupAlreadyOpen @testParams

					if ($alreadyOpen) {
						continue
					}
				}

				if ($urlsToOpen.Count -eq 1) {
					if ($isTor) {
						Start-Process $browserPath -ArgumentList $urlsToOpen[0] -NoNewWindow -ErrorAction Stop
					}
					else {
						Start-Process $browserPath -ArgumentList $newWindowArg, $urlsToOpen[0] -NoNewWindow -ErrorAction Stop
					}
				}
				else {
					$urlString = $urlsToOpen -join " "
					if ($isTor -or $Browser -eq "Firefox") {
						Start-Process $browserPath -ArgumentList $urlString -NoNewWindow -ErrorAction Stop
					}
					else {
						Start-Process $browserPath -ArgumentList $newWindowArg, $urlString -NoNewWindow -ErrorAction Stop
					}
				}

				Write-LogStep " Opened [$displayName]!"

				Write-LogList -Items $openedSubgroups
			}
		}

		Write-LogSuccess "$Browser opened$(if ($Private -and -not $isTor) { " in private mode" })!"
	}
	Catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
