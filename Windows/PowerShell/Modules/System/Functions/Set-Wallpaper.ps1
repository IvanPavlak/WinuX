function Set-Wallpaper {
	<#
	.SYNOPSIS
		Sets the desktop wallpaper for all or the current virtual desktop.

	.DESCRIPTION
		Applies a wallpaper image to the Windows desktop. Reads wallpaper paths from
		`WallpaperLightSettings` or `WallpaperDarkSettings` in Configuration.psd1 based on theme.

		With the VirtualDesktop PowerShell module available, applies the wallpaper to ALL
		virtual desktops. Without it, applies only to the current desktop.

		With `-Auto`, detects the current system theme and sets the matching wallpaper.
		Wallpaper style (fill, fit, stretch, tile, center) is read from `WallpaperStyles` config.

		Requires administrator privileges. Uses COM retry logic to handle transient failures.

	.PARAMETER Auto
		Auto-detect the system theme and apply the matching wallpaper.

	.PARAMETER Theme
		Theme to use: "Light", "Dark", or "Auto". Defaults to "Auto".

	.EXAMPLE
		Set-Wallpaper -Auto
		Sets the wallpaper for all virtual desktops matching the current system theme.

	.EXAMPLE
		Set-Wallpaper -Theme "Light"
		Sets the light theme wallpaper.
	#>
	param(
		[switch]$Auto,
		[Parameter(Mandatory = $false)]
		[ValidateSet("Light", "Dark", "Auto")]
		[string]$Theme = "Auto"
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting Wallpaper"

	try {
		Write-LogDebug " Parameters: Auto=$Auto, Theme=$Theme" -Style Step

		$hasVirtualDesktopModule = $false
		if (Get-Module -Name VirtualDesktop -ListAvailable) {
			try {
				# Import module only if not already loaded to prevent RPC server errors
				if (-not (Get-Module -Name VirtualDesktop)) {
					Import-Module VirtualDesktop -ErrorAction Stop -WarningAction SilentlyContinue
				}
				$hasVirtualDesktopModule = $true
				Write-LogDebug " VirtualDesktop module loaded successfully" -Style Step
			}
			catch {
				Write-LogWarning "Could not load VirtualDesktop module. Wallpaper will be set for current desktop only!"
				Write-LogDebug " VirtualDesktop module load error: $_" -Style Step
			}
		}
		else {
			Write-LogDebug " VirtualDesktop module not available" -Style Step
		}

		$WallpaperStyles = $Configuration.WallpaperStyles
		$WallpaperDarkSettings = $Configuration.WallpaperDarkSettings
		$WallpaperLightSettings = $Configuration.WallpaperLightSettings

		if (-not ([System.Management.Automation.PSTypeName]'WallpaperModule.Params').Type) {
			try {
				Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    namespace WallpaperModule {
        [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        public interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetMonitorDevicePathAt(uint monitorIndex);
        [return: MarshalAs(UnmanagedType.U4)]
        uint GetMonitorDevicePathCount();
        void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT rc);
        void SetBackgroundColor([MarshalAs(UnmanagedType.U4)] uint color);
        [return: MarshalAs(UnmanagedType.U4)]
        uint GetBackgroundColor();
        void SetPosition([MarshalAs(UnmanagedType.I4)] DesktopWallpaperPosition position);
        [return: MarshalAs(UnmanagedType.I4)]
        DesktopWallpaperPosition GetPosition();
        void SetSlideshow(IntPtr items);
        IntPtr GetSlideshow();
        void SetSlideshowOptions(DesktopSlideshowOptions options, uint slideshowTick);
        void GetSlideshowOptions(out DesktopSlideshowOptions options, out uint slideshowTick);
        void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorID, DesktopSlideshowDirection direction);
        DesktopSlideshowState GetStatus();
        void Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
    }

    public enum DesktopWallpaperPosition
    {
        Center = 0,
        Tile = 1,
        Stretch = 2,
        Fit = 3,
        Fill = 4,
        Span = 5
    }

    public enum DesktopSlideshowOptions
    {
        ShuffleImages = 0x01
    }

    public enum DesktopSlideshowDirection
    {
        Forward = 0,
        Backward = 1
    }

    public enum DesktopSlideshowState
    {
        Enabled = 0x01,
        Slideshow = 0x02,
        DisabledByRemoteSession = 0x04
    }

    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    public class DesktopWallpaperClass
    {
    }

    public class DesktopWallpaperHelper
    {
        private IDesktopWallpaper wallpaper;

        public DesktopWallpaperHelper()
        {
            var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD"));
            wallpaper = (IDesktopWallpaper)Activator.CreateInstance(type);
        }

        public uint GetMonitorCount()
        {
            return wallpaper.GetMonitorDevicePathCount();
        }

        public string GetMonitorDevicePathAt(uint index)
        {
            return wallpaper.GetMonitorDevicePathAt(index);
        }

        public void SetWallpaper(string monitorID, string path)
        {
            wallpaper.SetWallpaper(monitorID, path);
        }

        public string GetWallpaper(string monitorID)
        {
            return wallpaper.GetWallpaper(monitorID);
        }

        public void SetPosition(DesktopWallpaperPosition position)
        {
            wallpaper.SetPosition(position);
        }

        public bool IsMonitorActive(uint index)
        {
            try
            {
                string monitorID = wallpaper.GetMonitorDevicePathAt(index);
                if (string.IsNullOrEmpty(monitorID)) return false;
                RECT rc;
                wallpaper.GetMonitorRECT(monitorID, out rc);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public void Dispose()
        {
            if (wallpaper != null)
            {
                Marshal.ReleaseComObject(wallpaper);
                wallpaper = null;
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public class Params
    {
        [DllImport("User32.dll", CharSet=CharSet.Unicode)]
        public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    }
    }
"@
			}
			catch {
				Write-LogError "Error compiling wallpaper types => [$_]"
				Write-LogWarning "Try restarting PowerShell!"
				return
			}
		}

		if ($Auto) {
			$targetTheme = $Theme
			Write-LogDebug " Auto mode enabled, initial theme parameter: $targetTheme" -Style Step

			if ($targetTheme -eq 'Auto') {
				try {
					$isLightTheme = (Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop)
					$targetTheme = if ($isLightTheme -eq 1) { "Light" } else { "Dark" }
					Write-LogDebug " Detected theme from registry: $targetTheme (AppsUseLightTheme=$isLightTheme)" -Style Step
				}
				catch {
					Write-LogWarning "Could not detect system theme. Defaulting to [Dark]"
					$targetTheme = "Dark"
					Write-LogDebug " Theme detection error: $_" -Style Step
				}
			}

			$WallpaperSettings = if ($targetTheme -eq 'Light') { $WallpaperLightSettings } else { $WallpaperDarkSettings }
			Write-LogStep " Using [$targetTheme] theme wallpaper settings!"

			$MachineType = DetermineMachineType
			Write-LogDebug " MachineType: $MachineType" -Style Step

			$wallpaperSetting = $WallpaperSettings[$MachineType]
			if (-not $wallpaperSetting) {
				Write-LogWarning " No specific wallpaper found for [$MachineType]"
				Write-LogWarning "Using default"
				$wallpaperSetting = $WallpaperSettings["Default"]
			}

			Write-LogDebug " Wallpaper setting keys: $($wallpaperSetting.Keys -join ', ')" -Style Step

			$isMultiMonitor = $wallpaperSetting.ContainsKey("Monitors")
			Write-LogDebug " Is multi-monitor configuration: $isMultiMonitor" -Style Step

			if ($isMultiMonitor) {
				Write-LogStep " Detected multi-monitor configuration!"

				try {
					Write-LogDebug " Creating DesktopWallpaperHelper COM object..." -Style Step

					$desktopWallpaper = Invoke-WithRetry -ScriptBlock {
						New-Object WallpaperModule.DesktopWallpaperHelper
					} -MaxAttempts 3 -InitialDelayMs 150

					$totalMonitorCount = $desktopWallpaper.GetMonitorCount()

					# Filter to only active (connected) monitors
					$activeMonitorIndices = @()
					for ($i = 0; $i -lt $totalMonitorCount; $i++) {
						if ($desktopWallpaper.IsMonitorActive([uint32]$i)) {
							$activeMonitorIndices += $i
						}
						elseif (Test-LogVerbose) {
							$inactivePath = $desktopWallpaper.GetMonitorDevicePathAt([uint32]$i)
							Write-LogDebug " Skipping inactive/disconnected monitor at index $i`: $inactivePath" -Style Step
						}
					}
					$monitorCount = $activeMonitorIndices.Count

					Write-LogStep "   Found [$monitorCount] active monitor(s)" -BlankLineAfter

					Write-LogDebug " Total monitor paths: $totalMonitorCount, Active: $monitorCount" -Style Step

					$monitorSettings = $wallpaperSetting.Monitors
					Write-LogDebug " Monitor settings count: $($monitorSettings.Count)" -Style Step

					$allWallpapersMatch = $true
					for ($idx = 0; $idx -lt $monitorCount; $idx++) {
						$i = $activeMonitorIndices[$idx]
						if ($idx -lt $monitorSettings.Count) {
							$monitorConfig = $monitorSettings[$idx]
							$wallpaperFile = $monitorConfig.File
							$expectedWallpaperPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile

							if (Test-Path $expectedWallpaperPath) {
								$monitorID = $desktopWallpaper.GetMonitorDevicePathAt([uint32]$i)
								$currentWallpaper = $desktopWallpaper.GetWallpaper($monitorID)

								if ($currentWallpaper -ne $expectedWallpaperPath) {
									$allWallpapersMatch = $false
									break
								}
							}
						}
					}

					if ($allWallpapersMatch -and -not $hasVirtualDesktopModule) {
						$desktopWallpaper.Dispose()
						Write-LogWarning "Multi-monitor wallpaper already configured!" -NoLeadingNewline
						return
					}
					elseif ($allWallpapersMatch -and $hasVirtualDesktopModule) {
						Write-LogDebug " Current desktop wallpaper matches, but checking all virtual desktops..." -Style Step
					}

					for ($idx = 0; $idx -lt $monitorCount; $idx++) {
						$i = $activeMonitorIndices[$idx]
						if ($idx -lt $monitorSettings.Count) {
							$monitorConfig = $monitorSettings[$idx]
							$wallpaperFile = $monitorConfig.File
							$monitorStyle = $monitorConfig.Style

							$wallpaperPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile

							if (Test-Path $wallpaperPath) {
								$monitorID = $desktopWallpaper.GetMonitorDevicePathAt([uint32]$i)

								$positionValue = switch ($monitorStyle) {
									"Center" { 0 }
									"Tile" { 1 }
									"Stretch" { 2 }
									"Fit" { 3 }
									"Fill" { 4 }
									"Span" { 5 }
									default { 4 } # Fill
								}

								$desktopWallpaper.SetWallpaper($monitorID, $wallpaperPath)
								Write-LogSuccess "Monitor [$($idx + 1)] Set to [$wallpaperFile] with style [$monitorStyle]" -NoLeadingNewline
							}
							else {
								Write-LogError "Monitor [$($idx + 1)] wallpaper file not found at [$wallpaperPath]" -NoLeadingNewline
							}
						}
						else {
							Write-LogWarning "Monitor $($idx + 1): No wallpaper configured (using Windows default)"
						}
					}

					if ($monitorSettings.Count -gt 0) {
						$firstStyle = $monitorSettings[0].Style
						$position = switch ($firstStyle) {
							"Center" { [WallpaperModule.DesktopWallpaperPosition]::Center }
							"Tile" { [WallpaperModule.DesktopWallpaperPosition]::Tile }
							"Stretch" { [WallpaperModule.DesktopWallpaperPosition]::Stretch }
							"Fit" { [WallpaperModule.DesktopWallpaperPosition]::Fit }
							"Fill" { [WallpaperModule.DesktopWallpaperPosition]::Fill }
							"Span" { [WallpaperModule.DesktopWallpaperPosition]::Span }
							default { [WallpaperModule.DesktopWallpaperPosition]::Fill }
						}
						$desktopWallpaper.SetPosition($position)
					}

					if ($hasVirtualDesktopModule) {
						try {
							Write-LogDebug " VirtualDesktop module available, getting desktop info..." -Style Step

							$currentDesktop = Invoke-WithRetry -ScriptBlock {
								Get-CurrentDesktop
							} -MaxAttempts 3 -InitialDelayMs 200

							$originalDesktopIndex = Invoke-WithRetry -ScriptBlock {
								Get-DesktopIndex $currentDesktop
							} -MaxAttempts 3 -InitialDelayMs 200

							Write-LogDebug " Current desktop index: $originalDesktopIndex" -Style Step

							$allDesktops = Invoke-WithRetry -ScriptBlock {
								Get-DesktopList
							} -MaxAttempts 3 -InitialDelayMs 200

							$desktopCount = ($allDesktops | Measure-Object).Count

							Write-LogDebug " Total virtual desktops: $desktopCount" -Style Step

							if ($desktopCount -gt 1) {
								Write-LogStep " Applying wallpaper to all [$desktopCount] virtual desktops..."

								foreach ($desktop in $allDesktops) {
									try {
										$desktopNumber = $desktop.Number
										Write-LogDebug " Switching to virtual desktop #$desktopNumber..." -Style Step

										Invoke-WithRetry -ScriptBlock {
											Switch-Desktop -Desktop $desktopNumber -ErrorAction Stop | Out-Null
										} -MaxAttempts 3 -InitialDelayMs 200
										Start-Sleep -Milliseconds 200

										# Recreate COM object so it operates in the context of the newly active desktop
										$desktopWallpaper.Dispose()
										$desktopWallpaper = Invoke-WithRetry -ScriptBlock {
											New-Object WallpaperModule.DesktopWallpaperHelper
										} -MaxAttempts 3 -InitialDelayMs 150

										# Re-detect active monitors for this virtual desktop context
										$vdTotalCount = $desktopWallpaper.GetMonitorCount()
										$vdActiveIndices = @()
										for ($vi = 0; $vi -lt $vdTotalCount; $vi++) {
											if ($desktopWallpaper.IsMonitorActive([uint32]$vi)) {
												$vdActiveIndices += $vi
											}
										}

										for ($idx = 0; $idx -lt $vdActiveIndices.Count; $idx++) {
											$i = $vdActiveIndices[$idx]
											if ($idx -lt $monitorSettings.Count) {
												$monitorConfig = $monitorSettings[$idx]
												$wallpaperFile = $monitorConfig.File
												$wallpaperPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile

												if (Test-Path $wallpaperPath) {
													$monitorID = $desktopWallpaper.GetMonitorDevicePathAt([uint32]$i)
													Write-LogDebug "   Monitor #$($idx+1) (ID: $monitorID) => $wallpaperFile" -Style Step
													$desktopWallpaper.SetWallpaper($monitorID, $wallpaperPath)
												}
												else {
													Write-LogDebug "   Monitor #$($idx+1) wallpaper not found: $wallpaperPath" -Style Step
												}
											}
										}

										Write-LogDebug " Wallpapers set for desktop #$desktopNumber" -Style Step
									}
									catch {
										if ($_.Exception.Message -match 'RPC') { throw }
										Write-LogWarning "Could not switch to desktop [$desktopNumber]: $_"
										Write-LogDebug " Error details: $($_.Exception.Message)" -Style Step
									}
								}

								Write-LogDebug " Switching back to original desktop #$originalDesktopIndex..." -Style Step

								try {
									Invoke-WithRetry -ScriptBlock {
										Switch-Desktop -Desktop $originalDesktopIndex -ErrorAction Stop | Out-Null
									} -MaxAttempts 3 -InitialDelayMs 200
								}
								catch {
									if ($_.Exception.Message -match 'RPC') { throw }
									Write-LogWarning "Could not return to original desktop: $_"
									Write-LogDebug " Error details: $($_.Exception.Message)" -Style Step
								}
							}
							else {
								Write-LogDebug " Only one virtual desktop, skipping multi-desktop application" -Style Step
							}
						}
						catch {
							if ($_.Exception.Message -match 'RPC') { throw }
							Write-LogDebug " Virtual desktop error details => [$($_.Exception.Message)]" -Style Error
						}
					}
					else {
						Write-LogDebug " VirtualDesktop module not available for multi-monitor path" -Style Step
					}

					$desktopWallpaper.Dispose()
					Write-LogSuccess "Multi-monitor wallpaper configured successfully!"
					return
				}
				catch {
					if ($_.Exception.Message -match 'RPC') { throw }
					Write-LogError "Error setting multi-monitor wallpaper: $_"
					Write-LogWarning "Falling back to single wallpaper mode"

					if ($monitorSettings.Count -gt 0) {
						$wallpaperFile = $monitorSettings[0].File
						$selectedStyle = $monitorSettings[0].Style
						$wallpaper = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile
					}
					else {
						Write-LogError "No monitor settings available"
						return
					}
				}
			}
			else {
				$wallpaperFile = $wallpaperSetting.File
				$selectedStyle = $wallpaperSetting.Style
				$wallpaper = Join-Path -Path $MachineSpecificPaths.Projects.Self.Wallpapers -ChildPath $wallpaperFile
			}
		}
		else {
			$wallpaperPath = $MachineSpecificPaths.Projects.Self.Wallpapers
			$availableWallpapers = Get-ChildItem -Path $wallpaperPath -File |
				Where-Object { $_.Extension -match '\.(jpg|jpeg|png|bmp)$' } |
				Select-Object @{Name = 'Name'; Expression = { $_.BaseName } }, FullName

			if ($availableWallpapers.Count -eq 0) {
				Write-LogError "No wallpapers found in [$wallpaperPath]"
				return
			}

			$wallpaperNames = $availableWallpapers | Select-Object -ExpandProperty Name
			$selectedWallpaperName = Resolve-Selection -OptionList $wallpaperNames -MenuTitle "[Available Wallpapers]" -PromptMessage "Enter wallpaper name or number"

			$wallpaperFile = $availableWallpapers |
				Where-Object { $_.Name -eq $selectedWallpaperName } |
				Select-Object -ExpandProperty FullName

			if (-not $wallpaperFile) {
				Write-LogError "Wallpaper [$selectedWallpaperName] not found"
				return
			}

			$styleNames = $WallpaperStyles.Keys
			$selectedStyle = Resolve-Selection -OptionList $styleNames -MenuTitle "[Available Styles]" -PromptMessage "Enter wallpaper style (or press Enter for Fill)" -AllowEmptyPromptResponse:$true

			if ([string]::IsNullOrEmpty($selectedStyle)) {
				$selectedStyle = "Fill"
			}

			$wallpaper = $wallpaperFile
		}

		if (-not $isMultiMonitor -or (-not (Test-Path variable:isMultiMonitor))) {
			Write-LogDebug " Single wallpaper path - checking file existence" -Style Step

			if (-not (Test-Path $wallpaper)) {
				Write-LogError "Wallpaper file not found at path: $wallpaper"
				return
			}

			Write-LogDebug " Wallpaper file found: $wallpaper" -Style Step

			$keyDesktop = "HKCU:\Control Panel\Desktop"
			$currentWallpaper = Get-ItemPropertyValue -Path $keyDesktop -Name WallPaper
			$currentStyleValue = Get-ItemPropertyValue -Path $keyDesktop -Name WallpaperStyle
			$currentTileValue = Get-ItemPropertyValue -Path $keyDesktop -Name TileWallpaper

			Write-LogDebug " Current wallpaper: $currentWallpaper" -Style Step
			Write-LogDebug " Current style value: $currentStyleValue" -Style Step
			Write-LogDebug " Current tile value: $currentTileValue" -Style Step

			$newStyleValue = $WallpaperStyles[$selectedStyle]
			$newTileValue = if ($selectedStyle -eq "Tile") { "1" } else { "0" }

			Write-LogDebug " New style value: $newStyleValue (style: $selectedStyle)" -Style Step
			Write-LogDebug " New tile value: $newTileValue" -Style Step

			if (-not $hasVirtualDesktopModule -and
				$currentWallpaper -eq $wallpaper -and
				$currentStyleValue -eq $newStyleValue -and
				$currentTileValue -eq $newTileValue) {
				Write-LogWarning "Wallpaper already configured!"
				Write-LogDebug " Wallpaper unchanged, exiting" -Style Step
				return
			}
			elseif ($hasVirtualDesktopModule -and
				$currentWallpaper -eq $wallpaper -and
				$currentStyleValue -eq $newStyleValue -and
				$currentTileValue -eq $newTileValue) {
				Write-LogDebug " Current desktop wallpaper matches, but proceeding to check all virtual desktops..." -Style Step
			}

			Write-LogDebug " Setting file attribute +P on wallpaper" -Style Step

			attrib.exe $wallpaper +P /s | Out-Null

			Write-LogDebug " Setting registry values in $keyDesktop" -Style Step

			Set-ItemProperty -Path $keyDesktop -Name WallpaperStyle -Value $newStyleValue -Force | Out-Null
			Set-ItemProperty -Path $keyDesktop -Name TileWallpaper -Value $newTileValue -Force | Out-Null
			Set-ItemProperty -Path $keyDesktop -Name WallPaper -Value $wallpaper -Force | Out-Null

			$SPI_SETDESKWALLPAPER = 0x0014
			$UpdateIniFile = 0x01
			$SendChangeEvent = 0x02
			$fWinIni = $UpdateIniFile -bor $SendChangeEvent

			if ($hasVirtualDesktopModule) {
				try {
					Write-LogDebug " Single wallpaper mode - VirtualDesktop module available" -Style Step

					# Retry VirtualDesktop module commands to handle RPC initialization delays
					$currentDesktop = Invoke-WithRetry -ScriptBlock {
						Get-CurrentDesktop
					} -MaxAttempts 3 -InitialDelayMs 200

					$originalDesktopIndex = Invoke-WithRetry -ScriptBlock {
						Get-DesktopIndex $currentDesktop
					} -MaxAttempts 3 -InitialDelayMs 200

					Write-LogDebug " Current desktop index: $originalDesktopIndex" -Style Step

					$allDesktops = Invoke-WithRetry -ScriptBlock {
						Get-DesktopList
					} -MaxAttempts 3 -InitialDelayMs 200

					$desktopCount = ($allDesktops | Measure-Object).Count

					Write-LogDebug " Total virtual desktops: $desktopCount" -Style Step

					if ($desktopCount -gt 1) {
						Write-LogStep " Applying wallpaper to all $desktopCount virtual desktops..."

						foreach ($desktop in $allDesktops) {
							try {
								$desktopNumber = $desktop.Number
								Write-LogDebug " Switching to desktop #$desktopNumber..." -Style Step

								Invoke-WithRetry -ScriptBlock {
									Switch-Desktop -Desktop $desktopNumber -ErrorAction Stop | Out-Null
								} -MaxAttempts 3 -InitialDelayMs 200
								Start-Sleep -Milliseconds 10

								Write-LogDebug " Calling SystemParametersInfo for desktop #$desktopNumber with wallpaper: $wallpaper" -Style Step

								[WallpaperModule.Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaper, $fWinIni) | Out-Null

								Write-LogDebug " Wallpaper applied to desktop #$desktopNumber" -Style Step
							}
							catch {
								if ($_.Exception.Message -match 'RPC') { throw }
								Write-LogWarning "Could not switch to desktop $desktopNumber : $_"
								Write-LogDebug " Error details: $($_.Exception.Message)" -Style Step
							}
						}

						Write-LogDebug " Switching back to original desktop #$originalDesktopIndex..." -Style Step

						try {
							Invoke-WithRetry -ScriptBlock {
								Switch-Desktop -Desktop $originalDesktopIndex -ErrorAction Stop | Out-Null
							} -MaxAttempts 3 -InitialDelayMs 200
						}
						catch {
							if ($_.Exception.Message -match 'RPC') { throw }
							Write-LogWarning "Could not return to original desktop: $_"
							Write-LogDebug " Error details: $($_.Exception.Message)" -Style Step
						}
						Write-LogSuccess "Wallpaper configured with style [$selectedStyle] across all virtual desktops!"
					}
					else {
						Write-LogDebug " Only one virtual desktop, applying wallpaper once" -Style Step
						[WallpaperModule.Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaper, $fWinIni) | Out-Null
						Write-LogSuccess "Wallpaper configured with style [$selectedStyle]"
					}
				}
				catch {
					if ($_.Exception.Message -match 'RPC') { throw }
					Write-LogDebug " Virtual desktop error, falling back to single desktop: $($_.Exception.Message)" -Style Step
					[WallpaperModule.Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaper, $fWinIni) | Out-Null
				}
			}
			else {
				Write-LogDebug " VirtualDesktop module not available, applying to current desktop only" -Style Step
				[WallpaperModule.Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaper, $fWinIni) | Out-Null
				Write-LogSuccess "Wallpaper configured with style [$selectedStyle]!"
			}
		}
	}
	catch {
		Write-LogError "Error detected: [$($_.Exception.Message)]"

		ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning wallpaper setup!"
	}
}
