#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-StackedWindowOrder.ps1"

	# Compile the native layer exactly as Window.psm1 does: the function raises windows through
	# [WindowModule.Native]::SetWindowPos.
	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		$nativePath = Join-Path $ModuleRoot "Window\WindowNative.cs"
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}

	# A static .NET call cannot be mocked, so the raised windows are real ones: hidden WinForms
	# forms owned by this process. Their handles exist without ever being shown, SetWindowPos
	# with HWND_TOP / no move / no size / no activation succeeds on them, and nothing on screen
	# changes. Their relative Z-order is read back with GetWindow(GW_HWNDNEXT).
	Add-Type -AssemblyName System.Windows.Forms
	if (-not ([System.Management.Automation.PSTypeName]'StackedWindowOrderTest.ZOrder').Type) {
		Add-Type -Namespace StackedWindowOrderTest -Name ZOrder -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetWindow(System.IntPtr hWnd, uint uCmd);
'@
	}

	$script:TestForms = @()
	foreach ($name in 'First', 'Second', 'Third') {
		$form = New-Object System.Windows.Forms.Form
		$form.Text = "Set-StackedWindowOrder $name"
		$script:TestForms += $form
	}
	$script:HandleA = $script:TestForms[0].Handle
	$script:HandleB = $script:TestForms[1].Handle
	$script:HandleC = $script:TestForms[2].Handle

	# Whether $Upper sits above $Lower in the Z-order (walking down from $Upper reaches $Lower).
	function Test-WindowAbove {
		param([IntPtr]$Upper, [IntPtr]$Lower)
		$current = $Upper
		for ($step = 0; $step -lt 100000; $step++) {
			$current = [StackedWindowOrderTest.ZOrder]::GetWindow($current, 2)
			if ($current -eq [IntPtr]::Zero) { return $false }
			if ($current -eq $Lower) { return $true }
		}
		return $false
	}

	# Whether this session can observe a Z-order change at all: raise A then B directly, then the
	# other way round. Some test hosts (a worker without an interactive desktop) report success
	# from SetWindowPos without the order being readable back; the two ordering tests are skipped
	# there instead of failing on something the function does not control.
	$probeFlags = [WindowModule.Native]::SWP_NOMOVE -bor [WindowModule.Native]::SWP_NOSIZE -bor [WindowModule.Native]::SWP_NOACTIVATE
	[void][WindowModule.Native]::SetWindowPos($script:HandleA, [IntPtr]::Zero, 0, 0, 0, 0, $probeFlags)
	[void][WindowModule.Native]::SetWindowPos($script:HandleB, [IntPtr]::Zero, 0, 0, 0, 0, $probeFlags)
	$script:ZOrderObservable = Test-WindowAbove -Upper $script:HandleB -Lower $script:HandleA
	[void][WindowModule.Native]::SetWindowPos($script:HandleA, [IntPtr]::Zero, 0, 0, 0, 0, $probeFlags)
	$script:ZOrderObservable = $script:ZOrderObservable -and (Test-WindowAbove -Upper $script:HandleA -Lower $script:HandleB)

	function New-ResultRow {
		param($Handle, [string]$Zone = 'Fullscreen', $LayoutOrder, [string]$Status = 'Configured', [int]$Desktop = 1, [string]$Monitor = 'Primary', [string]$Title = 'Window')
		[PSCustomObject]@{
			Status         = $Status
			Handle         = $Handle
			ZoneName       = $Zone
			LayoutOrder    = $LayoutOrder
			DesktopDisplay = $Desktop
			MonitorLabel   = $Monitor
			WindowTitle    = $Title
		}
	}
}

AfterAll {
	foreach ($form in @($script:TestForms)) { if ($form) { $form.Dispose() } }
}

