#
# iso Rescue v1.00 - Rescue & Diagnostics ISO Downloader
# Based on Fido by Pete Batard <pete@akeo.ie>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#region Parameters
param(
	# (Optional) Application window title
	[string]$AppTitle = "isoRescue - Rescue & Diagnostics ISO Downloader",
	# (Optional) Pipe-separated localization strings
	[string]$LocData,
	# (Optional) Interface locale override (e.g. "en-US", "pl-PL")
	[string]$Locale,
	# (Optional) Path to icon file
	[string]$Icon,
	# (Optional) Named pipe to send the URL to (e.g. Rufus integration)
	[string]$PipeName,
	# (Optional) Rescue category or tool ("Hiren", "SystemRescue", "Rescuezilla", "Clonezilla", "GParted", "Kaspersky", "MemTest") [CLI mode]
	[Alias("Tool", "Name")][string]$ToolName,
	# (Optional) Tool version or release [CLI mode]
	[Alias("Ver", "Rel")][string]$Version,
	# (Optional) Tool edition or flavor [CLI mode]
	[Alias("Ed", "Flavor")][string]$Edition,
	# (Optional) Architecture [CLI mode]
	[string]$Arch,
	# (Optional) Return download URL only [CLI mode]
	[switch]$GetUrl = $false,
	# (Optional) Download file directly to disk in CLI mode
	[switch]$Download = $false,
	# (Optional) Verify SHA256 checksum after download
	[switch]$Verify = $false,
	# (Optional) Do not hide console window when launching GUI
	[switch]$NoConsoleHide = $false,
	# (Optional) Verbose output
	[switch]$Verbose = $false,
	# (Optional) Debug information
	[switch]$Debug = $false
)
#endregion


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $PSScriptRoot 'isoCommon.psm1') -Force
try {
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$Script:Version = "1.2.0"

$Cmd = $false
if ($ToolName -or $Version -or $Edition -or $Arch -or $GetUrl -or $Download) {
	$Cmd = $true
}

# Default interface locale to en-US unless specified
if (!$Locale) {
	$Locale = "en-US"
}

function Get-Platform-Version()
{
	$version = 0.0
	$platform = [string][System.Environment]::OSVersion.Platform
	if ($platform.StartsWith("Win")) {
		$version = [System.Environment]::OSVersion.Version.Major * 1.0 + [System.Environment]::OSVersion.Version.Minor * 0.1
	}
	return $version
}

$winver = Get-Platform-Version

# Force TLS 1.2 for older Windows versions
if ($winver -lt 10.0) {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
}

#region Assembly Types
$Drawing_Assembly = "System.Drawing"
if ($host.version -ge "7.0") {
	$Drawing_Assembly += ".Common"
}

$Signature = @{
	Namespace            = "WinAPI"
	Name                 = "Utils"
	Language             = "CSharp"
	UsingNamespace       = "System.Runtime", "System.IO", "System.Text", "System.Drawing", "System.Globalization"
	ReferencedAssemblies = $Drawing_Assembly
	ErrorAction          = "Stop"
	WarningAction        = "Ignore"
	IgnoreWarnings       = $true
	MemberDefinition     = @"
		[DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true, BestFitMapping = false, ThrowOnUnmappableChar = true)]
		internal static extern int ExtractIconEx(string sFile, int iIndex, out IntPtr piLargeVersion, out IntPtr piSmallVersion, int amountIcons);

		[DllImport("user32.dll")]
		public static extern bool ShowWindow(IntPtr handle, int state);

		public static Icon ExtractIcon(string file, int number, bool largeIcon) {
			IntPtr large, small;
			ExtractIconEx(file, number, out large, out small, 1);
			try {
				return Icon.FromHandle(largeIcon ? large : small);
			} catch {
				return null;
			}
		}
"@
}

