function Close-Window {
	<#
	.SYNOPSIS
		Asks a window to close by posting WM_CLOSE to its handle.

	.DESCRIPTION
		The one graceful-close seam in the repository. Posting WM_CLOSE needs neither focus nor
		synthesized input: the message goes straight to the handle, so the application runs its
		own close path (unsaved-changes prompts included) exactly as if the title-bar X had been
		clicked. Nothing here waits for the window to go away - pair it with Wait-WindowsClosed
		or Test-WindowVisible when the caller has to tell "closed" from "refused".

		Every closer used to carry its own compiled user32 PostMessage declaration
		(Close-Workspace, Close-Project, Rerun-LastCommand, the browser helper). They all post
		through WindowModule.Native now, so a test mocks this one function instead of Add-Type
		and never needs a handle that no real window can own.

	.PARAMETER Handle
		Window handle(s) to post WM_CLOSE to. A zero handle is skipped.

	.OUTPUTS
		[int] The number of handles the message was posted to.

	.EXAMPLE
		Close-Window -Handle $window.Handle
		Posts WM_CLOSE to one window.

	.EXAMPLE
		$windows | Close-Window
		Posts WM_CLOSE to every window object in the pipeline (their Handle property is bound).
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[AllowNull()]
		[IntPtr[]]$Handle
	)

	begin {
		$posted = 0
	}

	process {
		foreach ($target in $Handle) {
			if ($null -eq $target -or $target -eq [IntPtr]::Zero) {
				continue
			}
			if ([WindowModule.Native]::PostClose($target)) {
				$posted++
			}
		}
	}

	end {
		return $posted
	}
}
