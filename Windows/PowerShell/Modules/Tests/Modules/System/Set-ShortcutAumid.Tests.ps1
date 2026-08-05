#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Set-ShortcutAumid.ps1")
}

Describe "Set-ShortcutAumid" {
	# These tests exercise the real shell COM plumbing on purpose - the property-store
	# round trip IS the function - but all shortcuts live and die inside TestDrive.
	It "creates the shortcut (parent folder included) and stamps the AUMID when TargetPath is given" {
		$linkPath = Join-Path "$TestDrive" "Pins\Stamped.lnk"
		$target = "$env:SystemRoot\System32\notepad.exe"

		Set-ShortcutAumid -LinkPath $linkPath -TargetPath $target -Aumid "WinuX.Test.App"

		Test-Path $linkPath | Should -BeTrue
		$shell = New-Object -ComObject WScript.Shell
		$shell.CreateShortcut($linkPath).TargetPath | Should -Be $target
		# Read the stamped identity back through the shell's property system.
		$item = (New-Object -ComObject Shell.Application).Namespace((Split-Path $linkPath)).ParseName((Split-Path $linkPath -Leaf))
		$item.ExtendedProperty("System.AppUserModel.ID") | Should -Be "WinuX.Test.App"
	}

	It "stamps an existing shortcut in place without TargetPath, keeping its target" {
		$linkPath = Join-Path "$TestDrive" "Existing.lnk"
		$target = "$env:SystemRoot\System32\notepad.exe"
		$shell = New-Object -ComObject WScript.Shell
		$shortcut = $shell.CreateShortcut($linkPath)
		$shortcut.TargetPath = $target
		$shortcut.Save()

		Set-ShortcutAumid -LinkPath $linkPath -Aumid "WinuX.Test.Existing"

		$item = (New-Object -ComObject Shell.Application).Namespace((Split-Path $linkPath)).ParseName((Split-Path $linkPath -Leaf))
		$item.ExtendedProperty("System.AppUserModel.ID") | Should -Be "WinuX.Test.Existing"
		# The target survives the property-store round trip.
		$shell.CreateShortcut($linkPath).TargetPath | Should -Be $target
	}

	It "throws when the shortcut is missing and no TargetPath was given" {
		{ Set-ShortcutAumid -LinkPath (Join-Path "$TestDrive" "Missing.lnk") -Aumid "X" } | Should -Throw "*does not exist*"
	}
}
