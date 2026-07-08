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
}