Describe "Set-StackedWindowOrder" {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "raises the windows of a zone shared by several entries in layout order, the last entry on top" {
		if (-not $script:ZOrderObservable) { Set-ItResult -Skipped -Because "this test host does not expose Z-order changes of hidden windows"; return }
		# Rows arrive out of layout order; the entry with the highest LayoutOrder ends on top.
		$rows = @(
			New-ResultRow -Handle $script:HandleB -LayoutOrder 2
			New-ResultRow -Handle $script:HandleC -LayoutOrder 0
			New-ResultRow -Handle $script:HandleA -LayoutOrder 1
		)

		$raised = Set-StackedWindowOrder -Results $rows

		$raised | Should -Be 3
		Test-WindowAbove -Upper $script:HandleB -Lower $script:HandleA | Should -BeTrue
		Test-WindowAbove -Upper $script:HandleA -Lower $script:HandleC | Should -BeTrue
	}

	It "follows the layout order again when it is reversed" {
		if (-not $script:ZOrderObservable) { Set-ItResult -Skipped -Because "this test host does not expose Z-order changes of hidden windows"; return }
		$rows = @(
			New-ResultRow -Handle $script:HandleB -LayoutOrder 0
			New-ResultRow -Handle $script:HandleC -LayoutOrder 2
			New-ResultRow -Handle $script:HandleA -LayoutOrder 1
		)

		$null = Set-StackedWindowOrder -Results $rows

		Test-WindowAbove -Upper $script:HandleC -Lower $script:HandleA | Should -BeTrue
		Test-WindowAbove -Upper $script:HandleA -Lower $script:HandleB | Should -BeTrue
	}

	It "leaves a zone filled by a single entry alone" {
		# One catch-all entry placed several windows in one zone: their order is not configured.
		$rows = @(
			New-ResultRow -Handle $script:HandleA -LayoutOrder 4
			New-ResultRow -Handle $script:HandleB -LayoutOrder 4
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 0
	}

	It "groups by desktop, monitor and zone, so entries in different zones never stack" {
		$rows = @(
			New-ResultRow -Handle $script:HandleA -LayoutOrder 0 -Zone 'Left'
			New-ResultRow -Handle $script:HandleB -LayoutOrder 1 -Zone 'Right'
			New-ResultRow -Handle $script:HandleC -LayoutOrder 2 -Zone 'Left' -Desktop 2
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 0
	}

	It "raises a window listed twice in one zone only once" {
		$rows = @(
			New-ResultRow -Handle $script:HandleA -LayoutOrder 0
			New-ResultRow -Handle $script:HandleA -LayoutOrder 1
			New-ResultRow -Handle $script:HandleB -LayoutOrder 2
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 2
	}

	It "ignores rows that are not Configured or lack a handle, a zone or a layout order" {
		# Only A and B qualify; every other row would otherwise make the zone a shared one.
		$rows = @(
			New-ResultRow -Handle $script:HandleA -LayoutOrder 0
			New-ResultRow -Handle $script:HandleB -LayoutOrder 1
			New-ResultRow -Handle $script:HandleC -LayoutOrder 2 -Status 'Not Found'
			New-ResultRow -Handle $null -LayoutOrder 3
			New-ResultRow -Handle ([IntPtr]::Zero) -LayoutOrder 4
			New-ResultRow -Handle $script:HandleC -LayoutOrder 5 -Zone ''
			New-ResultRow -Handle $script:HandleC -LayoutOrder $null
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 2
	}

	It "returns 0 when fewer than two rows qualify" {
		$rows = @(
			New-ResultRow -Handle $script:HandleA -LayoutOrder 0
			New-ResultRow -Handle $script:HandleB -LayoutOrder 1 -Status 'Not Found'
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 0
	}

	It "returns 0 for no rows at all" {
		Set-StackedWindowOrder -Results @() | Should -Be 0
		Set-StackedWindowOrder -Results $null | Should -Be 0
	}

	It "does not count a window SetWindowPos cannot raise" {
		# A handle that is no window: SetWindowPos fails, nothing is counted, nothing throws.
		$rows = @(
			New-ResultRow -Handle ([IntPtr]0x7FFF0001) -LayoutOrder 0
			New-ResultRow -Handle $script:HandleA -LayoutOrder 1
		)

		Set-StackedWindowOrder -Results $rows | Should -Be 1
	}
}
