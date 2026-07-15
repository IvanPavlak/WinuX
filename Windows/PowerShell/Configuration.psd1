# ==============================================================================
# OVERVIEW
# ==============================================================================
# This file is the central configuration hub for the entire PowerShell system.
# It controls all aspects of the bootstrap process, system configuration,
# application management, and workflow automation.
#
# The configuration uses a hierarchical structure with path templates and machine-specific overrides
# to eliminate duplication while supporting any number of machines
# from a single configuration file.
#
# ARCHITECTURE:
# - BasePaths: Root directories per machine type (e.g., C:\Users\Name\Dev, etc.)
# - PathTemplates: Common paths using placeholders ({Dev}, {User}, {MachineType})
# - MachineOverrides: Machine-specific differences (rarely needed due to templates, but available)
# - Expand-ConfigPaths: Runtime function that expands placeholders into actual paths
#
# PLACEHOLDER SYSTEM:
# - {Dev}          → BasePaths.Dev for the current machine (e.g., "C:\Users\User\Development")
# - {User}         → BasePaths.User for the current machine (e.g., "C:\Users\You")
# - {MachineType}  → Current machine type (ships with "Test"; add your own)
# - {RepoRoot} → Resolved WinuX repository root path
# - {AppData}      → User's AppData\Roaming folder (e.g., "C:\Users\You\AppData\Roaming")
#
# USAGE:
# This configuration is automatically loaded during:
# 1. Bootstrap process (Install-Bootstrap.ps1 → Bootstrap.ps1 → Load-PathConfiguration)
# 2. PowerShell profile initialization (Microsoft.PowerShell_profile.ps1)
# 3. Manual load via: Load-PathConfiguration -RepoRoot "C:\Path\To\WinuX"
#
# After loading, configuration is available globally:
# - $global:Configuration (Universal configuration and templates)
# - $global:MachineSpecificPaths (Paths with placeholders expanded for current machine)
# - $global:MachineType (Current machine type → ships with "Test"; add your own)
#
# CONFIGURATION SECTIONS AND THEIR CONSUMERS:
#
# System Configuration:
# → GitConfig                           : Install-Git
# → Locales, DisplayLanguages           : Set-Locale, Set-DisplayLanguage
# → KeyboardLayouts                     : Set-KeyboardLayouts
# → NerdFonts, DefaultNerdFont          : Configure-NerdFont
# → ExplorerOptions                     : Set-ExplorerOptions
# → VisualEffects                       : Set-VisualEffects
# → AutoEnvironmentVariables            : Set-EnvironmentVariables
# → DotnetProjectsSearchPath            : Determine-DotnetDependencies
# → PostgreSqlPasswords                 : Configure-PostgreSqlPasswords
# → NuGetConfig                         : Configure-NuGetConfig
# → Themes                              : Set-SystemTheme
# → PowerButtonActions                  : Set-PowerButtonActions
# → PowerPlans                          : Set-PowerPlan
# → WallpaperStyles, Wallpaper*Settings : Set-Wallpaper
# → TaskbarConfiguration*               : Configure-Taskbar, Unpin-TaskbarApps, Clear-TaskbarPins
#
# Path & Repository Management:
# → BasePaths, PathTemplates     : Expand-ConfigPaths, all path-dependent functions
# → SymbolicLinks                : SymbolicLinkMaker
# → RepositoryGroups             : Update-Repositories, Initialize-Repository
# → GitHub URLs                  : All git clone/update operations
#
# Project & Workflow Management:
# → Projects, ProjectActions      : Open-Project
# → ProjectTerminals              : Open-ProjectTerminals, Run-Project, Resolve-ProjectPath
# → RunnableProjects              : Run-Project
# → VisualStudioSolutions         : Open-VisualStudio
# → VSCodeProjects                : Open-VSCode
#
# Workspace Management:
# → Workspaces, WorkspaceActions : Open-Workspace
#
# Application Configuration:
# → BrowserGroups                   : Open-Browser, Collect-BrowserUrls
# → AcrobatGroups, AcrobatPdfGroups : Open-Acrobat
# → Campaigns                       : Open-DnD
# → Universal executable paths      : Open-* functions (DBeaver, VirtualBox, etc.)
#
# Bootstrap Process:
# → PackageManagers              : Bootstrap
# → BootstrapConfig              : Bootstrap, Install-Bootstrap
#
# Machine Type Detection:
# → ValidMachineTypes            : DetermineMachineType, Test-MachineTypeScope
# → HostnameToMachineType        : DetermineMachineType
# → DefaultMachineType           : DetermineMachineType
# → LaptopChassisTypes           : Test-PowerPlan (WMI chassis type detection)
#
# UI & Visual Configuration:
# → ListFunctionsColors             : List-Functions
# → ShowFunctionDetailsColors       : Show-FunctionDetails
# → LoadingSpinners, DefaultSpinner : Loading-Spinner
# → FunctionDiscrepancyExclusions   : List-Functions
# → DefaultTranslateLanguages       : Invoke-GoogleTranslate
#
# Window Management & FancyZones:
# → LayoutNumbers              : Apply-FancyZones (keyboard shortcut mapping)
# → ZoneNameMappings           : Get-FancyZone (human-readable zone names to indices)
# → Layout files in Layouts/*/ : Set-WorkspaceWindowLayout, Visualize-Layouts
#
# CUSTOMIZATION GUIDE:
# Common customizations and where to make them:
#
# 1. Add a new machine:
#    - Add hostname → machine type mapping in HostnameToMachineType
#    - Add base paths in BasePaths section
#    - Add machine-specific theme in Themes
#    - Add wallpaper settings in WallpaperDarkSettings/WallpaperLightSettings
#    - Add taskbar apps (optional) in TaskbarConfiguration*
#    - Create layout files in Layouts/{MachineType}/ folder
#
# 2. Change development directory:
#    - Update BasePaths.Dev for your machine type
#    - All paths using {Dev} placeholder will automatically adjust
#
# 3. Add a new project:
#    - Add project path entry in PathTemplates.Projects
#    - Add a repository entry in RepositoryGroups (with Name, UrlPath, LocalPath)
#    - Add to Projects list for Open-Project menu
#    - Add project actions in ProjectActions (defines what happens when project opens)
#    - Optionally add to VSCodeProjects for Open-VSCode
#    - Optionally add to VisualStudioSolutions for Open-VisualStudio
#    - Optionally add to ProjectTerminals for Open-ProjectTerminals
#    - Optionally add to RunnableProjects/RunnableProjectMappings for Run-Project
#
# 4. Add a new repository:
#    - Add URL in Universal.GitHub.Private or Universal.GitHub.YourDefinedGroup
#    - Add a repository entry to a group in RepositoryGroups with:
#      * Name: Repository name used for selection and by-name updates
#      * UrlPath: Dot-notation path to URL in Universal.GitHub (e.g., "Universal.GitHub.Private.MyRepo")
#      * LocalPath: Dot-notation path to local directory (e.g., "Projects.MyProject.Root")
#      * Group: the group key the entry lives under ("Private", "Work", ... - freely configurable)
#
# 5. Configure new application:
#    - Add to WinGetApps.csv, ScoopApps.csv, or ChocolateyApps.csv in Bootstrap/Data/
#    - CSV format for WinGetApps: App,Version,Scope,Interactive,Source,Machine
#      * Version: "Latest" or specific version
#      * Scope: "d" (default), "m" (machine-wide), "u" (user)
#      * Interactive: "y" (yes), "n" (no)
#      * Source: "w" (winget), "s" (msstore)
#      * Machine: "All", "Test", or your own types, combinable like "PC/Laptop"
#    - CSV format for ScoopApps: App,Version,Global,Machine
#    - CSV format for ChocolateyApps: App,Version,Params,Force,Machine
#
# 6. Add symbolic link:
#    - Add entry in PathTemplates.SymbolicLinks with Path and Target
#    - Path: Where the symlink will be created
#    - Target: What the symlink points to (source file/folder in WinuX)
#    - Use placeholders for machine-independent configuration
#    - Nested symlinks supported: PowerToys = @{ Settings = @{ Path = ...; Target = ... } }
#
# 7. Add workspace:
#    - Add name to Workspaces list
#    - Configure actions in WorkspaceActions with array of action configs
#    - Each action: @{ Action = "FunctionName"; Parameters = @{ Param1 = "Value" } }
#    - Create layout file in Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1
#    - Run Visualize-Layouts -Layout "{WorkspaceName}_{MachineType}" -Update to add visualization
#
# 8. Add Browser URL group:
#    - Add group to BrowserGroups with hierarchical structure
#    - Simple: @{ GroupName = @( "https://url1.com", "https://url2.com" ) }
#    - Named: @{ GroupName = @( @{ Name = "UrlName"; Url = "https://url.com" } ) }
#    - Nested: @{ Parent = @( @{ Child = @( @{ Name = "..."; Url = "..." } ) } ) }
#    - Names must be unique across all groups (used for direct access)
#
# 9. Configure window layout for workspace:
#    - Create .psd1 file in Layouts/{MachineType}/ folder (e.g., MyWorkspace_PC.psd1)
#    - Define Monitors section with VirtualDesktopLayouts (maps desktop index to layout name)
#    - Define Layout array with window placement rules:
#      * ProcessName: Process name (e.g., "Code", "firefox")
#      * WindowTitle: Title pattern with wildcards (e.g., "*Visual Studio Code")
#      * DesktopNumber: Virtual desktop index (1-based)
#      * Zone: Zone name from ZoneNameMappings (e.g., "Left", "Top-Right")
#      * Monitor: "Primary" or "Secondary"
#    - Run: Visualize-Layouts -Layout "MyWorkspace_PC" -Update
#
# For detailed documentation on each section, see the comment blocks below.
# For usage examples, refer to the documentation.
#
# ==============================================================================