if (!$Cmd) {
	if (!("WinAPI.Utils" -as [type])) {
		Add-Type @Signature
	}
	Add-Type -AssemblyName PresentationFramework

	if (!$NoConsoleHide) {
		# Hide console window in background (unless -NoConsoleHide is passed)
		try {
			[WinAPI.Utils]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0) | Out-Null
		} catch {}
	}
}
#endregion

#region Rescue & Diagnostics Catalog
$RescueCatalog = @(
	[PSCustomObject]@{
		Name     = "Hiren's BootCD PE"
		Code     = "hiren"
		Category = "Windows PE Emergency Environment"
		Versions = @(
			[PSCustomObject]@{
				Name     = "HBCD PE x64 (Windows 11 PE Based - Latest)"
				Code     = "latest"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Full Edition (Diagnostic & Recovery Suite)"
						Code  = "full"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (64-bit)"; Arch = "x64"; Url = "https://www.hirensbootcd.org/files/HBCD_PE_x64.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "SystemRescue"
		Code     = "systemrescue"
		Category = "Linux Sysadmin & Repair Environment"
		Versions = @(
			[PSCustomObject]@{
				Name     = "SystemRescue 13.02 (Arch-based - Latest Stable)"
				Code     = "13.02"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Standard Live System"
						Code  = "standard"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (amd64)"; Arch = "amd64"; Url = "https://fastly-cdn.system-rescue.org/releases/13.02/systemrescue-13.02-amd64.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "Rescuezilla"
		Code     = "rescuezilla"
		Category = "Easy GUI Disk Cloning & Imaging"
		Versions = @(
			[PSCustomObject]@{
				Name     = "Rescuezilla 2.5.1 (Ubuntu Noble Based)"
				Code     = "2.5.1"
				Editions = @(
					[PSCustomObject]@{
						Name  = "GUI Live Suite"
						Code  = "gui"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (64-bit)"; Arch = "x64"; Url = "https://github.com/rescuezilla/rescuezilla/releases/download/2.5.1/rescuezilla-2.5.1-64bit.noble.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "Clonezilla Live"
		Code     = "clonezilla"
		Category = "Advanced Bare-Metal Partition & Disk Cloning"
		Versions = @(
			[PSCustomObject]@{
				Name     = "Clonezilla Live Stable"
				Code     = "stable"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Debian-based Stable"
						Code  = "debian"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (amd64)"; Arch = "amd64"; Url = "https://free.nchc.org.tw/clonezilla-live/stable/clonezilla-live-3.3.3-37-amd64.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "GParted Live"
		Code     = "gparted"
		Category = "Disk Partitioning & Filesystem Resizing"
		Versions = @(
			[PSCustomObject]@{
				Name     = "GParted Live Stable"
				Code     = "stable"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Standard Live Edition"
						Code  = "standard"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (amd64)"; Arch = "amd64"; Url = "https://free.nchc.org.tw/gparted-live/stable/gparted-live-1.8.1-3-amd64.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "Kaspersky Rescue Disk"
		Code     = "kaspersky"
		Category = "Offline Antivirus & Rootkit Cleaner"
		Versions = @(
			[PSCustomObject]@{
				Name     = "Kaspersky Rescue Disk Live"
				Code     = "krd"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Updatable Live ISO"
						Code  = "live"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 / x86 Hybrid"; Arch = "hybrid"; Url = "https://rescuedisk.s.kaspersky-labs.com/updatable/2018/krd.iso" }
						)
					}
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "MemTest86+"
		Code     = "memtest"
		Category = "Hardware RAM Diagnostics"
		Versions = @(
			[PSCustomObject]@{
				Name     = "MemTest86+ v9.00 (Latest Official)"
				Code     = "9.00"
				Editions = @(
					[PSCustomObject]@{
						Name  = "Bootable ISO Package"
						Code  = "iso"
						Archs = @(
							[PSCustomObject]@{ Name = "x86_64 (UEFI / BIOS)"; Arch = "x64"; Url = "https://www.memtest.org/download/v9.00/mt86plus_9.00_x86_64.iso.zip" }
						)
					}
				)
			}
		)
	}
)
#endregion

#region Globals
$ErrorActionPreference = "Stop"
$DefaultTimeout = 30
$dh = 58
$Stage = 0
$SelectedIndex = 0
$MaxStage = 4
$ExitCode = 100

$Verbosity = 1
if ($Debug) {
	$Verbosity = 5
} elseif ($Verbose) {
	$Verbosity = 2
} elseif ($Cmd -and $GetUrl) {
	$Verbosity = 0
}
#endregion

#region Localization
$EnglishMessages = "en-US|Tool|Version|Edition|Architecture|Download|Continue|Back|Close|Cancel|Error|Please wait...|" +
	"Download using a browser|Download is unavailable.|" +
	"PowerShell 3.0 or later is required to run this script.|Do you want to go online and download it?|" +
	"This feature is not available on this platform."

$PolishMessages = "pl-PL|NarzÄ™dzie|Wersja|Edycja|Architektura|Pobierz|Dalej|Wstecz|Zamknij|Anuluj|BĹ‚Ä…d|ProszÄ™ czekaÄ‡...|" +
	"Pobierz za pomocÄ… przeglÄ…darki|Pobieranie jest niedostÄ™pne.|" +
	"Wymagany jest PowerShell 3.0 lub nowszy.|Czy chcesz pobraÄ‡ go z sieci?|" +
	"Ta funkcja nie jest dostÄ™pna na tej platformie."

[string[]]$English = $EnglishMessages.Split('|')
[string[]]$Polish = $PolishMessages.Split('|')

[string[]]$Localized = $null
if ($LocData) {
	$Localized = $LocData.Split('|')
} elseif ($Locale -and $Locale.StartsWith("pl")) {
	$Localized = $Polish
} else {
	$Localized = $English
}

function Get-Translation([string]$Text)
{
	for ($i = 0; $i -lt $English.Length; $i++) {
		if ($English[$i] -eq $Text) {
			if ($Localized -and $Localized[$i]) {
				return $Localized[$i]
			}
			return $English[$i]
		}
	}
	return $Text
}
#endregion

#region Helper Functions
function ConvertTo-ImageSource
{
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[System.Drawing.Icon]$Icon
	)

	Process {
		foreach ($i in $Icon) {
			[System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
				$i.Handle,
				(New-Object System.Windows.Int32Rect -Args 0,0,$i.Width, $i.Height),
				[System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
			)
		}
	}
}

function Size-To-Human-Readable([uint64]$size)
{
	$suffix = "bytes", "KB", "MB", "GB", "TB"
	$i = 0
	while ($size -gt 1kb -and $i -lt $suffix.Length - 1) {
		$size = $size / 1kb
		$i++
	}
	"{0:N1} {1}" -f $size, $suffix[$i]
}

function Get-Url-Size([string]$Url)
{
	try {
		$req = [System.Net.HttpWebRequest]::Create($Url)
		$req.Method = "HEAD"
		$req.Timeout = 8000
		$req.AllowAutoRedirect = $true
		$req.UserAgent = "Mozilla/5.0"
		$res = $req.GetResponse()
		$len = [uint64]$res.ContentLength
		$res.Close()
		if ($len -gt 0) {
			return (Size-To-Human-Readable $len)
		}
	} catch {}
	return $null
}

function Error([string]$ErrorMessage)
{
	Write-Host "Error: $ErrorMessage"
	if (!$Cmd) {
		$XMLForm.Title = $(Get-Translation("Error")) + ": " + $ErrorMessage
		Refresh-Control($XMLForm)
		$XMLGrid.Children[2 * $script:Stage + 1].IsEnabled = $true
		[System.Windows.MessageBox]::Show($ErrorMessage, $(Get-Translation("Error")), "OK", "Error") | Out-Null
		$script:ExitCode = $script:Stage--
	} else {
		$script:ExitCode = 2
	}
}

function Send-Message([string]$PipeName, [string]$Message)
{
	[System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
	$Pipe = New-Object -TypeName System.IO.Pipes.NamedPipeClientStream -ArgumentList ".", $PipeName, ([System.IO.Pipes.PipeDirection]::Out), ([System.IO.Pipes.PipeOptions]::None), ([System.Security.Principal.TokenImpersonationLevel]::Impersonation)
	try {
		$Pipe.Connect(1500)
		$bRequest = $Encoding.GetBytes($Message)
		$Pipe.Write($bRequest, 0, $bRequest.Length)
		$Pipe.Dispose()
	} catch {
		Write-Host $_.Exception.Message
	}
}

function Process-Download-Link([string]$Url, [string]$FileName = "")
{
	try {
		if ($PipeName -and !$Check.IsChecked) {
			Send-Message -PipeName $PipeName -Message $Url
			return 0
		}

		if (!$FileName) {
			$FileName = ($Url.Split('?')[0]).Split('/')[-1]
		}

		if ($Cmd -and $Download) {
			Write-Host "Downloading '$FileName' from official source..."
			$Size = Get-Url-Size $Url
			if ($Size) {
				Write-Host "File size: $Size"
			}
			Invoke-IsoDownload -Source $Url -Destination $FileName -DisplayName "Rescue Tool Download" -UserAgent "Mozilla/5.0" | Out-Null
			Write-Host "Download complete: $FileName"

			if ($Verify -and (Test-Path $FileName)) {
				Write-Host "Calculating SHA256 checksum..."
				$hash = (Get-FileHash -Path $FileName -Algorithm SHA256).Hash
				Write-Host "SHA256: $hash"
			}
		} else {
			Write-Host "Download URL: $Url"
			Start-Process -FilePath $Url
		}
	} catch {
		Error($_.Exception.Message)
		return 404
	}
	return 0
}
#endregion

#region CLI Mode
if ($Cmd) {
	# Platform check
	if ($winver -le 6.1) {
		Error(Get-Translation("This feature is not available on this platform."))
		exit 403
	}

	# 1. Tool Selection (-ToolName / -Tool / -Name)
	if ($ToolName -eq "List") {
		Write-Host "Available Rescue & Diagnostic Tools (-Tool):"
		foreach ($t in $RescueCatalog) {
			Write-Host " - $($t.Name) [Code: $($t.Code)] ($($t.Category))"
		}
		exit 0
	}

	$selectedToolObj = $null
	if ($ToolName) {
		foreach ($t in $RescueCatalog) {
			if ($t.Name -match $ToolName -or $t.Code -match $ToolName) {
				$selectedToolObj = $t
				break
			}
		}
	} else {
		$selectedToolObj = $RescueCatalog[0]
		if ($Verbosity -ge 1) {
			Write-Host "No tool specified (-Tool). Defaulting to '$($selectedToolObj.Name)'."
		}
	}

	if ($selectedToolObj -eq $null) {
		Write-Host "Invalid rescue tool."
		Write-Host "Use '-Tool List' to view available tools."
		exit 1
	}

	# 2. Version Selection (-Version / -Rel / -Ver)
	if ($Version -eq "List") {
		Write-Host "Available versions for $($selectedToolObj.Name) (-Ver):"
		foreach ($v in $selectedToolObj.Versions) {
			Write-Host " - $($v.Name) [Code: $($v.Code)]"
		}
		exit 0
	}

	$selectedVersionObj = $null
	if ($Version) {
		foreach ($v in $selectedToolObj.Versions) {
			if ($Version -eq "Latest" -or $v.Name -match $Version -or $v.Code -match $Version) {
				$selectedVersionObj = $v
				break
			}
		}
	} else {
		$selectedVersionObj = $selectedToolObj.Versions[0]
		if ($Verbosity -ge 1) {
			Write-Host "No version specified (-Ver). Defaulting to '$($selectedVersionObj.Name)'."
		}
	}

	if ($selectedVersionObj -eq $null) {
		Write-Host "Invalid version."
		Write-Host "Use '-Ver List' to view available versions."
		exit 1
	}

	# 3. Edition Selection (-Edition / -Ed / -Flavor)
	if ($Edition -eq "List") {
		Write-Host "Available editions for $($selectedVersionObj.Name) (-Ed):"
		foreach ($e in $selectedVersionObj.Editions) {
			Write-Host " - $($e.Name) [Code: $($e.Code)]"
		}
		exit 0
	}

	$selectedEditionObj = $null
	if ($Edition) {
		foreach ($e in $selectedVersionObj.Editions) {
			if ($e.Name -match $Edition -or $e.Code -match $Edition) {
				$selectedEditionObj = $e
				break
			}
		}
	} else {
		$selectedEditionObj = $selectedVersionObj.Editions[0]
		if ($Verbosity -ge 1) {
			Write-Host "No edition specified (-Ed). Defaulting to '$($selectedEditionObj.Name)'."
		}
	}

	if ($selectedEditionObj -eq $null) {
		Write-Host "Invalid edition."
		Write-Host "Use '-Ed List' to view available editions."
		exit 1
	}

	# 4. Architecture Selection (-Arch)
	if ($Arch -eq "List") {
		Write-Host "Available architectures for $($selectedEditionObj.Name) (-Arch):"
		foreach ($a in $selectedEditionObj.Archs) {
			Write-Host " - $($a.Name) [Code: $($a.Arch)]"
		}
		exit 0
	}

	$selectedArchObj = $null
	if ($Arch) {
		foreach ($a in $selectedEditionObj.Archs) {
			if ($a.Name -match $Arch -or $a.Arch -match $Arch) {
				$selectedArchObj = $a
				break
			}
		}
	} else {
		$selectedArchObj = $selectedEditionObj.Archs[0]
		if ($Verbosity -ge 1) {
			Write-Host "No architecture specified (-Arch). Defaulting to '$($selectedArchObj.Name)'."
		}
	}

	if ($selectedArchObj -eq $null) {
		Write-Host "Invalid architecture."
		Write-Host "Use '-Arch List' to view available architectures."
		exit 1
	}

	$finalUrl = $selectedArchObj.Url

	if ($GetUrl) {
		Write-Output $finalUrl
		exit 0
	} else {
		Write-Host "Selected: $($selectedToolObj.Name) - $($selectedVersionObj.Name) - $($selectedEditionObj.Name) [$($selectedArchObj.Name)]"
		$fileName = ($finalUrl.Split('?')[0]).Split('/')[-1]
		$ExitCode = Process-Download-Link $finalUrl $fileName
		exit $ExitCode
	}
}
#endregion

#region GUI / WPF
# WPF Window definition in XAML
[xml]$XAML = @"
<Window xmlns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	Title = "isoRescue" Height = "184" Width = "384" ResizeMode = "NoResize"
	WindowStartupLocation = "CenterScreen">
	<Grid Name = "XMLGrid">
		<Button Name = "Continue" FontSize = "15" Height = "28" Width = "160" HorizontalAlignment = "Left" VerticalAlignment = "Top" Margin = "14,78,0,0"/>
		<Button Name = "Back" FontSize = "15" Height = "28" Width = "160" HorizontalAlignment = "Left" VerticalAlignment = "Top" Margin = "194,78,0,0"/>
		<TextBlock Name = "ToolTitle" FontSize = "15" Width="340" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="16,8,0,0" FontWeight="SemiBold"/>
		<ComboBox Name = "ToolChoice" FontSize = "13" Height = "26" Width = "340" HorizontalAlignment = "Left" VerticalAlignment="Top" Margin = "14,34,0,0"/>
		<CheckBox Name = "Check" FontSize = "13" Width = "340" HorizontalAlignment = "Left" VerticalAlignment="Top" Margin = "14,0,0,0" Visibility="Collapsed" />
		<TextBlock Name = "FooterCredits" Text = "Sebastian Januchowski @ polsoft.ITS(TM) Dev"
			FontSize = "11" FontFamily = "Segoe UI" FontWeight = "Medium"
			HorizontalAlignment = "Center" VerticalAlignment = "Bottom"
			Margin = "0,0,0,8" Foreground = "#464A50" Opacity = "0.88" TextAlignment = "Center"
			TextOptions.TextFormattingMode = "Display"
			TextOptions.TextRenderingMode = "ClearType"
			TextOptions.TextHintingMode = "Fixed"
			SnapsToDevicePixels = "True">
			<TextBlock.Effect>
				<DropShadowEffect ShadowDepth = "1" Direction = "315" Color = "White" Opacity = "0.75" BlurRadius = "0" RenderingBias = "Quality"/>
			</TextBlock.Effect>
		</TextBlock>
	</Grid>
</Window>
"@

function Add-Entry([int]$pos, [string]$Name, [array]$Items, [string]$DisplayName)
{
	$Title = New-Object System.Windows.Controls.TextBlock
	$Title.FontSize = $ToolTitle.FontSize
	$Title.FontWeight = $ToolTitle.FontWeight
	$Title.Height = $ToolTitle.Height
	$Title.Width = $ToolTitle.Width
	$Title.HorizontalAlignment = "Left"
	$Title.VerticalAlignment = "Top"
	$Margin = $ToolTitle.Margin
	$Margin.Top += $pos * $dh
	$Title.Margin = $Margin
	$Title.Text = Get-Translation($Name)
	$XMLGrid.Children.Insert(2 * $script:Stage + 2, $Title)

	$Combo = New-Object System.Windows.Controls.ComboBox
	$Combo.FontSize = $ToolChoice.FontSize
	$Combo.Height = $ToolChoice.Height
	$Combo.Width = $ToolChoice.Width
	$Combo.HorizontalAlignment = "Left"
	$Combo.VerticalAlignment = "Top"
	$Margin = $ToolChoice.Margin
	$Margin.Top += $pos * $dh
	$Combo.Margin = $Margin
	if ($Items) {
		$Combo.ItemsSource = $Items
		if ($DisplayName) {
			$Combo.DisplayMemberPath = $DisplayName
		} else {
			$Combo.DisplayMemberPath = "Name"
		}
		$Combo.SelectedIndex = 0
	}
	$XMLGrid.Children.Insert(2 * $script:Stage + 3, $Combo)

	$XMLForm.Height += $dh
	$Margin = $Continue.Margin
	$Margin.Top += $dh
	$Continue.Margin = $Margin
	$Margin = $Back.Margin
	$Margin.Top += $dh
	$Back.Margin = $Margin

	return $Combo
}

function Refresh-Control([object]$Control)
{
	$Control.Dispatcher.Invoke("Render", [Windows.Input.InputEventHandler] { $Continue.UpdateLayout() }, $null, $null) | Out-Null
}

# Create XAML form
$XMLForm = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XAML))
$XAML.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $XMLForm.FindName($_.Name) -Scope Script }

$XMLForm.Title = $AppTitle

# Set window icon
if ($Icon -and (Test-Path $Icon)) {
	$XMLForm.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]$Icon)
} else {
	try {
		$icon = [WinAPI.Utils]::ExtractIcon("imageres.dll", -109, $true)
		if ($icon) {
			$XMLForm.Icon = $icon | ConvertTo-ImageSource
		}
	} catch {}
}

if ($Locale.StartsWith("ar") -or $Locale.StartsWith("he")) {
	$XMLForm.FlowDirection = "RightToLeft"
}

$ToolTitle.Text = Get-Translation("Tool")
$Continue.Content = Get-Translation("Continue")
$Back.Content = Get-Translation("Close")

# Populate first list: Rescue Tools
$ToolChoice.ItemsSource = $RescueCatalog
$ToolChoice.DisplayMemberPath = "Name"
$ToolChoice.SelectedIndex = 0

# Handle Continue / Download button click
$Continue.add_click({
	$script:Stage++
	$XMLGrid.Children[2 * $Stage + 1].IsEnabled = $false
	$Continue.IsEnabled = $false
	$Back.IsEnabled = $false
	Refresh-Control($Continue)
	Refresh-Control($Back)

	switch ($Stage) {
		1 {
			# Step 1: Tool selected -> Populate versions
			$selectedTool = $ToolChoice.SelectedItem
			$script:SelectedVersionCombo = Add-Entry $Stage "Version" $selectedTool.Versions "Name"
			$Back.Content = Get-Translation("Back")
			$XMLForm.Title = $AppTitle
		}

		2 {
			# Step 2: Version selected -> Populate editions
			$selectedVer = $script:SelectedVersionCombo.SelectedItem
			$script:SelectedEditionCombo = Add-Entry $Stage "Edition" $selectedVer.Editions "Name"
			$XMLForm.Title = $AppTitle
		}

		3 {
			# Step 3: Edition selected -> Populate architectures & show Download
			$selectedEd = $script:SelectedEditionCombo.SelectedItem
			$script:SelectedArchCombo = Add-Entry $Stage "Architecture" $selectedEd.Archs "Name"
			$script:SelectedArchCombo.SelectedIndex = 0

			# Browser download option
			$XMLForm.Height += [int]($dh / 2)
			$Margin = $Continue.Margin
			$top = $Margin.Top
			$Margin.Top += [int]($dh / 2)
			$Continue.Margin = $Margin
			$Margin = $Back.Margin
			$Margin.Top += [int]($dh / 2)
			$Back.Margin = $Margin
			$Margin = $Check.Margin
			$Margin.Top = $top - 2
			$Check.Margin = $Margin
			$Check.Content = Get-Translation("Download using a browser")
			$Check.IsChecked = $true
			$Check.Visibility = "Visible"

			$Continue.Content = Get-Translation("Download")
			$XMLForm.Title = $AppTitle
		}

		4 {
			# Step 4: Click Download -> Execute download
			$selectedArch = $script:SelectedArchCombo.SelectedItem
			$finalUrl = $selectedArch.Url
			$fileName = ($finalUrl.Split('?')[0]).Split('/')[-1]

			$script:ExitCode = Process-Download-Link $finalUrl $fileName
			$XMLForm.Close()
		}
	}

	$Continue.IsEnabled = $true
	if ($Stage -ge 0) {
		$Back.IsEnabled = $true
	}
})

# Handle Back / Close button click
$Back.add_click({
	if ($Stage -eq 0) {
		$XMLForm.Close()
	} else {
		$XMLGrid.Children.RemoveAt(2 * $Stage + 3)
		$XMLGrid.Children.RemoveAt(2 * $Stage + 2)
		$XMLGrid.Children[2 * $Stage + 1].IsEnabled = $true
		$dh2 = $dh

		if ($Stage -eq 3) {
			$Check.Visibility = "Collapsed"
			$dh2 += [int]($dh / 2)
		}

		$XMLForm.Height -= $dh2
		$Margin = $Continue.Margin
		$Margin.Top -= $dh2
		$Continue.Margin = $Margin
		$Margin = $Back.Margin
		$Margin.Top -= $dh2
		$Back.Margin = $Margin

		$script:Stage = $Stage - 1
		$XMLForm.Title = $AppTitle

		if ($Stage -eq 0) {
			$Back.Content = Get-Translation("Close")
		} else {
			$Continue.Content = Get-Translation("Continue")
			Refresh-Control($Continue)
		}
	}
})

# Display window
$XMLForm.Add_Loaded({ $XMLForm.Activate() })
$XMLForm.ShowDialog() | Out-Null

exit $ExitCode
#endregion
