function Show-Image {
	<#
	.SYNOPSIS
		Display an image file in a Windows Forms dialog.

	.DESCRIPTION
		Loads image from file path and displays in a PictureBox form window.
		Window size matches image dimensions. Useful for viewing wallpapers or screenshots.

	.PARAMETER ImagePath
		Full path to image file (.jpg, .png, .bmp, etc).

	.EXAMPLE
		Show-Image -ImagePath "C:\Wallpapers\Mountain.jpg"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$ImagePath
	)
	Add-WindowsFormsType -Quiet

	$ImageFileInfo = Get-Item -Path $ImagePath
	$Image = [Drawing.Image]::FromFile($ImageFileInfo)

	$PictureBox = [Windows.Forms.PictureBox]::new()
	$PictureBox.Size = $Image.Size
	$PictureBox.Image = $Image

	$Form = [Windows.Forms.Form]::new()
	$Form.Size = $Image.Size
	$Form.Controls.Add($PictureBox)
	$Form.ShowDialog()
}