@{
	# ==========================================================================
	# Universal Constants (Machine-Independent)
	# ==========================================================================
	# Constants that remain the same across all machines.
	# These are typically system paths, executable locations, or shared URLs.
	#
	# Example:
	#   Desktop             = $null  # Auto-resolved to user's desktop
	#   FirefoxExe          = "C:\Program Files\Mozilla Firefox\firefox.exe"
	#   GitHub.Base         = "https://YourUsername@github.com"
	#   GitHub.Private.*    = Repository paths for private projects
	# ==========================================================================
	Universal                     = @{
		Desktop                  = $null
		Fonts                    = "C:\Windows\Fonts"
		TaskbarPinFolder         = "{AppData}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
		IconCacheDb              = "{User}\AppData\Local\IconCache.db"
		IconCacheFolder          = "{User}\AppData\Local\Microsoft\Windows\Explorer"
		OhMyPoshThemeFile        = "{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"
		TrainingFile             = "TrainingPlan.docx"
		WhatsAppLocalStoragePath = "{User}\AppData\Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\shared\transfers"
		FirefoxExe               = "C:\Program Files\Mozilla Firefox\firefox.exe"
		LeagueOfLegendsExe       = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Riot Games\League of Legends"
		SteamExe                 = "C:\Program Files (x86)\Steam\steam.exe"
		RiseupVpnExe             = "C:\Program Files (x86)\RiseupVPN\riseup-vpn.exe"
		DbeaverExe               = "{User}\AppData\Local\DBeaver\dbeaver.exe"
		OutlookLauncherExe       = "C:\Windows\explorer.exe"
		TeamViewerExe            = "C:\Program Files\TeamViewer\TeamViewer.exe"
		FoundryVTTExe            = "C:\Program Files\Foundry Virtual Tabletop\Foundry Virtual Tabletop.exe"
		NotepadPlusPlusExe       = "C:\Program Files\Notepad++\notepad++.exe"
		VisualStudio2026Exe      = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe"
		VirtualBoxExe            = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
		DockerExe                = "C:\Program Files\Docker\Docker\frontend\Docker Desktop.exe"
		WindowsTerminalHome      = "{User}"

		# Browser Configuration
		# Maps browser names to their executable paths and command-line arguments
		# Used by Open-Browser function to support multiple browsers
		Browsers                 = @{
			Firefox = @{
				Exe          = "C:\Program Files\Mozilla Firefox\firefox.exe"
				PrivateArg   = "-private-window"
				NewWindowArg = "-new-window"
			}
			Tor     = @{
				Exe = "{User}\Tor Browser\Browser\firefox.exe"
			}
			Chrome  = @{
				Exe          = "C:\Program Files\Google\Chrome\Application\chrome.exe"
				PrivateArg   = "--incognito"
				NewWindowArg = "--new-window"
			}
			Edge    = @{
				Exe          = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
				PrivateArg   = "-inprivate"
				NewWindowArg = "--new-window"
			}
			# For Brave to work with Open-Browser as expected, check Settings > On startup > New tab page option
			Brave   = @{
				Exe          = "{User}\AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe"
				PrivateArg   = "--incognito"
				NewWindowArg = "--new-window"
			}
		}

		DefaultBrowser           = "Firefox"

		# GitHub repository URLs. Base is combined with each path below to form a clone
		# URL, e.g. "https://github.com" + "/YourUsername/WinuX.git". List YOUR repositories
		# here, then reference them in RepositoryGroups (see the
		# "Add a new repository" guide in the docs).
		GitHub                   = @{
			Base    = "https://github.com"
			Private = @{
				# The WinuX repository itself - the worked example. List YOUR repositories here
				# as "<Name>" = "/<owner>/<repo>.git". A fork renames this to its own repo name.
				WinuX = "/YourUsername/WinuX.git"
				# Add your own repositories here, for example:
				# ExampleProject = "/YourUsername/ExampleProject.git"
			}
		}
	}

	# ==========================================================================
	# WSL Configuration
	# ==========================================================================
	DefaultWSLDistribution        = "Ubuntu"

	# ==========================================================================
	# Wake-on-LAN Configuration
	# ==========================================================================
	# Wake-on-LAN machine configurations. Used by Send-WakeOnLan and Test-MachineOnline.
	#
	# Each machine name listed in WakeOnLanMachines must match a key in WakeOnLanConfig
	# exactly (quote keys that contain spaces, e.g. "Proxmox Backup Server").
	#
	# The optional 'Address' (IP or hostname) makes Wake-on-LAN reliable: Send-WakeOnLan
	# pings it to skip machines that are already on, and to confirm a machine actually
	# woke up after the packet is sent. Leave it as "" for fire-and-forget (no checks).
	#
	# Example:
	#   WakeOnLanMachines = @("Server", "All", "None")
	#   WakeOnLanConfig = @{
	#       "Server" = @{
	#           MacAddress                     = "AA-BB-CC-DD-EE-FF"
	#           SubNetSpecificBroadcastAddress = "192.168.1.255"
	#           Address                        = "192.168.1.10"
	#           Port                           = 9
	#       }
	#   }
	#   DefaultWakeOnLanMachine = "Server"
	# ==========================================================================
	WakeOnLanMachines             = @(
		"Server",
		"All",
		"None"
	)

	# Example entry only - replace the MAC address and IP with your own machine's values.
	WakeOnLanConfig               = @{
		Server = @{
			MacAddress                     = "AA-BB-CC-DD-EE-FF"
			SubNetSpecificBroadcastAddress = "192.168.1.255"
			Address                        = "192.168.1.10"
			Port                           = 9
		}
	}

	DefaultWakeOnLanMachine       = "Server"

	# ==========================================================================
	# Base Paths Per Machine Type
	# ==========================================================================
	# Defines root directories for each machine type. These paths are used to
	# expand {Dev} and {User} placeholders throughout the configuration.
	#
	# Example:
	#   PC     = @{ Dev = "E:\Development";              User = "C:\Users\John" }
	#   Laptop = @{ Dev = "C:\Users\John\Projects";      User = "C:\Users\John" }
	#   Work   = @{ Dev = "D:\Work\Development";         User = "C:\Users\John" }
	#
	# The Expand-ConfigPaths function replaces {Dev} with the Dev path and
	# {User} with the User path for the current machine type.
	# ==========================================================================
	BasePaths                     = @{
		# Per-machine root dirs. Placeholders for the public template; your real paths are
		# written here at first run (see Initialize-Configuration) from your install input.
		Test    = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
		Machine = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
	}

	# ==========================================================================
	# Common Path Templates
	# ==========================================================================
	# Path templates use placeholders that are expanded at runtime:
	#   {Dev}         - Replaced with BasePaths.Dev for the machine type
	#   {User}        - Replaced with BasePaths.User for the machine type
	#   {MachineType} - Replaced with the machine type (Test, Machine)
	#
	# Example:
	#   Development = "{Dev}"
	#   Projects.MyApp.Root = "{Dev}\MyApp"
	#   SymbolicLinks.Profile.Target = "{Dev}\WinuX\profile_{MachineType}.ps1"
	#
	# The Expand-ConfigPaths function processes these templates to create
	# machine-specific paths.
	# ==========================================================================
	PathTemplates                 = @{
		ObsidianDirectory       = "{Dev}\Obsidian"
		ObsidianStartupScript   = "{RepoRoot}\Obsidian\ObsidianStartupScript.pyw"
		TrainingBackupDirectory = "{Dev}\ExampleBackup"
		# Machine-local destination for the generated taskbar layout XML (the StartLayoutFile the
		# Explorer Group Policy points at). Written directly by Configure-Taskbar / Unpin-TaskbarApps;
		# never versioned in the repo. Each machine keeps its own copy under C:\ProgramData.
		TaskbarLayoutFile       = "C:\ProgramData\provisioning\taskbar_layout.xml"
		DockerDirectory         = "{RepoRoot}\Docker"
		LearningBook            = "{User}\Learning\ExampleBook.pdf"
		TrainingDirectory       = "{User}\Training\2026"
		Dnd                     = @{
			# Example campaign character sheet (consumed by Open-DnD / Open-Acrobat). Replace with your own.
			ExampleCharacter = "{Dev}\Obsidian\Campaigns\ExampleCampaign\ExampleCharacter.pdf"
		}

		NuGetConfig             = @{
			SourcePath      = "{RepoRoot}\NuGet\nuget.config"
			DestinationPath = "{AppData}\NuGet\nuget.config"
		}

		# Projects Configuration
		# Defines paths for each project. These are used by multiple functions:
		# - Open-VSCode (via VSCodeProjects)
		# - Open-VisualStudio (via VisualStudioSolutions)
		# - Open-ProjectTerminals (via ProjectTerminals)
		# - Run-Project (via RunnableProjectMappings)
		# - Update-Repositories (via RepositoryGroups)
		#
		# Common keys:
		# - Root: Main project directory
		# - Solution: .sln file path for Visual Studio
		# - Api: Backend API directory
		# - Ui: Frontend UI directory
		# - Backend: Backend root (alternative to Api for some projects)
		Projects                = @{
			# This repository itself. The engine references it by the name-neutral key "Self"
			# (resolved to the real repo root via {RepoRoot}); its display name is "WinuX",
			# used in GitHub.Private, VSCodeProjects, ProjectTerminals and RepositoryGroups.
			Self           = @{
				Root             = "{RepoRoot}"
				Docs             = "{RepoRoot}\docs"
				Modules          = "{RepoRoot}\Windows\PowerShell\Modules"
				Wallpapers       = "{RepoRoot}\Wallpapers"
				Layouts          = "{RepoRoot}\Windows\PowerShell\Modules\Window\Layouts"
				# Folder holding *.code-workspace files for the -VSCodeWorkspace override
				# (Open-VSCodeWorkspace / Open-Workspace). See DefaultVSCodeWorkspaces below.
				VSCodeWorkspaces = "{RepoRoot}\VSCode\Workspaces"
			}
			# A worked example of a multi-part project (backend + UI). Replace it with your
			# own projects, or add more entries following the same shape. Keys like Root,
			# Solution, Api, Backend and Ui are consumed by VSCodeProjects,
			# VisualStudioSolutions, ProjectTerminals, ProjectActions and RunnableProjects.
			ExampleProject = @{
				Root     = "{Dev}\ExampleProject"
				Solution = "{Dev}\ExampleProject\ExampleProject.sln"
				Api      = "{Dev}\ExampleProject\src\Api"
				Ui       = "{Dev}\ExampleProject-UI"
			}
		}

		# Symbolic Links Configuration
		# Defines source → target mappings for symbolic links.
		# Used by SymbolicLinkMaker to create links during bootstrap.
		#
		# HOW SYMBOLIC LINKS WORK:
		# - Path: Location where the symlink will be created (on your system)
		# - Target: What the symlink points to (file in WinuX repository)
		# - Result: Changes to the original file in WinuX are reflected everywhere
		#
		# HOW TO ADD A SYMBOLIC LINK:
		# 1. Add entry here with Path and Target
		# 2. Run Bootstrap or SymbolicLinkMaker to create the links
		# 3. For nested links, use hashtable nesting:
		#    PowerToys = @{
		#        Settings = @{ Path = "..."; Target = "..." }
		#        Layouts  = @{ Path = "..."; Target = "..." }
		#    }
		#
		# Example:
		#   Git = @{
		#       Path   = "{User}\.gitconfig"              # Created here (symlink)
		#       Target = "{RepoRoot}\Git\.gitconfig"  # Points to this (real file)
		#   }
		SymbolicLinks           = @{
			Git                  = @{
				Path   = "{User}\.gitconfig"
				Target = "{RepoRoot}\Git\.gitconfig"
			}
			# SSH config symlinking is a natural fit for WinuX, but no example ssh/config
			# ships in the public repo (it would expose private hosts). To manage your own,
			# add an entry here pointing at a config file you keep in your fork, e.g.:
			#   SSH = @{ Path = "{User}\.ssh\config"; Target = "{RepoRoot}\.ssh\config" }
			# No taskbar symlink: the layout is generated per-machine and written straight to its
			# machine-local path (PathTemplates.TaskbarLayoutFile) by Configure-Taskbar /
			# Unpin-TaskbarApps, so there is nothing in the repo to link to.
			# App-specific symlinks whose payloads the template does not ship. Define them in
			# your Configuration.local.psd1 when you use the app - a symlink entry only makes
			# sense once the target exists in your fork (SymbolicLinkMaker skips missing
			# targets with a warning). Example - Obsidian vault settings:
			#   Obsidian = @{
			#       Path   = "{Dev}\Obsidian\.obsidian"
			#       Target = "{RepoRoot}\Obsidian\.obsidian"
			#   }
			PowerToys            = @{
				Settings      = @{
					Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\settings.json"
					Target = "{RepoRoot}\Windows\FancyZones\settings.json"
				}
				CustomLayouts = @{
					Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\custom-layouts.json"
					Target = "{RepoRoot}\Windows\FancyZones\custom-layouts.json"
				}
				LayoutHotkeys = @{
					Path   = "{User}\AppData\Local\Microsoft\PowerToys\FancyZones\layout-hotkeys.json"
					Target = "{RepoRoot}\Windows\FancyZones\layout-hotkeys.json"
				}
			}
			FastFetch            = @{
				Configuration = @{
					Path   = "{User}\.config\fastfetch\config.jsonc"
					Target = "{RepoRoot}\FastFetch\Windows\config_{MachineType}.jsonc"
				}
				Logo          = @{
					Path   = "{User}\.config\fastfetch\FastFetchLogo_{MachineType}.txt"
					Target = "{RepoRoot}\FastFetch\Windows\FastFetchLogo_{MachineType}.txt"
				}
			}
			CondaFastFetch       = @{
				Configuration = @{
					Path   = "{User}\.config\fastfetch\config_Conda.jsonc"
					Target = "{RepoRoot}\FastFetch\Windows\Conda\config_Conda_{MachineType}.jsonc"
				}
				Logo          = @{
					Path   = "{User}\.config\fastfetch\FastFetchLogo_Conda.txt"
					Target = "{RepoRoot}\FastFetch\Windows\Conda\FastFetchLogo_Conda.txt"
				}
			}
			OhMyPosh             = @{
				Path   = "{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"
				Target = "{RepoRoot}\Windows\Oh-My-Posh\WinuX_{MachineType}.omp.json"
			}
			PowerShell           = @{
				Profile       = @{
					Path   = "{User}\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
					Target = "{RepoRoot}\Windows\PowerShell\Microsoft.PowerShell_profile.ps1"
				}
				Configuration = @{
					Path   = "{User}\Documents\PowerShell\Configuration.psd1"
					Target = "{RepoRoot}\Windows\PowerShell\Configuration.psd1"
				}
			}
			WindowsTerminal      = @{
				Settings  = @{
					Path   = "{User}\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
					Target = "{RepoRoot}\Windows\WindowsTerminal\settings_{MachineType}.json"
				}
				CondaLogo = @{
					Path   = "{User}\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\CondaLogo.png"
					Target = "{RepoRoot}\Windows\WindowsTerminal\CondaLogo.png"
				}
			}
			# Example - TranslucentTB settings (payload not shipped by the template):
			#   TranslucentTB = @{
			#       Settings = @{
			#           Path   = "{User}\AppData\Local\Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState\settings.json"
			#           Target = "{RepoRoot}\Windows\TranslucentTB\settings.json"
			#       }
			#   }
			LazyGit              = @{
				Path   = "{User}\AppData\Local\lazygit\config.yml"
				Target = "{RepoRoot}\LazyGit\config.yml"
			}
			LazyDocker           = @{
				Path   = "{AppData}\lazydocker\config.yml"
				Target = "{RepoRoot}\LazyDocker\config.yml"
			}
		}
	}

	# ==========================================================================
	# Machine-Specific Overrides (Only Store Differences!)
	# ==========================================================================
	# Contains paths or settings that differ between machines and cannot be
	# templated with {Dev}/{User} placeholders. Use sparingly.
	#
	# Example:
	#   PC = @{
	#       Learning          = "E:\Books\ProgrammingBook.pdf"
	#       TrainingDirectory = "E:\Training\2026"
	#   }
	#   Laptop = @{
	#       Learning          = "C:\Users\John\Books\ProgrammingBook.pdf"
	#       TrainingDirectory = "C:\Users\John\Documents\Training"
	#   }
	# ==========================================================================
	MachineOverrides              = @{
		Test    = @{}
		Machine = @{}
	}

	# ==========================================================================
	# Git Configuration
	# ==========================================================================
	# Global Git settings configured during bootstrap by Install-Git function.
	#
	# Example:
	#   UserName        = "JohnDoe"
	#   UserEmail       = "john.doe@example.com"
	#   WingetPackageId = "Git.Git"
	# ==========================================================================
	# UserName/UserEmail are set automatically at first run (see Initialize-Configuration)
	# from your install-time input - they are intentionally left blank here so no personal
	# email is ever committed. Fill them in only in your own private fork if you prefer.
	GitConfig                     = @{
		UserName        = ""
		UserEmail       = ""
		WingetPackageId = "Git.Git"
	}

	# ==========================================================================
	# Package Managers Configuration
	# ==========================================================================
	PackageManagers               = @(
		"WinGet",
		"Scoop",
		"Chocolatey"
	)

	# ==========================================================================
	# Bootstrap Configuration
	# ==========================================================================
	# Controls bootstrap process behavior, logging, and external script URLs.
	#
	# HOW BOOTSTRAP WORKS:
	# 1. Run Install-Bootstrap.ps1 to download and set up WinuX
	# 2. Bootstrap function runs all configuration steps automatically
	# 3. Uses WithInitialSetup flag for first-time machine setup
	#
	# BOOTSTRAP STEPS (in order):
	# - Update-Repositories (clone/pull all configured repositories)
	# - Set-CustomExecutionPolicy, Enable-DeveloperMode
	# - Set-SystemTheme, Set-Locale, Set-DisplayLanguage, Set-KeyboardLayouts
	# - Configure-NerdFont, Install-PowerShellModules
	# - Set-SpecialFolders, Restart-Explorer
	# - Configure-WSL, Install package managers and apps
	# - Upgrade-All, fork-defined PersonalSteps, Install-DotnetEF
	# - Set-EnvironmentVariables, Create-CondaEnvironments, Configure-NuGetConfig
	# - Configure-Taskbar, Initialize-WSLEnvironment, SymbolicLinkMaker
	# - Configure-WSLSSH, Lock taskbar layout, Restart-Machine
	#
	# HOW TO ADD NEW APPLICATIONS:
	# 1. Add to appropriate CSV file in Bootstrap/Data/
	# 2. WinGetApps.csv: App,Version,Scope,Interactive,Source,Machine
	# 3. ScoopApps.csv: App,Version,Global,Machine
	# 4. ChocolateyApps.csv: App,Version,Params,Force,Machine
	# ==========================================================================
	BootstrapConfig               = @{
		# Log file configuration
		LogFileLocation       = "Desktop"  # Relative to user profile or full path
		LogFilePrefix         = "BootstrapLog"

		# Default branch for repository
		DefaultBranch         = "master"

		# Which repositories Bootstrap clones/updates, by machine type (consumed by Bootstrap ->
		# Update-Repositories). Values: "All" | "Private" | "Work" | "None". "Default" covers any
		# machine type not listed; absent => "All". Override per machine type as needed, e.g.
		# @{ Default = "All"; Test = "Private" }.
		RepositoryUpdateScope = @{
			Default = "All"
		}

		# Whether Bootstrap provisions WSL, by machine type (consumed by Bootstrap ->
		# Configure-WSL, Initialize-WSLEnvironment, Configure-WSLSSH). $true/$false per machine
		# type; "Default" covers any machine type not listed; absent => $true. WSL is an optional
		# comfort layer (Ubuntu shell, fastfetch/oh-my-posh in WSL, WSL SSH) - no other Bootstrap
		# step depends on it, and `wsl --install` adds a large download, an interactive
		# first-launch account prompt, and a reboot, so the minimal Test profile skips it.
		# SymbolicLinkMaker independently skips WSL symlinks when no distribution is present.
		WSLSetup              = @{
			Default = $true
			Test    = $false
		}

		# Fork-defined optional bootstrap steps, run right after Upgrade-All (consumed by
		# Bootstrap -> Invoke-PersonalSteps). Each entry is either the name of a function the
		# fork's modules export (runs on every machine type), or a hashtable
		# @{ Function = "Name"; Machine = "PC/Laptop" }
		# gated per machine type exactly like the app CSVs' Machine column ("All" covers every
		# machine; tokens are validated by Test-MachineTypeScope, so typos are reported instead
		# of silently never matching). Entries that do not resolve are skipped with a warning.
		# The base ships an empty list, so a vanilla WinuX bootstrap runs no personal steps.
		# Forks set their own list in Configuration.local.psd1, e.g.
		# PersonalSteps = @("Install-MyBackupTool") or
		# PersonalSteps = @(@{ Function = "Install-MyBackupTool"; Machine = "PC" }).
		PersonalSteps         = @()

		# External script URLs
		ExternalScripts       = @{
			MicrosoftActivationScripts = "https://get.activated.win"
		}

		# Local vendored scripts
		LocalScripts          = @{
			Win11Debloat = "{RepoRoot}\Windows\Win11Debloat\vendor\Win11Debloat.ps1"
		}

		# Prompts configuration (whether to ask user about optional steps)
		PromptForActivation   = $true
		PromptForDebloat      = $true

		# Package manager data files (relative to WinuX root)
		DataFiles             = @{
			WinGetApps        = "Windows\PowerShell\Modules\Bootstrap\Data\WinGetApps.csv"
			ScoopApps         = "Windows\PowerShell\Modules\Bootstrap\Data\ScoopApps.csv"
			ChocolateyApps    = "Windows\PowerShell\Modules\Bootstrap\Data\ChocolateyApps.csv"
			CondaEnvironments = "Conda\Environments"
		}
	}

	# ==========================================================================
	# Machine Type Mappings
	# ==========================================================================
	# Determines machine type from hostname. Used by DetermineMachineType
	# to configure machine-specific settings.
	#
	# Example:
	#   ValidMachineTypes = @("Test", "Machine")
	#   HostnameToMachineType = @{
	#       "DESKTOP-GAMING"  = "PC"
	#       "LAPTOP-PERSONAL" = "Laptop"
	#       "WORKSTATION-01"  = "Work"
	#   }
	#   DefaultMachineType = "Laptop"
	# ==========================================================================
	# Valid machine types. WinuX ships only the minimal "Test" profile; add your own types
	# here (plus a Layouts/<Type>/ folder and <name>_<Type> payload variants) - see
	# docs/configuration/guides/add-new-machine.md.
	ValidMachineTypes             = @(
		"Test"
	)

	# Laptop chassis types for WMI detection (Win32_SystemEnclosure.ChassisTypes)
	# 8=Portable
	# 9=Laptop
	# 10=Notebook
	# 11=HandHeld
	# 14=SubNotebook
	# 30=Tablet
	# 31=Convertible
	# 32=Detachable
	LaptopChassisTypes            = @(8, 9, 10, 11, 14, 30, 31, 32)

	# Maps hostname to machine type
	HostnameToMachineType         = @{
		# Map each machine's hostname to a machine type. Unknown hostnames fall back to
		# DefaultMachineType. "Test" is the minimal working profile; add your own machines.
		"Test" = "Test"
		# Example second machine (first add "PC" to ValidMachineTypes and create its
		# Layouts/PC/ folder + payload variants - see docs/configuration/guides/add-new-machine.md):
		# "YOUR-PC-HOSTNAME" = "PC"
	}

	# Default machine type if hostname not found
	DefaultMachineType            = "Test"

	# Machine type whose layout set a small (laptop-class) display uses; "" disables the override.
	SmallDisplayMachineType       = ""

	# Enable taskbar auto-hide during Bootstrap (Set-TaskbarAutoHide -Auto). Purely cosmetic:
	# zone geometry is work-area based and correct with a visible taskbar too. $false leaves
	# every machine's taskbar untouched; a fork can opt in via Configuration.local.psd1.
	TaskbarAutoHide               = $false

	# Maps machine type keys used in bootstrap/configuration
	MachinePathMappings           = @{
		"Test"    = "Test"
		"Default" = "Test"
	}

	# ==========================================================================
	# Locale & Language Settings
	# ==========================================================================
	# Regional settings for language, locale, and keyboard layouts.
	# Used by Set-Locale, Set-DisplayLanguage, and Set-KeyboardLayouts.
	#
	# Example:
	#   Locales = @{
	#       "Croatian" = @{ Code = "hr-HR"; GeoId = 191 }
	#       "English (US)" = @{ Code = "en-US"; GeoId = 244 }
	#   }
	#   DefaultLocale = "Croatian"
	#   KeyboardLayouts = @{ "Croatian" = "0000041A"; "US" = "00000409" }
	#   DefaultKeyboardLayoutSet = "Croatian-US"
	# ==========================================================================
	Locales                       = @{
		"Croatian"     = @{ Code = "hr-HR"; GeoId = 191 }
		"English (US)" = @{ Code = "en-US"; GeoId = 244 }
	}

	DefaultLocale                 = "Croatian"

	KeyboardLayouts               = @{
		"Croatian" = "0000041A"
		"US"       = "00000409"
	}

	KeyboardLayoutSets            = @{
		"Croatian-US" = @("Croatian", "US")
		"US-Croatian" = @("US", "Croatian")
	}

	DefaultKeyboardLayoutSet      = "Croatian-US"

	DisplayLanguages              = @{
		"English (US)" = "en-US"
		"Croatian"     = "hr-HR"
	}

	DefaultDisplayLanguage        = "English (US)"

	# ==========================================================================
	# Font Configuration
	# ==========================================================================
	# Nerd Font installation settings. Used by Configure-NerdFont function.
	#
	# Example:
	#   NerdFonts = @{
	#       "JetBrainsMono" = @{
	#           FolderName    = "JetBrainsMonoNerdFont"
	#           SearchPattern = "*JetBrainsMono*Nerd*Font*"
	#       }
	#   }
	#   DefaultNerdFont = "JetBrainsMono"
	# ==========================================================================
	NerdFonts                     = @{
		"JetBrainsMono" = @{
			FolderName    = "JetBrainsMonoNerdFont"
			SearchPattern = "*JetBrainsMono*Nerd*Font*"
		}
	}

	DefaultNerdFont               = "JetBrainsMono"

	# ==========================================================================
	# Special Folders
	# ==========================================================================
	# Redirects system folders (Downloads, Screenshots) to the Desktop.
	# Applied by Set-SpecialFolders.
	# ==========================================================================
	SpecialFolders                = @(
		@{
			Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders";
			Name        = "{374DE290-123F-4565-9164-39C4925E467B}"; # Downloads
			Value       = "{User}\Desktop";
			Description = "Redirect Downloads to Desktop"
		}
		@{
			Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders";
			Name        = "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}"; # Screenshots
			Value       = "{User}\Desktop";
			Description = "Redirect Screenshots to Desktop"
		}
	)

	# ==========================================================================
	# Explorer Options
	# ==========================================================================
	# Windows Explorer registry settings. Applied by Set-ExplorerOptions.
	#
	# Example:
	#   @{
	#       Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
	#       Name = "Hidden"
	#       Value = 1
	#       Description = "Show hidden files and folders"
	#   }
	# ==========================================================================
	ExplorerOptions               = @(
		# Win11Debloat LastUsedSettings is the source of truth for these two:
		# - ShowHiddenFolders
		# - ShowKnownFileExt
		#@{
		#	Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
		#	Name        = "Hidden";
		#	Value       = 1;
		#	Description = "Show hidden files, folders, and drives"
		#}
		#@{
		#	Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
		#	Name        = "HideFileExt";
		#	Value       = 0;
		#	Description = "Show file name extensions"
		#}
		@{
			Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
			Name        = "DontPrettyPath";
			Value       = 1;
			Description = "Show full path in the title bar"
		}
		@{
			Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer";
			Name        = "ShowRecent";
			Value       = 0;
			Description = "Do not show recently used files in Quick access"
		}
		@{
			Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer";
			Name        = "ShowFrequent";
			Value       = 0;
			Description = "Do not show frequently used folders in Quick access"
		}
	)

	# ==========================================================================
	# Visual Effects
	# ==========================================================================
	# Performance Options visual effects (System Properties → Performance Options
	# → Visual Effects tab), applied by Set-VisualEffects during Bootstrap. Every
	# key mirrors one dialog checkbox one-to-one: $true = effect on (appearance),
	# $false = effect off (performance). Keys left commented out are not touched;
	# with everything commented (the shipped default) Bootstrap changes NOTHING -
	# a fork opts in via Configuration.local.psd1. When at least one effect is
	# managed, the dialog's radio button is set to "Custom" (VisualFXSetting = 3).
	# ==========================================================================
	VisualEffects                 = @{
		# AnimateControlsAndElementsInsideWindows   = $false
		# AnimateWindowsWhenMinimisingAndMaximising = $false
		# AnimationsInTheTaskbar                    = $false
		# EnablePeek                                = $false
		# FadeOrSlideMenusIntoView                  = $false
		# FadeOrSlideToolTipsIntoView               = $false
		# FadeOutMenuItemsAfterClicking             = $false
		# SaveTaskbarThumbnailPreviews              = $true
		# ShowShadowsUnderMousePointer              = $false
		# ShowShadowsUnderWindows                   = $false
		# ShowThumbnailsInsteadOfIcons              = $true
		# ShowTranslucentSelectionRectangle         = $true
		# ShowWindowContentsWhileDragging           = $true
		# SlideOpenComboBoxes                       = $false
		# SmoothEdgesOfScreenFonts                  = $true
		# SmoothScrollListBoxes                     = $false
		# UseDropShadowsForIconLabelsOnTheDesktop   = $false
	}

	# ==========================================================================
	# Environment Variables
	# ==========================================================================
	# User-level environment variables set by Set-EnvironmentVariables -Auto.
	#
	# Example:
	#   AutoEnvironmentVariables = @{
	#       "NODE_PATH"   = "C:\Program Files\nodejs\"
	#       "PYTHON_HOME" = "C:\Python312\"
	#       "MY_DEV_PATH" = "{Dev}\Tools"  # Uses placeholder
	#   }
	# ==========================================================================
	AutoEnvironmentVariables      = @{
		"Conda"  = "{User}\miniconda3"
		"Claude" = "{User}\.local\bin"
		"Cargo"  = "{User}\.cargo\bin\cargo.exe"
	}

	# ==========================================================================
	# PATH Additions
	# ==========================================================================
	# Directories appended to the User PATH by Set-EnvironmentVariables -Auto.
	# Use hardcoded paths for fixed install locations, or placeholders for
	# paths relative to {Dev}/{User}.
	#
	# Example:
	#   AutoPathAdditions = @(
	#       "C:\msys64\ucrt64\bin"
	#       "{Dev}\Tools\bin"
	#   )
	# ==========================================================================
	AutoPathAdditions             = @(
		"C:\msys64\ucrt64\bin"
		# Oh My Posh install locations. The winget EXE installer registers its own PATH entry,
		# but on fresh machines that can fail to reach new shells (or use a different scope);
		# persisting the known locations here makes the profile's oh-my-posh init behave like
		# the classic one-liner everywhere. Directories that do not exist are harmless on PATH.
		"%LOCALAPPDATA%\Programs\oh-my-posh\bin"
		"C:\Program Files\oh-my-posh\bin"
	)

	# ==========================================================================
	# .NET Configuration
	# ==========================================================================
	# .NET project search configuration for Determine-DotnetDependencies function.
	# DotnetEFVersion specifies which version of EF Core tools to install.
	# If empty or null, Install-DotnetEf will install the latest version.
	#
	# Example:
	#   DotnetProjectsSearchPath = "C:\Users\Name\Development"
	#   DotnetEFVersion          = "8.0.11"  # Specific version
	#   DotnetEFVersion          = "8.*"     # Latest specific version
	#   DotnetEFVersion          = ""        # Install latest
	# ==========================================================================
	DotnetProjectsSearchPath      = "{Dev}"
	DotnetEFVersion               = "8.*"

	# ==========================================================================
	# PostgreSQL Configuration
	# ==========================================================================
	# PostgreSQL password settings for Configure-PostgreSqlPassword function.
	#
	# Example:
	#   PostgreSqlPasswords = @{
	#       DefaultOrCurrent = "postgres"        # Current/default password
	#       New              = "SecurePass123!"  # New password to set
	#   }
	# ==========================================================================
	# Conventional local-dev defaults only. Change "New" before using PostgreSQL for anything
	# you care about; never put a real/production password in this file.
	PostgreSqlPasswords           = @{
		DefaultOrCurrent = "postgres"
		New              = "ChangeMe"
	}

	# ==========================================================================
	# Theme Settings
	# ==========================================================================
	# System theme per machine type. Used by Set-SystemTheme -Auto.
	#
	# Example:
	#   Themes = @{
	#       "PC"     = "Dark"
	#       "Laptop" = "Dark"
	#       "Work"   = "Light"
	#   }
	# ==========================================================================
	Themes                        = @{
		"Test" = "Dark"
	}

	# ==========================================================================
	# Power Button & Lid Actions
	# ==========================================================================
	# Per-machine power button, sleep button, lid close actions, and shutdown
	# settings. Used by Set-PowerButtonActions -Auto.
	#
	# Action values: "DoNothing", "Sleep", "Hibernate", "ShutDown"
	#
	# Example:
	#   PowerButtonActions = @{
	#       "PC" = @{
	#           PowerButtonOnBattery = "ShutDown"
	#           PowerButtonPluggedIn = "ShutDown"
	#           SleepButtonOnBattery = "DoNothing"
	#           SleepButtonPluggedIn = "DoNothing"
	#           LidCloseOnBattery    = "ShutDown"
	#           LidClosePluggedIn    = "DoNothing"
	#           DisableFastStartup   = $true
	#           DisableSleep         = $true
	#           DisableHibernate     = $true
	#       }
	#   }
	# ==========================================================================
	PowerButtonActions            = @{
		"Test" = @{
			PowerButtonOnBattery = "ShutDown"
			PowerButtonPluggedIn = "ShutDown"
			SleepButtonOnBattery = "DoNothing"
			SleepButtonPluggedIn = "DoNothing"
			LidCloseOnBattery    = "ShutDown"
			LidClosePluggedIn    = "DoNothing"
			# Win11Debloat LastUsedSettings is the source of truth for DisableFastStartup.
			DisableSleep         = $true
			DisableHibernate     = $true
		}
	}

	# ==========================================================================
	# Power Plan
	# ==========================================================================
	# Power plan per machine type. Used by Set-PowerPlan -Auto.
	# Valid values: "Balanced", "HighPerformance", "UltimatePerformance"
	#
	# Example:
	#   PowerPlans = @{
	#       "PC"     = "UltimatePerformance"
	#       "Laptop" = "HighPerformance"
	#       "Work"   = "Balanced"
	#   }
	# ==========================================================================
	PowerPlans                    = @{
		"Test" = "UltimatePerformance"
	}

	# ==========================================================================
	# Wallpaper Configuration
	# ==========================================================================
	# Wallpaper settings per machine and theme. Used by Set-Wallpaper -Auto.
	# Supports multi-monitor setups with per-monitor wallpapers.
	#
	# Example:
	#   WallpaperStyles = @{
	#       "Fill"    = "10"  # Fills screen, may crop
	#       "Fit"     = "6"   # Fits image, may add bars
	#       "Stretch" = "2"   # Stretches to fill
	#   }
	#   WallpaperDarkSettings = @{
	#       "PC" = @{
	#           Monitors = @(
	#               @{ File = "Space1.jpg"; Style = "Fill" }
	#               @{ File = "Space2.jpg"; Style = "Fill" }
	#           )
	#       }
	#       "Laptop" = @{ File = "Mountain.jpg"; Style = "Fill" }
	#   }
	# ==========================================================================
	WallpaperStyles               = @{
		"Fill"    = "10"
		"Fit"     = "6"
		"Stretch" = "2"
		"Tile"    = "0"
		"Center"  = "0"
		"Span"    = "22"
	}

	WallpaperDarkSettings         = @{
		"Test"    = @{ File = "Black.jpg"; Style = "Fill" }
		"Default" = @{ File = "Black.jpg"; Style = "Fill" }
	}

	WallpaperLightSettings        = @{
		"Test"    = @{ File = "White.png"; Style = "Fill" }
		"Default" = @{ File = "White.png"; Style = "Fill" }
	}

	# ==========================================================================
	# Visual Studio Configuration
	# ==========================================================================
	VisualStudioSolutions         = @(
		# Example: maps a friendly name to a .sln path defined in PathTemplates.Projects.
		# Replace these with your own solutions.
		@{ Name = "ExampleProject"; Solution = "Projects.ExampleProject.Solution" }
	)

	# ==========================================================================
	# VS Code Configuration
	# ==========================================================================
	VSCodeProjects                = @(
		@{ Name = "WinuX"; Path = "Projects.Self.Root" }
		@{ Name = "ExampleProject"; Path = "Projects.ExampleProject.Root" }
	)

	# ==========================================================================
	# Project Terminal Configuration
	# ==========================================================================
	# Defines which terminal tabs to open for each project.
	# Used by Open-ProjectTerminals function.
	#
	# HOW TO ADD PROJECT TERMINALS:
	# Add an entry to ProjectTerminals with:
	#   - Name: Project name (used for display and lookup)
	#   - BasePath: Dot-notation path to project in PathTemplates.Projects
	#   - Paths: Array of subpath names (keys in the project's path definition)
	#
	# HOW PATHS WORK:
	# - BasePath "Projects.ExampleProject" points to the project config
	# - Paths @("API", "UI") opens tabs at the Api and Ui subpaths
	# - "ROOT" is special - opens at the project root path
	#
	# SPECIAL PATH TYPES:
	# - "DEFAULT": Opens a plain terminal tab at the default starting directory.
	#   No path definition needed in PathTemplates. Useful for projects that
	#   just need a shell without a specific working directory.
	# - "WSL": Opens a WSL tab using DefaultWSLDistribution.
	# - @{ Key = "Name"; Path = "C:\path" }: Opens a tab at a custom explicit path
	#   without requiring a matching entry in PathTemplates.
	# - @{ Key = "Name" }: Opens a plain tab (like DEFAULT) with a custom name.
	#
	# Example:
	#   @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI", "Tests") }
	#   @{ Name = "Server"; BasePath = "Projects.Server"; Paths = @("DEFAULT", "WSL") }
	# ==========================================================================
	ProjectTerminals              = @(
		@{ Name = "WinuX"; BasePath = "Projects.Self"; Paths = @("ROOT", "DOCS") }
		@{ Name = "ExampleProject"; BasePath = "Projects.ExampleProject"; Paths = @("API", "UI") }
		# A no-path showcase: terminals open at the default dir + a WSL tab (no PathTemplates entry needed).
		@{ Name = "Server"; BasePath = "Projects.Server"; Paths = @("DEFAULT", "WSL") }
	)

	# ==========================================================================
	# Repository Configuration
	# ==========================================================================
	# Maps repository names to URL paths and local paths, grouped by category.
	# Used by Update-Repositories and Initialize-Repository functions.
	#
	# STRUCTURE:
	# RepositoryGroups is an ordered list of groups (like BrowserGroups). Each group is a
	# single-key hashtable whose key is the group name and whose value is the list of
	# repositories in that group. Group names are freely configurable - add, rename, or
	# remove groups as you like; the interactive menu and -All follow whatever is defined.
	#
	# HOW TO ADD A NEW REPOSITORY:
	# 1. Add the GitHub URL path to Universal.GitHub section (Private or your org group)
	# 2. Add a repository entry to the desired group here with:
	#    - Name:      Repository name used for selection and by-name updates
	#    - UrlPath:   Dot-notation path to URL (e.g., "Universal.GitHub.Private.MyRepo")
	#    - LocalPath: Dot-notation path to local directory (e.g., "Projects.MyProject.Root")
	#
	# HOW TO UPDATE REPOSITORIES:
	# - Update-Repositories -Private    # Updates all repos in the "Private" group
	# - Update-Repositories -Work       # Updates all repos in the "Work" group
	# - Update-Repositories -All        # Updates all configured repositories
	# - Update-Repositories WinuX       # Updates specific repository by name
	# - Update-Repositories             # Interactive menu to select repositories
	#
	# Example:
	#   RepositoryGroups = @(
	#       @{ Private = @(
	#               @{ Name = "MyProject"; UrlPath = "Universal.GitHub.Private.MyProject"; LocalPath = "Projects.MyProject.Root" }
	#           )
	#       }
	#       @{ Work = @(
	#               @{ Name = "MyWorkRepo"; UrlPath = "Universal.GitHub.MyOrg.MyWorkRepo"; LocalPath = "Projects.MyOrg.MyWorkRepo.Root" }
	#           )
	#       }
	#   )
	# ==========================================================================
	RepositoryGroups              = @(
		# The WinuX repository itself (the worked example). Name is the repo's display name;
		# LocalPath points at the name-neutral Projects.Self entry. The group key ("Private",
		# "Work", ...) selects which Update-Repositories flag/menu entry includes the repo.
		@{ Private = @(
				@{ Name = "WinuX"; UrlPath = "Universal.GitHub.Private.WinuX"; LocalPath = "Projects.Self.Root" }
			)
		}
		# Add more groups/repositories, for example:
		# @{ Work = @(
		#         @{ Name = "ExampleProject"; UrlPath = "Universal.GitHub.Private.ExampleProject"; LocalPath = "Projects.ExampleProject.Root" }
		#     )
		# }
	)

	# ==========================================================================
	# Open-Project Configuration
	# ==========================================================================
	Projects                      = @(
		"WinuX",
		"ExampleProject",
		"Server"
	)

	# ==========================================================================
	# Project Actions Configuration
	# ==========================================================================
	# Defines actions to be executed when opening each project via Open-Project.
	# Each project can have multiple actions executed in sequence.
	#
	# HOW TO ADD A NEW PROJECT:
	# 1. Add project to the Projects list above
	# 2. Add paths in PathTemplates.Projects
	# 3. Add entry here defining what happens when the project opens
	#
	# Supported Action Types:
	#   - Open-VSCode                       : Opens VS Code with folder parameter (-Folder)
	#   - Open-VisualStudio                 : Opens Visual Studio with solution parameter (-Solution)
	#   - Open-ProjectTerminals-Or-RunProject : Opens terminals OR runs project based on RunApp flag
	#   - Run-Project                       : Runs project with project parameter (-Project)
	#   - Open-Browser                      : Opens Browser with group parameter (-Groups)
	#
	# Parameter Format:
	#   - For simple parameters: @{ Folder = "FolderName" }
	#   - For no parameters:     @{} or omit Parameters key
	#   - For boolean/switch:    @{ RunApp = $true }
	#
	# Special Parameters:
	#   - {ProjectName}: Automatically replaced with the current project name
	#   - This allows reusing the same action config across similar projects
	#
	# Example:
	#   "MyProject" = @(
	#       @{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
	#       @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
	#       @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
	#   )
	# ==========================================================================
	ProjectActions                = @{
		# DefaultProject = @(
		# 	@{ Action = "Open-Obsidian" }
		# 	@{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") } }
		# )

		WinuX          = @(
			@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
			@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
		)

		ExampleProject = @(
			#@{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
			@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
			@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
		)

		Server         = @(
			@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
		)
	}

	# ==========================================================================
	# Run-Project Configuration
	# ==========================================================================
	# Defines which projects can be run and their startup commands.
	# Used by Run-Project function and Open-ProjectTerminals-Or-RunProject action.
	#
	# HOW TO ADD A RUNNABLE PROJECT:
	# 1. Add project name to RunnableProjects list
	# 2. Add entry to RunnableProjectMappings with Commands array
	# 3. Commands order must match ProjectTerminals.Paths order
	#
	# HOW TO RUN A PROJECT:
	# - Run-Project                    # Interactive menu to select project
	# - Run-Project ExampleProject     # Runs specific project
	# - Open-Workspace Server ExampleProject run  # Opens workspace and runs project
	#
	# Supported Commands:
	# - "dnr"          : DotnetRun (dotnet run)
	# - "dnbr"         : DotnetBuildAndRun (dotnet build + run)
	# - "nir"          : NpmInstallAndStart (npm install + npm run dev)
	# - "npm run dev"  : Direct npm command
	# - ""             : Empty (no command for that path)
	# ==========================================================================
	DefaultDatabaseProvider       = "PostgreSQL"

	# Docker Compose file mappings for database providers managed by WinuX.
	# These are NOT committed to individual project repos - they live in WinuX/Docker/
	# and are used by Run-Project to spin up containers transparently.
	DockerComposeFiles            = @{
		PostgreSQL = "docker-compose.postgresql.yml"
	}

	RunnableProjects              = @(
		"WinuX",
		"ExampleProject"
	)

	# Command order has to match with the Paths order in ProjectTerminals
	# For example, if ProjectTerminals has Paths = @("API", "UI")
	# then Commands should be @("dnr", "nir") for API=dnr, UI=nir
	#
	# Both DotnetRun (dnr) and DotnetBuildAndRun (dnbr) are supported
	RunnableProjectMappings       = @(
		@{ Name   = "WinuX";
		 Commands = @("", "npx docsify-cli serve")
		}
		@{ Name            = "ExampleProject";
			Commands          = @("dnr", "nir");
			DatabaseProviders = @("PostgreSQL");
		}
	)

	# ==========================================================================
	# Workspace Configuration
	# ==========================================================================
	Workspaces                    = @(
		"Example",
		"Fullscreen",
		"Empty",
		"Default",
		"WinuX"
	)

	# ==========================================================================
	# Default VS Code Workspace Per Workspace
	# ==========================================================================
	# Optional. Maps an Open-Workspace name to a .code-workspace file (base name, no
	# extension) under Projects.Self.VSCodeWorkspaces (<repo>\VSCode\Workspaces). When set,
	# opening that workspace opens the .code-workspace in VS Code IN PLACE OF the project
	# folder, and Set-WorkspaceWindowLayout retitles the inferred VS Code layout entry
	# (ProcessName 'Code') so the layout targets the workspace window instead of the folder
	# window. A command-line "-VSCodeWorkspace <name>" overrides this; a bare
	# "-VSCodeWorkspace" (no value) shows a Resolve-Selection menu of available workspaces.
	# Empty => plain project-folder behaviour (the default).
	#
	# Example:
	#   DefaultVSCodeWorkspaces = @{ WinuX = "MyWorkspace" }
	# ==========================================================================
	DefaultVSCodeWorkspaces       = @{}

	# ==========================================================================
	# Workspace Actions Configuration
	# ==========================================================================
	# Defines actions to be executed when opening each workspace via Open-Workspace.
	# Each workspace can have multiple actions executed in sequence.
	#
	# HOW TO ADD A NEW WORKSPACE:
	# 1. Add workspace name to the Workspaces list above
	# 2. Add entry here defining what happens when the workspace opens
	# 3. Create a layout file in Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1
	# 4. Run: Visualize-Layouts -Layout "{WorkspaceName}_{MachineType}" -Update
	#
	# HOW TO OPEN A WORKSPACE:
	# - Open-Workspace                    # Interactive menu to select workspace
	# - Open-Workspace WinuX              # Opens specific workspace
	# - Open-Workspace MyWorkspace MyProject     # Opens workspace with specific project
	# - Open-Workspace MyWorkspace MyProject run # Opens workspace and runs the project
	#
	# Supported Action Types:
	#   - Open-Obsidian               : Opens Obsidian vault
	#   - Open-Acrobat                : Opens Acrobat with PDF group parameter (-Pdf)
	#   - Open-Browser                : Opens Browser with optional group parameter (-Groups)
	#   - Open-Project                : Opens project (uses -Project, -RunApp from caller)
	#   - Open-DBeaver                : Opens DBeaver database tool
	#   - Open-WhatsApp               : Opens WhatsApp Desktop
	#   - Open-Outlook                : Opens Outlook email client
	#   - Open-Discord                : Opens Discord
	#   - Open-DnD                    : Opens D&D campaign tools
	#   - Open-SecureBrowser          : Opens Tor browser with RiseupVPN
	#   - Send-WakeOnLan              : Wakes a machine via Wake-on-LAN
	#   - Training-Backup             : Runs Training-Backup command
	#   - Set-WorkspaceWindowLayout   : Applies window layout for the workspace
	#   - Test-PrivacyStatus          : Tests browser privacy status
	#   - Return                      : Exits workspace processing immediately
	#
	# Parameter Format:
	#   - For simple parameters: @{ Param1 = "Value1"; Param2 = "Value2" }
	#   - For array parameters:  @{ Groups = @("Group1", "Group2") }
	#   - For no parameters:     @{} or omit Parameters key
	#   - For boolean/switch:    @{ NoMenu = $true }
	#
	# PARAMETER FORWARDING:
	#   Open-Workspace supports intelligent parameter forwarding. Any extra parameters
	#   passed on the command line are automatically forwarded ONLY to actions that
	#   accept them. Parameters are filtered using PowerShell introspection (Get-Command).
	#
	#   Example: w MyWorkspace -Machine MyServer
	#     - Send-WakeOnLan receives -Machine MyServer (has $Machine parameter)
	#     - Open-Browser does NOT receive -Machine (filtered out automatically)
	#     - No errors, no function modifications needed!
	#
	#   This allows passing action-specific parameters without modifying every function.
	#
	# Special Cases:
	#   - Fullscreen: Applies full-screen FancyZone layout to all windows
	#   - Default: Actions when no workspace is selected (null/Enter selection)
	#   - Return action: Stops processing and exits (e.g., Training workspace)
	#
	# Example:
	#   "MyWorkspace" = @(
	#       @{ Action = "Open-Obsidian" }
	#       @{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
	#       @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub") } }
	#       @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
	#   )
	# ==========================================================================
	# TODO: Add support for a "universal" param which will then be sent to every action
	WorkspaceActions              = @{
		Example    = @(
			@{ Action = "Open-Browser"; Parameters = @{ NoMenu = $true ; Instances = 33 } }
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Example" } }
			@{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
		)

		Fullscreen = @(
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Fullscreen" } }
			@{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
		)

		Empty      = @(
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Empty" } }
			@{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
		)

		Default    = @(
			@{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google", "YouTube") } }
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Default" } }
			@{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
			@{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ IncludeCurrent = $true } }
		)

		# WinuX development: the repository's GitHub page on the left, VS Code on the right
		# (FancyZones layout "One") on virtual desktop 1. The terminal tab that launched the
		# workspace is closed last (OnlyCurrent leaves every other tab alive).
		WinuX      = @(
			@{ Action = "Open-Browser"; Parameters = @{ Groups = @("WinuX") } }
			@{ Action = "Open-VSCode"; Parameters = @{ Folder = "WinuX" } }
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "WinuX" } }
			@{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
			@{ Action = "Terminate-WindowsTerminalTabs"; Parameters = @{ OnlyCurrent = $true } }
		)
	}

	# ==========================================================================
	# D&D Configuration
	# ==========================================================================
	Campaigns                     = @(
		"ExampleCampaign"
	)

	# Per-campaign resources consumed by Open-DnD (rulebook PDF + resource browser group).
	CampaignResources             = @{
		ExampleCampaign = @{ Pdf = "ExampleCharacter"; Browser = "Reference" }
	}

	# ==========================================================================
	# Acrobat Configuration
	# ==========================================================================
	AcrobatGroups                 = @(
		"ExampleRulebook"
	)

	AcrobatPdfGroups              = @{
		"ExampleRulebook" = @("Dnd.ExampleCharacter")
	}

	# ==========================================================================
	# Taskbar Configuration
	#
	# Use Get-StartApps in PowerShell to determine AppID (AUMID or Path)
	# ==========================================================================
	# Taskbar pinned applications configuration. Used by Configure-Taskbar. Order of entries
	# determines pin order on the taskbar.
	#
	# Each row may carry a Machine scope, matched against the current machine type by
	# Test-MachineTypeScope (identical to the app CSVs' Machine column): "All" pins on every
	# machine, "Test" only on Test, "PC/Laptop" on PC or Laptop. Any type used here must exist
	# in ValidMachineTypes or it is reported as an unknown token. A row without a Machine key
	# (or a blank one) defaults to "All", so one list can drive every machine.
	#
	# This is the shipped example (every row tagged "All"); keep your real, machine-tagged list
	# in Configuration.local.psd1 - it replaces this array wholesale on merge. See
	# docs/configuration/guides/add-new-machine.md.
	#
	# Example:
	#   TaskbarConfiguration = @(
	#       @{ Name = "Terminal"; Type = "AUMID"; Value = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"; Machine = "All" }
	#       @{ Name = "Browser";  Type = "Path";  Value = "C:\Program Files\Mozilla Firefox\firefox.exe"; Machine = "All" }
	#       @{ Name = "WorkTool";  Type = "AUMID"; Value = "Contoso.Tool";                                Machine = "PC/Work" }
	#   )
	# ==========================================================================
	TaskbarConfiguration          = @(
		@{ Name = "WindowsTerminal"; Type = "AUMID"; Value = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"; Machine = "All" }
		@{ Name = "Obsidian"; Type = "AUMID"; Value = "md.obsidian"; Machine = "All" }
		@{ Name = "Firefox"; Type = "AUMID"; Value = "308046B0AF4A39CB"; Machine = "All" }
		@{ Name = "VSCode"; Type = "AUMID"; Value = "Microsoft.VisualStudioCode"; Machine = "All" }
		#@{ Name = "VisualStudio2026Community"; Type = "Path"; Value = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe"; Machine = "All" }
		@{ Name = "DBeaver"; Type = "Path"; Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Machine = "All" }
		#@{ Name = "WhatsappDesktop"; Type = "AUMID"; Value = "5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App"; Machine = "All" }
		#@{ Name = "BitWarden"; Type = "AUMID"; Value = "com.bitwarden.desktop"; Machine = "All" }
		@{ Name = "FileExplorer"; Type = "AUMID"; Value = "Microsoft.Windows.Explorer"; Machine = "All" }
	)

	# ==========================================================================
	# Browser Group Matching
	# ==========================================================================
	# Controls how Test-BrowserGroupAlreadyOpen decides whether a browser group
	# is already open by comparing configured URLs against visible window titles.
	#
	# HOW TO USE THIS SECTION:
	# - BrowserProcessNames:
	#   Add or override entries when the browser label passed to Open-Browser
	#   does not match the real process name. Example: Tor uses firefox.exe.
	# - KeywordExtraction.GenericWords:
	#   Add words that are too generic to identify a page reliably.
	# - KeywordExtraction.GenericSubdomains:
	#   Add technical wrapper subdomains that should not be treated as product
	#   names. Example: app.slack.com should prefer Slack, not App.
	# - KeywordExtraction.SpecialHostKeywords:
	#   Add branded aliases for hosts whose titles use a product name instead of
	#   the raw hostname. Example: mail.google.com -> gmail.
	# - KeywordExtraction.IgnoredPathSegments:
	#   Add path segments that should never become matching keywords.
	# - ExactTitle.SimpleHomepagePaths:
	#   Add homepage-like paths that should use exact title matching for provider
	#   homepages such as google.com or microsoft.com.
	# - NegativeMatching.KnownServiceSubdomains:
	#   List sibling products that must be excluded when checking a provider
	#   homepage. Example: google.com should not match Gemini or Calendar.
	# - ExactTitle.BrowserTitleSuffixPatterns:
	#   Regex suffixes stripped from titles before exact homepage comparisons.
	# - Matching:
	#   Tune these thresholds only when duplicate detection is consistently too
	#   strict or too permissive across multiple browser groups.
	# → Consumer: Test-BrowserGroupAlreadyOpen
	# ==========================================================================
	BrowserGroupMatching          = @{
		# Browser label -> actual process name.
		BrowserProcessNames = @{
			Chrome  = "chrome"
			Firefox = "firefox"
			Edge    = "msedge"
			Tor     = "firefox"
			Brave   = "brave"
		}

		# Keyword extraction rules applied to URL hosts, paths, and fragments.
		KeywordExtraction   = @{
			LocalhostHosts       = @(
				"localhost"
			)
			MinimumKeywordLength = 4
			GenericWords         = @(
				"new",
				"index",
				"home",
				"main",
				"page",
				"default",
				"app",
				"www",
				"chat"
			)
			GenericSubdomains    = @(
				"www",
				"app",
				"web",
				"login",
				"api",
				"cdn",
				"static",
				"m",
				"mobile"
			)
			IgnoredPathSegments  = @(
				"index.html"
			)
			SpecialHostKeywords  = @{
				"claude.ai"            = @("claude")
				"chat.openai.com"      = @("chatgpt", "openai")
				"gemini.google.com"    = @("gemini")
				"aistudio.google.com"  = @("aistudio")
				"mail.google.com"      = @("gmail")
				"perplexity.ai"        = @("perplexity")
				"homepage.example.com" = @("server")
			}
		}

		# Exact-title rules for provider homepages where generic domain keywords
		# alone would be too permissive.
		ExactTitle          = @{
			HomepageIndicatorSubdomains = @(
				"www"
			)
			SimpleHomepagePaths         = @(
				"",
				"index.html",
				"index.htm",
				"search"
			)
			BrowserTitleSuffixPatterns  = @(
				'\s*[-—]\s*(Mozilla\s+)?Firefox\s*$',
				'\s*[-—]\s*Google\s+Chrome\s*$',
				'\s*[-—]\s*Microsoft\s+Edge\s*$',
				'\s*[-—]\s*Opera.*$',
				'\s*[-—]\s*Brave\s*$'
			)
		}

		# Shared-provider services that should be excluded when checking a naked
		# provider homepage such as google.com.
		NegativeMatching    = @{
			KnownServiceSubdomains = @{
				"google"    = @(
					"gemini",
					"drive",
					"docs",
					"sheets",
					"slides",
					"maps",
					"mail",
					"calendar",
					"photos",
					"meet",
					"chat",
					"keep",
					"translate",
					"news",
					"play",
					"aistudio",
					"colab",
					"cloud",
					"analytics",
					"adsense",
					"ads",
					"flights",
					"shopping",
					"classroom",
					"books",
					"scholar",
					"earth",
					"fonts",
					"console",
					"assistant"
				)
				"microsoft" = @(
					"outlook",
					"teams",
					"sharepoint",
					"onedrive",
					"onenote",
					"excel",
					"word",
					"powerpoint",
					"forms",
					"planner",
					"dynamics",
					"azure",
					"copilot"
				)
				"apple"     = @(
					"music",
					"icloud",
					"maps",
					"news",
					"books",
					"podcasts",
					"fitness"
				)
				"amazon"    = @(
					"prime",
					"music",
					"kindle",
					"aws",
					"photos",
					"alexa",
					"audible"
				)
			}
		}

		# Confidence thresholds and regex patterns used during title matching.
		Matching            = @{
			ProblemLoadingPagePattern          = "(?i)problem.{0,10}loading.{0,10}page"
			MinimumAcceptedScore               = 4
			WordBoundaryScoreMultiplier        = 2
			SlugScoreMultiplier                = 1
			HighConfidencePrimaryKeywordLength = 6
			MultiUrlSecondaryOnlyThreshold     = 3
		}
	}

	# ==========================================================================
	# Browser Groups
	# ==========================================================================
	# Hierarchical Browser URL group configurations. Used by Open-Browser.
	# Supports unlimited nesting depth with group → subgroup → URL structure.
	#
	# HOW TO OPEN BROWSER GROUPS:
	# - Open-Browser                      # Interactive menu to select groups
	# - Open-Browser AI                   # Opens all URLs in the AI group
	# - Open-Browser AI,GitHub            # Opens multiple groups
	# - Open-Browser ChatGPT              # Opens specific named URL directly
	# - Open-Browser -Private AI          # Opens in private/incognito mode
	#
	# NAME UNIQUENESS REQUIREMENT:
	# Names must be unique across ALL groups! If "Profile" exists in both
	# Personal and Firm subgroups, Open-Browser Profile will only open the
	# last one processed. Use unique names like "PersonalProfile", "FirmProfile".
	#
	# URL FORMATS:
	# 1. Simple string (group with raw URLs):
	#    @{ Google = @( "https://www.google.com/" ) }
	#
	# 2. Named URL (for direct access by name):
	#    @{ AI = @( @{ Name = "ChatGPT"; Url = "https://chat.openai.com/" } ) }
	#
	# 3. Nested groups (for organization):
	#    @{ GitHub = @(
	#        @{ Personal = @(
	#            @{ Name = "PersonalProfile"; Url = "https://github.com/UserName" }
	#        )}
	#        @{ Work = @(
	#            @{ Name = "WorkProfile"; Url = "https://github.com/WorkOrg" }
	#        )}
	#    )}
	#
	# 4. Mixed array (named URLs alongside nested sub-groups):
	#    @{ Server = @(
	#        @{ Name = "Homepage"; Url = "https://homepage.example.com" }
	#        @{ Name = "Proxmox"; Url = "https://proxmox.example.com" }
	#        @{ ArrStack = @(
	#            @{ Name = "Sonarr"; Url = "https://sonarr.example.com" }
	#            @{ Name = "Radarr"; Url = "https://radarr.example.com" }
	#        )}
	#    )}
	#
	# Example:
	#   BrowserGroups = @(
	#       @{ AI = @(
	#           @{ Name = "ChatGPT"; Url = "https://chat.openai.com/" }
	#           @{ Name = "Claude";  Url = "https://claude.ai/new" }
	#       )}
	#       @{ Dev = @(
	#           @{ Name = "GitHub"; Url = "https://github.com/" }
	#       )}
	#   )
	# ==========================================================================
	BrowserGroups                 = @(
		@{ Google = @(
				"https://www.google.com/"
			)
		}

		@{ WhatsAppWeb = @(
				"https://web.whatsapp.com/"
			)
		}

		@{ AI = @(
				@{ Name = "Gemini"; Url = "https://gemini.google.com/" }
				@{ Name = "GoogleAiStudio"; Url = "https://aistudio.google.com/prompts/new_chat" }
				@{ Name = "Perplexity"; Url = "https://www.perplexity.ai/" }
				@{ Name = "ChatGPT"; Url = "https://chat.openai.com/" }
				@{ Name = "Claude"; Url = "https://claude.ai/new" }
			)
		}

		# Example self-hosted dashboard. Replace these with YOUR OWN services - public
		# reverse-proxy domains and/or LAN addresses. Demonstrates the nested DomainLinks /
		# LocalLinks structure that Open-Browser and a "Server" workspace consume.
		@{ Server = @(
				@{ DomainLinks = @(
						@{ Name = "DomainDashboard"; Url = "https://dashboard.example.com" }
						@{ Name = "DomainRouter"; Url = "http://192.168.1.1" }
					)
				}
				@{ LocalLinks = @(
						@{ Name = "LocalDashboard"; Url = "http://192.168.1.10:3000" }
						@{ Name = "LocalRouter"; Url = "http://192.168.1.1/" }
					)
				}
			)
		}

		# Example local dev API docs - adjust the port(s) to match your projects.
		@{ Swagger = @(
				@{ Name = "ExampleProject"; Url = "http://localhost:5000/swagger/index.html" }
			)
		}

		@{ Email = @(
				"https://mail.google.com/mail/u/0/#inbox"
			)
		}

		@{ Calendar = @(
				"https://calendar.google.com/calendar/u/0/r/week"
			)
		}

		@{ GitHub = @(
				@{ Name = "Profile"; Url = "https://github.com/YourUsername" }
				@{ Name = "WinuX"; Url = "https://github.com/YourUsername/WinuX" }
			)
		}

		@{ News = @(
				"https://www.reuters.com/",
				"https://apnews.com/",
				"https://www.bbc.com/news"
			)
		}

		@{ YouTube = @(
				"https://www.youtube.com/"
			)
		}

		@{ Reddit = @(
				"https://www.reddit.com/"
			)
		}

		# Example of a deeply-nested group (kept small). The matching engine supports
		# arbitrary nesting; expand with your own sub-groups as needed.
		@{ Reference = @(
				@{ Docs = @(
						@{ Name = "MDN"; Url = "https://developer.mozilla.org/" }
						@{ Name = "DevDocs"; Url = "https://devdocs.io/" }
					)
				}
			)
		}
	)

	# ==========================================================================
	# List-Functions Configuration
	# ==========================================================================
	# Functions excluded from discrepancy checks by List-Functions.
	# These appear in README but aren't loaded in session (standalone scripts).
	#
	# Example:
	#   FunctionDiscrepancyExclusions = @(
	#       "Install-Bootstrap",
	#       "One-Time-Setup"
	#   )
	# ==========================================================================
	FunctionDiscrepancyExclusions = @(
		"Install-Bootstrap"
	)

	# Color scheme for List-Functions output
	# Used for syntax highlighting different output sections
	#
	# Example:
	#   ListFunctionsColors = @{
	#       Border              = "Cyan"
	#       DiscrepancyError    = "Red"
	#       DiscrepancySuccess  = "Green"
	#   }
	ListFunctionsColors           = @{
		Border             = "DarkCyan" # Category borders and function count borders
		DiscrepancyError   = "Red"      # Discrepancy warning messages
		DiscrepancySuccess = "Green"    # Success message when no discrepancies found
	}

	# ==========================================================================
	# Show-FunctionDetails Configuration
	# ==========================================================================
	# Color scheme for Show-FunctionDetails function output.
	# Used for displaying function details with color-coded parameters.
	#
	# Example:
	#   ShowFunctionDetailsColors = @{
	#       FunctionName = "Green"
	#       Description  = "White"
	#       Parameters   = @("Cyan", "DarkCyan", "Blue", "DarkBlue")
	#   }
	# ==========================================================================
	ShowFunctionDetailsColors     = @{
		FunctionName = "DarkCyan"                                # Color for the function name
		Description  = "Gray"                                    # Color for the function description
		Parameters   = @("Cyan", "DarkCyan", "Blue", "DarkBlue") # Rotating colors for parameters
	}

	# ==========================================================================
	# Loading-Spinner Configuration
	# ==========================================================================
	# Spinner styles for Loading-Spinner function with animation symbols/delay.
	#
	# Example:
	#   LoadingSpinners = @{
	#       "Dots" = @{
	#           Symbols = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
	#           Delay   = 80  # Milliseconds between frames
	#       }
	#   }
	#   DefaultSpinner = "Dots"
	# ==========================================================================
	LoadingSpinners               = @{
		"BrailleBlocks" = @{
			Symbols = @("⣾⣿", "⣽⣿", "⣻⣿", "⢿⣿", "⡿⣿", "⣟⣿", "⣯⣿", "⣷⣿",
				"⣿⣾", "⣿⣽", "⣿⣻", "⣿⢿", "⣿⡿", "⣿⣟", "⣿⣯", "⣿⣷")
			Delay   = 50
		}
		"Dots"          = @{
			Symbols = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
			Delay   = 50
		}
		"Line"          = @{
			Symbols = @("|", "/", "-", "\")
			Delay   = 50
		}
		"Arrows"        = @{
			Symbols = @("←", "↖", "↑", "↗", "→", "↘", "↓", "↙")
			Delay   = 50
		}
		"Box"           = @{
			Symbols = @("▖", "▘", "▝", "▗")
			Delay   = 50
		}
		"Circle"        = @{
			Symbols = @("◐", "◓", "◑", "◒")
			Delay   = 50
		}
		"Moon"          = @{
			Symbols = @("🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘")
			Delay   = 50
		}
		"Clock"         = @{
			Symbols = @("🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛")
			Delay   = 50
		}
		"Star"          = @{
			Symbols = @("✶", "✸", "✹", "✺", "✹", "✸")
			Delay   = 50
		}
		"Dot"           = @{
			Symbols = @("⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂")
			Delay   = 50
		}
		"GrowingDots"   = @{
			Symbols = @("⢀⠀", "⢄⠀", "⢤⠀", "⢦⠀", "⢶⠀", "⢷⠀", "⣾⠀", "⣷⠀", "⣯⠀", "⣟⠀", "⡿⠀", "⠿⠀", "⠻⠀", "⠛⠀", "⠋⠀", "⠙⠀", "⠸⠀", "⢸⠀")
			Delay   = 50
		}
		"BlockFill"     = @{
			Symbols = @("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂")
			Delay   = 50
		}
		"Pulse"         = @{
			Symbols = @("∙", "●", "◉", "○", "◉", "●")
			Delay   = 50
		}
		"Binary"        = @{
			Symbols = @("010010", "001001", "100100", "010010", "001001", "100100")
			Delay   = 100
		}
		"Triangle"      = @{
			Symbols = @("◢", "◣", "◤", "◥")
			Delay   = 50
		}
		"BarBlocks"     = @{
			Symbols = @("▉", "▊", "▋", "▌", "▍", "▎", "▏", "▎", "▍", "▌", "▋", "▊", "▉")
			Delay   = 50
		}
		"SquareCorners" = @{
			Symbols = @("◰", "◳", "◲", "◱")
			Delay   = 50
		}
		"Hamburger"     = @{
			Symbols = @("☱", "☲", "☴")
			Delay   = 50
		}
		"Arc"           = @{
			Symbols = @("◜", "◝", "◞", "◟")
			Delay   = 50
		}
	}

	# Default spinner to use if none is specified
	DefaultSpinner                = "Dots"

	# ==========================================================================
	# Logging Configuration
	# ==========================================================================
	# Palette and file-logging behavior for the Logging module (Write-Log* functions,
	# Set-LogLevel, Start-Logging / Stop-Logging). Console colors default to the documented
	# house style; structured logs are written to the module's own Logs/ folder and pruned by
	# the retention limits below so they stay detailed but small. Pinned logs (Logs/Pinned,
	# created via Protect-Log) are never pruned.
	# → Consumer: Initialize-LoggingState, Write-Log, Clear-OldLogs
	#
	# Example:
	#   Logging = @{
	#       DefaultLevel = "Normal"   # Quiet | Normal | Verbose
	#       Colors       = @{ Success = "Green"; Error = "Red" }
	#       FileLogging  = @{ Enabled = $true; Retention = @{ MaxSessionFiles = 20 } }
	#   }
	# ==========================================================================
	Logging                       = @{
		# Console verbosity at session start: Quiet | Normal | Verbose
		DefaultLevel = "Normal"

		# Per-level console colors (must be valid PowerShell console color names).
		Colors       = @{
			Title   = "DarkCyan"
			Step    = "White"
			Success = "Green"
			Warning = "Yellow"
			Error   = "Red"
			Debug   = "DarkCyan"
		}

		# Structured, leveled file logging mirrored from every Write-Log* call.
		FileLogging  = @{
			Enabled       = $true        # Set $false to disable file logging entirely
			Directory     = ""           # Empty => the module's own Logs/ folder (recommended; gitignored)
			ErrorFileName = "Errors.log" # Verbose error log (message + exception + stack trace)

			# Retention keeps the Logs/ folder detailed but bounded. Pinned logs are exempt.
			Retention     = @{
				MaxAgeDays         = 7   # Delete session logs older than this many days
				MaxSessionFiles    = 20  # Keep at most this many session logs (newest retained)
				MaxTotalSizeMB     = 50  # Cap combined session-log size (oldest removed first)
				MaxErrorFileSizeMB = 5   # Trim the error log to its most recent content past this size
			}
		}
	}

	# ==========================================================================
	# Invoke-GoogleTranslate Configuration
	# ==========================================================================
	# Default output language for Invoke-GoogleTranslate (alias: translate).
	# When called without -InputLanguage, the source language is auto-detected.
	# When called without -OutputLanguage, the default below is used.
	#
	# Example:
	#   DefaultTranslateLanguages = @{
	#       OutputLanguage = "English"
	#   }
	#
	# Usage:
	#   translate kako si                                                           → "how are you"
	#   translate -InputLanguage English -OutputLanguage Croatian -Text hello world → "pozdrav svijete"
	# ==========================================================================
	DefaultTranslateLanguages     = @{
		OutputLanguage = "English"
	}

	# ==========================================================================
	# Window Module Configuration
	# ==========================================================================
	# Configuration for the Window module which provides "Tiling Window Manager"
	# functionality using FancyZones and virtual desktops.
	#
	# HOW WINDOW LAYOUTS WORK:
	# 1. FancyZones defines zone layouts (Zero through Nine) in custom-layouts.json
	# 2. Layout files (.psd1) in Layouts/{MachineType}/ define window placement
	# 3. Set-WorkspaceWindowLayout applies the layout when opening a workspace
	# 4. Windows are positioned to zones and snapped using FancyZones hotkeys
	#
	# LAYOUT FILE STRUCTURE (Layouts/{MachineType}/{Workspace}_{MachineType}.psd1):
	#   @{
	#       Monitors = @{
	#           Primary = @{
	#               VirtualDesktopLayouts = @{
	#                   1 = "One"    # Desktop 1 uses "One" layout (2 zones: Left, Right)
	#                   2 = "Eight"  # Desktop 2 uses "Eight" layout (5 zones)
	#               }
	#           }
	#           Secondary = @{
	#               VirtualDesktopLayouts = @{
	#                   1 = "Seven"  # Desktop 1 uses "Seven" layout (4 zones)
	#               }
	#           }
	#       }
	#       Layout = @(
	#           @{
	#               ProcessName   = "Code"
	#               WindowTitle   = "*Visual Studio Code"
	#               DesktopNumber = 1
	#               Zone          = "Right"
	#               Monitor       = "Primary"
	#           }
	#       )
	#   }
	#
	# CREATING A NEW LAYOUT:
	# 1. Create .psd1 file in Layouts/{MachineType}/ (e.g., MyWorkspace_PC.psd1)
	# 2. Define Monitors with VirtualDesktopLayouts mapping
	# 3. Define Layout array with window rules
	# 4. Run: Visualize-Layouts -Layout "MyWorkspace_PC" -Update
	#
	# VISUALIZING LAYOUTS:
	# - Visualize-Layouts                           # Interactive layout selection
	# - Visualize-Layouts -Layout "WinuX_PC"     # View specific layout
	# - Visualize-Layouts -All                      # View all layouts
	# - Visualize-Layouts -All -Update              # Update all layout files with ASCII art
	# - Visualize-Layouts -DisplayAvailableLayouts  # Show all FancyZones layouts and zones
	# ==========================================================================

	# Simple Layout Workspaces
	# Workspaces that only apply FancyZones layouts without window positioning.
	# Used by Set-WorkspaceWindowLayout to determine if a workspace is "simple".
	SimpleLayoutWorkspaces        = @("Fullscreen", "Empty")

	# ==========================================================================
	# Reset-Windows Defaults (Per Machine)
	# ==========================================================================
	# Per-machine defaults for Reset-Windows, the layout-testing wrapper that
	# collapses virtual desktops, consolidates all windows onto a single desktop
	# (and optional monitor), then centers them.
	#
	# Keyed by machine type. "Default" is used when the current machine type has
	# no entry. Explicit -VirtualDesktop / -Monitor parameters override these.
	#
	# Keys:
	# - VirtualDesktop : 1-based desktop to consolidate all windows onto.
	# - Monitor        : Target physical monitor for Move-Windows. Accepts a
	#                    1-based index ("2"), a label ("Primary"/"Secondary"), or
	#                    a device name. Leave "" to skip monitor targeting
	#                    (windows stay on their current monitor).
	#
	# Example: the Machine profile consolidates onto monitor 2; Test does no monitor
	# targeting since they are single-monitor.
	# ==========================================================================
	ResetAllWindowsDefaults       = @{
		Test    = @{ VirtualDesktop = 1; Monitor = "" }
		Default = @{ VirtualDesktop = 1; Monitor = "" }
	}

	# ==========================================================================
	# Center-Terminal Sizing (Dynamic, Live-Monitor-Aware)
	# ==========================================================================
	# Controls how Center-Terminal sizes the Windows Terminal when it re-centers
	# it on the primary monitor (Center-Terminal => Center-Windows). Kill-All is
	# the main caller - it re-centers the surviving terminal after cleanup.
	#
	# Goal: a terminal that is the SAME PHYSICAL SIZE on every display. Rather
	# than a fixed percentage (tiny on a small laptop panel, huge on an
	# ultrawide), Center-Terminal targets a fixed on-screen pixel size and
	# computes the width/height percentages from the LIVE primary monitor's work
	# area at run time. Reading the live monitor (not $global:MachineType) means
	# a docked laptop on a big external monitor and the same laptop undocked on
	# its own panel are handled correctly even though the machine type is identical.
	#
	# Keys:
	# - TargetWidthPx / TargetHeightPx : desired on-screen terminal size in px.
	#       Anchored to the ultrawide (3440x1440 work area ~3440x1400 => 1376x700,
	#       i.e. the legacy 40% x 50%), so the ultrawide is unchanged.
	# - Max*Percent : upper clamp; set high enough NOT to bind on common laptops
	#       so they reproduce the target size, while still capping a tiny panel.
	# - Min*Percent : lower clamp; guards against a degenerate window on an
	#       unexpectedly huge work area.
	#
	# Percentages are clamped to [Min, Max] and additionally to Center-Windows'
	# [10,100] ValidateRange. If this section is absent, Center-Terminal falls
	# back to the legacy 40% x 50%.
	# ==========================================================================
	CenterTerminalSizing          = @{
		TargetWidthPx    = 1376
		TargetHeightPx   = 700
		MinWidthPercent  = 25
		MaxWidthPercent  = 72
		MinHeightPercent = 35
		MaxHeightPercent = 75
	}

	# Layout Name to Number Mappings
	# Used by Apply-FancyZones to trigger keyboard shortcuts (Ctrl+Alt+Win+0-9)
	# The number corresponds to the FancyZones layout hotkey
	LayoutNumbers                 = @{
		"Zero"  = 0
		"One"   = 1
		"Two"   = 2
		"Three" = 3
		"Four"  = 4
		"Five"  = 5
		"Six"   = 6
		"Seven" = 7
		"Eight" = 8
		"Nine"  = 9
	}

	# ==========================================================================
	# Zone Name Mappings by Layout
	# ==========================================================================
	# Used by Get-FancyZone to map human-readable zone names to zone indices.
	# These names are used in layout .psd1 files for the "Zone" property.
	#
	# The zone indices come from FancyZones custom-layouts.json "cell-child-map".
	# Multiple names can map to the same index (e.g., "Left" and "Far-Left" → 0).
	#
	# HOW TO FIND ZONE INDICES:
	# 1. Open custom-layouts.json in Windows/FancyZones/
	# 2. Find your layout by name
	# 3. Look at the "cell-child-map" array - each number is a zone index
	# 4. Top row is first array, bottom row is second array
	#
	# Example from custom-layouts.json:
	#   cell-child-map: [
	#     [0, 1, 3],  ← TOP ROW (zones 0, 1, 3)
	#     [0, 2, 4]   ← BOTTOM ROW (zones 0, 2, 4)
	#   ]
	#
	#   This creates:
	#   ┌──────────┬──────────┬──────────┐
	#   │  Zone 0  │  Zone 1  │  Zone 3  │  ← TOP ROW
	#   │          ├──────────┼──────────┤
	#   │          │  Zone 2  │  Zone 4  │  ← BOTTOM ROW
	#   └──────────┴──────────┴──────────┘
	#      Left       Middle      Right
	#
	# Zone 0 spans both rows (tall left zone)
	# Zones 1 & 2 are stacked in middle
	# Zones 3 & 4 are stacked on right
	ZoneNameMappings              = @{
		"Zero"  = @{
			"Full"       = 0
			"Fullscreen" = 0
		}
		"One"   = @{
			"Left"  = 0
			"Right" = 1
		}
		"Two"   = @{
			"Left"   = 0
			"Middle" = 1
			"Right"  = 2
		}
		"Three" = @{
			"Far-Left"     = 0
			"Left"         = 0
			"Middle-Left"  = 1
			"Middle-Right" = 2
			"Far-Right"    = 3
			"Right"        = 3
		}
		"Four"  = @{
			"Top-Left"     = 0
			"Bottom-Left"  = 1
			"Top-Right"    = 2
			"Bottom-Right" = 3
		}
		"Five"  = @{
			"Left"  = 0
			"Right" = 1
		}
		"Six"   = @{
			"Left"         = 0
			"Top-Right"    = 1
			"Bottom-Right" = 2
		}
		"Seven" = @{
			"Left"         = 0
			"Middle"       = 1
			"Top-Right"    = 2
			"Bottom-Right" = 3
		}
		"Eight" = @{
			"Left"          = 0
			"Top-Middle"    = 1
			"Bottom-Middle" = 2
			"Top-Right"     = 3
			"Bottom-Right"  = 4
		}
		"Nine"  = @{
			"Top-Left"      = 0
			"Bottom-Left"   = 1
			"Top-Middle"    = 2
			"Bottom-Middle" = 3
			"Top-Right"     = 4
			"Bottom-Right"  = 5
		}
	}
}
