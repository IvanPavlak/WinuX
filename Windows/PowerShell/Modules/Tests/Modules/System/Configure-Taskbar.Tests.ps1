#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Configure-Taskbar.ps1"
	# Dot-source the AUMID stamper so the Aumid-row tests can mock it instead of hitting COM.
	. "$FunctionsPath\Set-ShortcutAumid.ps1"
	# Dot-source the machine-scope gate and machine-type resolver so both are mockable here,
	# regardless of whether the imported Bootstrap module in this session already exports them.
	. (Join-Path $ModuleRoot "Bootstrap\Functions\Test-MachineTypeScope.ps1")
	. (Join-Path $ModuleRoot "Bootstrap\Functions\DetermineMachineType.ps1")
}

Describe "Configure-Taskbar" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Universal            = [PSCustomObject]@{ TaskbarPinFolder = "C:\\Temp\\TaskbarPins" }
			TaskbarConfiguration = $null
		}
		$global:MachineSpecificPaths = [PSCustomObject]@{
			TaskbarLayoutFile = "C:\\Temp\\taskbar_layout.xml"
		}

		Mock Test-AdminPrivileges { }
		Mock Unpin-TaskbarApps { }
		Mock Test-Path { $false }
		# An existing real layout file is backed up via Backup-RepositoryItem before the
		# overwrite; stub it so no test can ever write into the real repository's Backups sink
		# (TestDrive persists across Its, so a second write finds the first one's file).
		Mock Backup-RepositoryItem { Join-Path "$TestDrive" "BackupSink" }
		Mock Loading-Spinner { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock DetermineMachineType { "Test" }
	}

	It "returns without touching anything when TaskbarConfiguration is missing" {
		{ Configure-Taskbar } | Should -Not -Throw

		# The guard sits BEFORE the destructive unpin/clear calls: an unconfigured
		# taskbar must survive a vanilla run exactly as the user arranged it.
		Should -Invoke Unpin-TaskbarApps -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "TaskbarConfiguration not configured" }
	}

	It "returns without touching anything when TaskbarConfiguration is an empty array" {
		$script:Configuration.TaskbarConfiguration = @()

		{ Configure-Taskbar } | Should -Not -Throw

		Should -Invoke Unpin-TaskbarApps -Times 0
	}

	Context "machine-type filtering" {
		BeforeEach {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "AllApp"; Type = "AUMID"; Value = "App.All"; Machine = "All" }
				@{ Name = "TestApp"; Type = "AUMID"; Value = "App.Test"; Machine = "Test" }
				@{ Name = "PcApp"; Type = "AUMID"; Value = "App.Pc"; Machine = "PC" }
				@{ Name = "UntaggedApp"; Type = "AUMID"; Value = "App.Untagged" }
			)

			# Write the layout XML into Pester's TestDrive so the generated pin list can be read
			# back, and stub the registry boundary. -FromBootstrap skips the lock/restart tail.
			$global:MachineSpecificPaths = [PSCustomObject]@{ TaskbarLayoutFile = (Join-Path "$TestDrive" "taskbar_layout.xml") }
			Mock New-Item { }
			Mock Set-ItemProperty { }
		}

		It "resolves the machine type and routes every row through Test-MachineTypeScope" {
			Mock Test-MachineTypeScope { $true }

			Configure-Taskbar -FromBootstrap

			Should -Invoke DetermineMachineType -Times 1
			Should -Invoke Test-MachineTypeScope -Times 4 -Exactly
		}

		It "defaults a row without a Machine key to the All scope" {
			Mock Test-MachineTypeScope { $true }

			Configure-Taskbar -FromBootstrap

			# Only the untagged row must be queried with the "All" fallback scope.
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter {
				$Scope -eq "All" -and $Context -eq "TaskbarConfiguration [UntaggedApp]"
			}
			# The tagged rows are queried with their own declared scope.
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter {
				$Scope -eq "PC" -and $Context -eq "TaskbarConfiguration [PcApp]"
			}
		}

		It "pins only rows whose Machine scope matches the current machine type" {
			# Simulate the gate: "All" or a scope naming the current machine type matches.
			Mock Test-MachineTypeScope {
				$Scope -eq "All" -or (($Scope -split "/" | ForEach-Object { $_.Trim() }) -contains $MachineType)
			}

			Configure-Taskbar -FromBootstrap

			# App.All ("All"), App.Test ("Test") and App.Untagged (defaulted to "All") match the
			# "Test" machine; App.Pc ("PC") does not and must be absent from the written layout.
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match "App\.All"
			$layout | Should -Match "App\.Test"
			$layout | Should -Match "App\.Untagged"
			$layout | Should -Not -Match "App\.Pc"
		}

		It "removes a pre-existing symlink at the layout path before writing" {
			Mock Test-MachineTypeScope { $true }
			# Simulate a leftover symlink from the old design sitting at the layout path.
			Mock Get-Item { [PSCustomObject]@{ LinkType = "SymbolicLink" } } -ParameterFilter { "$LiteralPath" -like "*taskbar_layout.xml" }
			Mock Remove-Item { }

			Configure-Taskbar -FromBootstrap

			Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { "$LiteralPath" -like "*taskbar_layout.xml" }
			# A symlink carries no content of its own - it is removed, never backed up.
			Should -Invoke Backup-RepositoryItem -Times 0
		}

		It "backs a pre-existing real layout file up before overwriting it" {
			Mock Test-MachineTypeScope { $true }
			Set-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Value "<hand-pinned/>" -NoNewline

			Configure-Taskbar -FromBootstrap

			Should -Invoke Backup-RepositoryItem -Times 1 -Exactly -ParameterFilter {
				$Category -eq "System" -and $Key -eq "TaskbarLayout"
			}
		}

		It "skips the layout write when the backup cannot be taken" {
			Mock Test-MachineTypeScope { $true }
			Mock Backup-RepositoryItem { throw "access denied" }
			Set-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Value "<hand-pinned/>" -NoNewline

			Configure-Taskbar -FromBootstrap

			# The layout that could not be saved is never replaced.
			Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw | Should -Be "<hand-pinned/>"
		}
	}

	Context "AUMID-stamped Path rows" {
		BeforeEach {
			$global:MachineSpecificPaths = [PSCustomObject]@{ TaskbarLayoutFile = (Join-Path "$TestDrive" "taskbar_layout.xml") }
			Mock New-Item { }
			Mock Set-ItemProperty { }
			Mock Test-MachineTypeScope { $true }
			Mock Set-ShortcutAumid { }
		}

		It "pins an exe row with an Aumid through a generated, stamped TaskbarPins shortcut" {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "DBeaver"; Type = "Path"; Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Aumid = "DBeaver" }
			)

			Configure-Taskbar -FromBootstrap

			$expectedShortcut = Join-Path (Join-Path "$TestDrive" "TaskbarPins") "DBeaver.lnk"
			# The shortcut is generated from the resolved exe path and stamped with the identity.
			Should -Invoke Set-ShortcutAumid -Times 1 -Exactly -ParameterFilter {
				$LinkPath -eq $expectedShortcut -and $TargetPath -like "*\AppData\Local\DBeaver\dbeaver.exe" -and $Aumid -eq "DBeaver"
			}
			# The layout pins the stamped shortcut, not the raw exe.
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match ([regex]::Escape("DesktopApplicationLinkPath=`"$expectedShortcut`""))
			$layout | Should -Not -Match ([regex]::Escape("dbeaver.exe"))
		}

		It "stamps a .lnk row with an Aumid in place instead of generating a shortcut" {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "SomeApp"; Type = "Path"; Value = "C:\Apps\SomeApp.lnk"; Aumid = "Some.App" }
			)

			Configure-Taskbar -FromBootstrap

			Should -Invoke Set-ShortcutAumid -Times 1 -Exactly -ParameterFilter {
				$LinkPath -eq "C:\Apps\SomeApp.lnk" -and -not $TargetPath -and $Aumid -eq "Some.App"
			}
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match ([regex]::Escape("DesktopApplicationLinkPath=`"C:\Apps\SomeApp.lnk`""))
		}

		It "falls back to pinning the raw path with a warning when stamping fails" {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "DBeaver"; Type = "Path"; Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Aumid = "DBeaver" }
			)
			Mock Set-ShortcutAumid { throw "COM says no" }

			Configure-Taskbar -FromBootstrap

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "Could not stamp AUMID \[DBeaver\]" }
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match ([regex]::Escape("\AppData\Local\DBeaver\dbeaver.exe"))
		}

		It "leaves a plain Path row without an Aumid untouched" {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "PlainApp"; Type = "Path"; Value = "C:\Apps\plain.exe" }
			)

			Configure-Taskbar -FromBootstrap

			Should -Invoke Set-ShortcutAumid -Times 0
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match ([regex]::Escape("DesktopApplicationLinkPath=`"C:\Apps\plain.exe`""))
		}
	}

	# Explorer applies a taskbar layout asynchronously for seconds after it starts and records the
	# layout file's timestamp so an unchanged file is never re-applied, which makes any restart
	# landing mid-apply a permanent truncation of the pins. The interactive path is therefore
	# ordered so exactly one bounce precedes the layout and the final restart is never followed by
	# another - these tests pin that ordering, which -FromBootstrap skips entirely.
	Context "Explorer restart ordering (interactive path)" {
		BeforeEach {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "AllApp"; Type = "AUMID"; Value = "App.All"; Machine = "All" }
			)
			$global:MachineSpecificPaths = [PSCustomObject]@{ TaskbarLayoutFile = (Join-Path "$TestDrive" "taskbar_layout.xml") }
			Mock New-Item { }
			Mock Set-ItemProperty { }
			Mock Test-MachineTypeScope { $true }

			# Every Explorer-touching step appends to one list, so the assertions can check order
			# and not merely that each was called. File existence is probed through .NET rather
			# than Test-Path, which the outer BeforeEach mocks to a blanket $false.
			$script:steps = [System.Collections.Generic.List[string]]::new()
			Mock Unpin-TaskbarApps { $script:steps.Add("Unpin(Skip=$([bool]$SkipExplorerRestart))") }
			Mock Rebuild-IconCache {
				$script:steps.Add("Rebuild(layoutWritten=$([System.IO.File]::Exists($global:MachineSpecificPaths.TaskbarLayoutFile)))")
			}
			Mock Restart-Explorer { $script:steps.Add("Restart(Delay=$Delay)") }
			# The interactive path clears the real HKCU marker; mock it so a test run cannot
			# disturb the machine's actual taskbar state.
			Mock Remove-ItemProperty { $script:steps.Add("ClearMarker") }
		}

		It "bounces Explorer once before the layout and restarts it last" {
			Configure-Taskbar

			# The rebuild is the single pre-layout bounce, so Unpin must not add one of its own,
			# and the rebuild must land while the layout file is still unwritten.
			$script:steps[0] | Should -Be "Unpin(Skip=True)"
			$script:steps[1] | Should -Be "Rebuild(layoutWritten=False)"
			# Nothing may touch Explorer after the final restart - that instance is the one that
			# has to finish applying the pins.
			$script:steps[-1] | Should -Be "Restart(Delay=8)"
			Should -Invoke Rebuild-IconCache -Times 1 -Exactly
			Should -Invoke Restart-Explorer -Times 1 -Exactly
		}

		It "clears the applied-layout marker immediately before the final restart" {
			Configure-Taskbar

			# Explorer skips a layout whose timestamp it already recorded, so the marker has to be
			# gone before the restart that is expected to apply it.
			$script:steps[-2] | Should -Be "ClearMarker"
			Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
				$Name -eq "LayoutXMLLastModified" -and "$Path" -like "*\Explorer\Taskband"
			}
		}
	}
}
