#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Import the module so the native WindowModule.RECT / WindowModule.Native types and
	# the dependent functions (Get-WindowHandle, Import-VirtualDesktopModule, ...) exist.
	Import-Module (Join-Path $ModuleRoot "Window\Window.psm1") -Force

	# Dot-source the function under test into script scope so plain Mock (no -ModuleName)
	# intercepts its internal calls, mirroring the rest of this file.
	. "$FunctionsPath\Confirm-WorkspaceWindowPositions.ps1"

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones the desktop check calls so Mock can attach (no-op where the module exists).
	if (-not (Get-Command Get-DesktopFromWindow -ErrorAction SilentlyContinue)) {
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
	}
	if (-not (Get-Command Get-DesktopIndex -ErrorAction SilentlyContinue)) {
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Confirm-WorkspaceWindowPositions" {
	BeforeEach {
		Mock Resolve-LayoutTokens { param([hashtable]$LayoutEntry) $LayoutEntry }
		Mock Clear-WindowCache { }
		# Skip the virtual-desktop preference branch - it requires a live VD module and only
		# triggers when more than one candidate survives matching, which these tests avoid.
		Mock Import-VirtualDesktopModule { $false }
	}

	It "rejects empty layout configuration" {
		{ Confirm-WorkspaceWindowPositions -LayoutConfig @() } | Should -Throw
	}

	Context "Title-drift fallback (non-browser caption recovery)" {
		# These entries use explicit X/Y/Width/Height so no FancyZone/monitor resolution is needed.
		# The recovered window carries a bogus handle, so GetWindowRect fails and the entry is
		# reported as "Handle invalid" - which proves a window WAS selected. An entry where no
		# window is selected is instead reported as "Window not found". That difference is what
		# distinguishes "fallback fired" from "fallback skipped".
		BeforeAll {
			$script:outlookLayout = @(
				@{
					ProcessName = "Olk"
					WindowTitle = "Mail - user@example.com - Outlook"
					X = 1722; Y = 2; Width = 1717; Height = 1437
				}
			)
		}

		It "recovers a sole non-browser process window when the caption no longer matches the title pattern" {
			# Strict title∩process matching finds nothing (caption drifted to 'Inbox - ...'),
			# but exactly one Olk window exists, so the fallback should adopt it.
			Mock Get-WindowHandle -ParameterFilter { $WindowTitle } { @() }
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9A001; Title = "Inbox - user@example.com - Outlook" })
			}

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $outlookLayout

			$result.Success | Should -BeFalse
			$result.Failures.Count | Should -Be 1
			# "Handle invalid" (not "Window not found") => a window was selected via the fallback.
			$result.Failures[0].Actual | Should -Be "Handle invalid"
			$result.Failures[0].WindowTitle | Should -BeLike "*Outlook*"
		}

		It "does not apply the fallback to browser processes" {
			# Browsers legitimately own many windows; the sole-window heuristic must not fire.
			Mock Get-WindowHandle -ParameterFilter { $WindowTitle } { @() }
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9B001; Title = "Some Page - Mozilla Firefox" })
			}

			$browserLayout = @(
				@{
					ProcessName = "firefox"
					WindowTitle = "Mail - user@example.com - Outlook"
					X = 1722; Y = 2; Width = 1717; Height = 1437
				}
			)

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $browserLayout

			$result.Success | Should -BeFalse
			$result.Failures[0].Actual | Should -Be "Window not found"
		}

		It "does not apply the fallback when multiple process windows are ambiguous" {
			Mock Get-WindowHandle -ParameterFilter { $WindowTitle } { @() }
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]0x9C001; Title = "Inbox - user@example.com - Outlook" }
					[PSCustomObject]@{ Handle = [IntPtr]0x9C002; Title = "Calendar - user@example.com - Outlook" }
				)
			}

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $outlookLayout

			$result.Success | Should -BeFalse
			$result.Failures[0].Actual | Should -Be "Window not found"
		}

		It "uses strict title∩process matching and never reaches the fallback when the caption matches" {
			# Control: when the configured title matches the live caption, the window is found
			# the normal way (and still reports 'Handle invalid' because the handle is bogus).
			$handle = [IntPtr]0x9D001
			Mock Get-WindowHandle -ParameterFilter { $WindowTitle } {
				@([PSCustomObject]@{ Handle = $handle; Title = "Mail - user@example.com - Outlook" })
			}
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = $handle; Title = "Mail - user@example.com - Outlook" })
			}

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $outlookLayout

			$result.Success | Should -BeFalse
			$result.Failures[0].Actual | Should -Be "Handle invalid"
		}
	}

	Context "Failure labelling" {
		# A token-expanded entry ("Browser") carries a process REGEX, not a process name, and
		# such entries often have no WindowTitle at all - so the layout-derived label reads
		# "(firefox|chrome|msedge|brave)", which names no window and repeats identically for
		# every browser entry in the layout. The failure must name the window instead.
		BeforeAll {
			$script:browserLayoutEntry = @(
				@{
					ProcessName = '(firefox|chrome|msedge|brave)'
					X = 2; Y = 2; Width = 1717; Height = 1437
				}
			)
		}

		It "reports the matched window's caption rather than the layout's process pattern" {
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9E001; Title = 'YouTube - Mozilla Firefox' })
			}

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $browserLayoutEntry

			$result.Failures.Count | Should -Be 1
			$result.Failures[0].WindowTitle | Should -Be 'YouTube - Mozilla Firefox'
			# The layout-entry identity is preserved separately, not lost.
			$result.Failures[0].LayoutEntry | Should -Be '(firefox|chrome|msedge|brave)'
			$result.Failures[0].ProcessName | Should -Be '(firefox|chrome|msedge|brave)'
		}

		It "falls back to the layout entry label when no window matched at all" {
			Mock Get-WindowHandle { @() }

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $browserLayoutEntry

			$result.Failures.Count | Should -Be 1
			$result.Failures[0].Actual | Should -Be 'Window not found'
			# Nothing better exists here - the pattern is genuinely all that is known.
			$result.Failures[0].WindowTitle | Should -Be '(firefox|chrome|msedge|brave)'
		}
	}

	Context "Virtual desktop of the matched window" {
		# A window at the right rect on the wrong desktop is not in place. The desktop used to be
		# consulted only to choose between several candidates, so a lone VS Code window that
		# appeared on the desktop the snap pass happened to be on, at the bounds VS Code itself
		# restored, verified as placed.
		BeforeAll {
			$script:codeLayout = @(
				@{
					ProcessName   = 'Code'
					DesktopNumber = 3
					X = 2; Y = 2; Width = 1717; Height = 1437
				}
			)
		}

		BeforeEach {
			Mock Import-VirtualDesktopModule { $true }
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9D001; Title = 'asseto - Visual Studio Code' })
			}
			Mock Get-DesktopFromWindow { 'desktop' }
		}

		It "fails an entry whose only window sits on another desktop, naming both desktops" {
			Mock Get-DesktopIndex { 3 }

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $codeLayout

			$result.Success | Should -BeFalse
			$result.Failures.Count | Should -Be 1
			$result.Failures[0].WindowTitle | Should -Be 'asseto - Visual Studio Code'
			$result.Failures[0].Handle | Should -Be ([IntPtr]0x9D001)
			$result.Failures[0].Actual | Should -Be 'On desktop 4'
			$result.Failures[0].Expected | Should -Match 'on desktop 3$'
		}

		It "accepts the window when it is on the expected desktop" {
			Mock Get-DesktopIndex { 2 }

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $codeLayout

			# A window WAS selected - the bogus handle only fails the rect read.
			$result.Failures[0].Actual | Should -Be 'Handle invalid'
		}

		It "applies the desktop offset of an alongside open" {
			Mock Get-DesktopIndex { 5 }

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $codeLayout -DesktopOffset 3

			$result.Failures[0].Actual | Should -Be 'Handle invalid'
		}

		It "keeps a window whose desktop cannot be resolved as a fallback" {
			Mock Get-DesktopFromWindow { throw 'RPC unavailable' }

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $codeLayout

			$result.Failures[0].Actual | Should -Be 'Handle invalid'
		}
	}

	Context "ExcludeWindowHandles (alongside scoping)" {
		# Alongside verification must judge only the windows THIS open created. A window that
		# was already on screen belongs to another workspace and was deliberately never
		# positioned, so matching one would either pass an entry nothing was placed for, or
		# steal the match from the entry's real window.
		BeforeAll {
			$script:excludeLayout = @(
				@{
					ProcessName = 'chrome'
					X = 2; Y = 2; Width = 1717; Height = 1437
				}
			)
		}

		It "never matches an excluded window" {
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9F001; Title = 'New Tab - Google Chrome' })
			}

			$excluded = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$excluded.Add([IntPtr]0x9F001)

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $excludeLayout -ExcludeWindowHandles $excluded

			$result.Success | Should -BeFalse
			# "Window not found" (not "Handle invalid") => no window was selected at all.
			$result.Failures[0].Actual | Should -Be 'Window not found'
		}

		It "still matches windows that are not excluded" {
			Mock Get-WindowHandle -ParameterFilter { $ProcessName -and -not $WindowTitle } {
				@([PSCustomObject]@{ Handle = [IntPtr]0x9F002; Title = 'New Tab - Google Chrome' })
			}

			$excluded = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$excluded.Add([IntPtr]0x9F001)

			$result = Confirm-WorkspaceWindowPositions -LayoutConfig $excludeLayout -ExcludeWindowHandles $excluded

			$result.Failures.Count | Should -Be 1
			# A window WAS selected - the bogus handle only fails the rect read.
			$result.Failures[0].Actual | Should -Be 'Handle invalid'
		}
	}
}
