#
# odt Config v1.00 - Office Deployment Tool Configuration Generator & Installer
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
	[string]$AppTitle = "odtConfig - Office Configuration Generator",
	# (Optional) Pipe-separated localization strings
	[string]$LocData,
	# (Optional) Interface locale override (e.g. "en-US", "pl-PL")
	[string]$Locale,
	# (Optional) Path to icon file
	[string]$Icon,
	# (Optional) Office Product ID (e.g. "ProPlus2024Retail", "O365ProPlusRetail", "ProPlus2021Retail", "ProPlus2019Retail") [CLI mode]
	[Alias("Prod", "Suite")][string]$Product,
	# (Optional) Update Channel (e.g. "Current", "MonthlyEnterprise", "SemiAnnual", "PerpetualVL2024") [CLI mode]
	[string]$Channel,
	# (Optional) Architecture ("64" or "32") [CLI mode]
	[string]$Arch,
	# (Optional) Language code (e.g. "en-us", "pl-pl", "de-de") [CLI mode]
	[string]$Lang,
	# (Optional) Comma-separated list of applications to exclude (e.g. "Access,Teams,OneDrive,Groove,Publisher") [CLI mode]
	[string]$Exclude,
	# (Optional) Output path for configuration.xml [CLI mode]
	[string]$OutFile = "configuration.xml",
	# (Optional) Automatically download the official Microsoft Office Deployment Tool (setup.exe)
	[switch]$DownloadODT = $false,
	# (Optional) Automatically launch setup.exe /configure to start the customized installation
	[switch]$Install = $false,
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
if ($Product -or $Channel -or $Arch -or $Lang -or $Exclude -or $DownloadODT -or $Install) {
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

#region ODT Catalog
$ODTDownloadUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20430-20146.exe"

$ProductsList = @(
	[PSCustomObject]@{ Name = "Office 2024 Professional Plus (Retail)"; Id = "ProPlus2024Retail"; Channel = "Current" },
	[PSCustomObject]@{ Name = "Office 2024 Professional Plus (Volume / LTSC)"; Id = "ProPlus2024Volume"; Channel = "PerpetualVL2024" },
	[PSCustomObject]@{ Name = "Microsoft 365 Apps for Enterprise (ProPlus)"; Id = "O365ProPlusRetail"; Channel = "Current" },
	[PSCustomObject]@{ Name = "Microsoft 365 Business (Standard / Premium)"; Id = "O365BusinessRetail"; Channel = "Current" },
	[PSCustomObject]@{ Name = "Office 2021 Professional Plus (Retail)"; Id = "ProPlus2021Retail"; Channel = "Current" },
	[PSCustomObject]@{ Name = "Office 2021 Professional Plus (Volume / LTSC)"; Id = "ProPlus2021Volume"; Channel = "PerpetualVL2021" },
	[PSCustomObject]@{ Name = "Office 2019 Professional Plus (Retail)"; Id = "ProPlus2019Retail"; Channel = "Current" },
	[PSCustomObject]@{ Name = "Office 2016 Professional Plus (Retail)"; Id = "ProPlusRetail"; Channel = "Current" }
)

$AppPresets = @(
	[PSCustomObject]@{ Name = "Standard Office (Word, Excel, PowerPoint only)"; Exclude = @("Access", "Groove", "Lync", "OneDrive", "OneNote", "Outlook", "Publisher", "Teams") },
	[PSCustomObject]@{ Name = "Office Suite without Teams & OneDrive (Fast & Clean)"; Exclude = @("Access", "Groove", "Lync", "OneDrive", "Teams") },
	[PSCustomObject]@{ Name = "Full Productivity Suite (Word, Excel, PowerPoint, Outlook, OneNote)"; Exclude = @("Access", "Groove", "Lync", "Publisher", "Teams") },
	[PSCustomObject]@{ Name = "All Applications Included (No Exclusions)"; Exclude = @() }
)

$ChannelsList = @(
	[PSCustomObject]@{ Name = "Current Channel (Recommended for Microsoft 365)"; Code = "Current" },
	[PSCustomObject]@{ Name = "Monthly Enterprise Channel"; Code = "MonthlyEnterprise" },
	[PSCustomObject]@{ Name = "Semi-Annual Enterprise Channel"; Code = "SemiAnnual" },
	[PSCustomObject]@{ Name = "Perpetual VL 2024 (LTSC 2024)"; Code = "PerpetualVL2024" },
	[PSCustomObject]@{ Name = "Perpetual VL 2021 (LTSC 2021)"; Code = "PerpetualVL2021" }
)

$ArchitecturesList = @(
	[PSCustomObject]@{ Name = "64-bit (x64 - Recommended)"; Code = "64" },
	[PSCustomObject]@{ Name = "32-bit (x86 - Legacy)"; Code = "32" }
)

$LanguagesList = @(
	[PSCustomObject]@{ Display = "English (United States)"; Code = "en-us" },
	[PSCustomObject]@{ Display = "Polski (Polish)"; Code = "pl-pl" },
	[PSCustomObject]@{ Display = "English (United Kingdom)"; Code = "en-gb" },
	[PSCustomObject]@{ Display = "Deutsch (German)"; Code = "de-de" },
	[PSCustomObject]@{ Display = "Francais (French)"; Code = "fr-fr" },
	[PSCustomObject]@{ Display = "Espanol (Spanish)"; Code = "es-es" },
	[PSCustomObject]@{ Display = "Italiano (Italian)"; Code = "it-it" },
	[PSCustomObject]@{ Display = "Ukrainian"; Code = "uk-ua" }
)
#endregion

#region Globals
$ErrorActionPreference = "Stop"
$dh = 58
$Stage = 0
$ExitCode = 100

$Verbosity = 1
if ($Debug) { $Verbosity = 5 }
elseif ($Verbose) { $Verbosity = 2 }
#endregion

#region Localization
$EnglishMessages = "en-US|Suite|Preset|Architecture|Language|Generate Config|Continue|Back|Close|Cancel|Error|Please wait...|" +
	"Download setup.exe (ODT)|Configuration saved.|PowerShell 3.0 or later is required.|Do you want to download it?|" +
	"This feature is not available on this platform."

$PolishMessages = "pl-PL|Pakiet|Szablon|Architektura|JÄ™zyk|Generuj konfiguracjÄ™|Dalej|Wstecz|Zamknij|Anuluj|BĹ‚Ä…d|ProszÄ™ czekaÄ‡...|" +
	"Pobierz setup.exe (ODT)|Konfiguracja zapisana.|Wymagany jest PowerShell 3.0.|Czy chcesz pobraÄ‡?|" +
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

function Generate-Configuration-Xml(
	[string]$ProductId,
	[string]$ChannelName,
	[string]$Architecture,
	[string]$LanguageCode,
	[string[]]$ExcludedApps
) {
	$xml = @"
<Configuration>
  <Add OfficeClientEdition="$Architecture" Channel="$ChannelName">
    <Product ID="$ProductId">
      <Language ID="$LanguageCode" />
"@
	if ($ExcludedApps -and $ExcludedApps.Count -gt 0) {
		foreach ($app in $ExcludedApps) {
			$xml += "`n      <ExcludeApp ID=""$app"" />"
		}
	}

	$xml += @"

    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="DeviceBasedLicensing" Value="0" />
  <Property Name="SCLCacheOverride" Value="0" />
  <Updates Enabled="TRUE" />
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@
	return $xml
}

function Download-ODT-Executable([string]$DestinationDir = ".")
{
	$destFile = Join-Path $DestinationDir "officedeploymenttool.exe"
	Write-Host "Downloading Office Deployment Tool from Microsoft..."
	Invoke-IsoDownload -Source $ODTDownloadUrl -Destination $destFile -DisplayName "Office Deployment Tool" | Out-Null

	Write-Host "Extracting setup.exe..."
	$extractArgs = "/quiet /extract:`"$DestinationDir`""
	Start-Process -FilePath $destFile -ArgumentList $extractArgs -Wait -NoNewWindow
	Remove-Item -Path $destFile -Force -ErrorAction SilentlyContinue

	$setupPath = Join-Path $DestinationDir "setup.exe"
	if (Test-Path $setupPath) {
		Write-Host "Office Deployment Tool (setup.exe) ready: $setupPath"
		return $setupPath
	}
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
#endregion

#region CLI Mode
if ($Cmd) {
	# Platform check
	if ($winver -le 6.1) {
		Error(Get-Translation("This feature is not available on this platform."))
		exit 403
	}

	# 1. Product Selection
	if ($Product -eq "List") {
		Write-Host "Available Office Suites (-Product):"
		foreach ($p in $ProductsList) {
			Write-Host " - $($p.Name) [Id: $($p.Id)]"
		}
		exit 0
	}

	$selectedProductObj = $null
	if ($Product) {
		foreach ($p in $ProductsList) {
			if ($p.Id -match $Product -or $p.Name -match $Product) {
				$selectedProductObj = $p
				break
			}
		}
	} else {
		$selectedProductObj = $ProductsList[0]
		if ($Verbosity -ge 1) {
			Write-Host "No product specified (-Product). Defaulting to '$($selectedProductObj.Name)'."
		}
	}

	if ($selectedProductObj -eq $null) {
		Write-Host "Invalid product suite specified."
		Write-Host "Use '-Product List' to view available suites."
		exit 1
	}

	# 2. Channel
	$selectedChannel = if ($Channel) { $Channel } else { $selectedProductObj.Channel }

	# 3. Architecture
	$selectedArch = if ($Arch -match "32|x86") { "32" } else { "64" }

	# 4. Language
	$selectedLang = if ($Lang) { $Lang } else { "en-us" }

	# 5. Excluded Apps
	$excludedList = @()
	if ($Exclude) {
		$excludedList = $Exclude.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
	}

	$configContent = Generate-Configuration-Xml $selectedProductObj.Id $selectedChannel $selectedArch $selectedLang $excludedList
	Set-Content -Path $OutFile -Value $configContent -Encoding UTF8
	Write-Host "Generated configuration file: $OutFile"

	if ($DownloadODT -or $Install) {
		$setupExe = Download-ODT-Executable "."
		if ($Install -and $setupExe) {
			Write-Host "Starting Office Installation..."
			Start-Process -FilePath $setupExe -ArgumentList "/configure", "`"$OutFile`"" -Wait
			Write-Host "Installation process completed."
		}
	}
	exit 0
}
#endregion

#region GUI / WPF
# WPF Window definition in XAML
[xml]$XAML = @"
<Window xmlns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	Title = "odtConfig" Height = "184" Width = "384" ResizeMode = "NoResize"
	WindowStartupLocation = "CenterScreen">
	<Grid Name = "XMLGrid">
		<Button Name = "Continue" FontSize = "15" Height = "28" Width = "160" HorizontalAlignment = "Left" VerticalAlignment = "Top" Margin = "14,78,0,0"/>
		<Button Name = "Back" FontSize = "15" Height = "28" Width = "160" HorizontalAlignment = "Left" VerticalAlignment = "Top" Margin = "194,78,0,0"/>
		<TextBlock Name = "StepTitle" FontSize = "15" Width="340" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="16,8,0,0" FontWeight="SemiBold"/>
		<ComboBox Name = "StepChoice" FontSize = "13" Height = "26" Width = "340" HorizontalAlignment = "Left" VerticalAlignment="Top" Margin = "14,34,0,0"/>
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
	$Title.FontSize = $StepTitle.FontSize
	$Title.FontWeight = $StepTitle.FontWeight
	$Title.Height = $StepTitle.Height
	$Title.Width = $StepTitle.Width
	$Title.HorizontalAlignment = "Left"
	$Title.VerticalAlignment = "Top"
	$Margin = $StepTitle.Margin
	$Margin.Top += $pos * $dh
	$Title.Margin = $Margin
	$Title.Text = Get-Translation($Name)
	$XMLGrid.Children.Insert(2 * $script:Stage + 2, $Title)

	$Combo = New-Object System.Windows.Controls.ComboBox
	$Combo.FontSize = $StepChoice.FontSize
	$Combo.Height = $StepChoice.Height
	$Combo.Width = $StepChoice.Width
	$Combo.HorizontalAlignment = "Left"
	$Combo.VerticalAlignment = "Top"
	$Margin = $StepChoice.Margin
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
		$icon = [WinAPI.Utils]::ExtractIcon("imageres.dll", -110, $true)
		if ($icon) {
			$XMLForm.Icon = $icon | ConvertTo-ImageSource
		}
	} catch {}
}

if ($Locale.StartsWith("ar") -or $Locale.StartsWith("he")) {
	$XMLForm.FlowDirection = "RightToLeft"
}

$StepTitle.Text = Get-Translation("Suite")
$Continue.Content = Get-Translation("Continue")
$Back.Content = Get-Translation("Close")

# Populate first list: Office Products
$StepChoice.ItemsSource = $ProductsList
$StepChoice.DisplayMemberPath = "Name"
$StepChoice.SelectedIndex = 0

# Handle Continue / Generate button click
$Continue.add_click({
	$script:Stage++
	$XMLGrid.Children[2 * $Stage + 1].IsEnabled = $false
	$Continue.IsEnabled = $false
	$Back.IsEnabled = $false
	Refresh-Control($Continue)
	Refresh-Control($Back)

	switch ($Stage) {
		1 {
			# Step 1: Product selected -> Populate application preset
			$script:SelectedPresetCombo = Add-Entry $Stage "Preset" $AppPresets "Name"
			$Back.Content = Get-Translation("Back")
			$XMLForm.Title = $AppTitle
		}

		2 {
			# Step 2: Preset selected -> Populate architecture
			$script:SelectedArchCombo = Add-Entry $Stage "Architecture" $ArchitecturesList "Name"
			$XMLForm.Title = $AppTitle
		}

		3 {
			# Step 3: Architecture selected -> Populate language & show Download ODT checkbox
			$script:SelectedLangCombo = Add-Entry $Stage "Language" $LanguagesList "Display"

			# Auto-select Polish if system locale is Polish
			if ([System.Globalization.CultureInfo]::CurrentUICulture.Name.ToLower().StartsWith("pl")) {
				$script:SelectedLangCombo.SelectedIndex = 1
			} else {
				$script:SelectedLangCombo.SelectedIndex = 0
			}

			# Checkbox option to download setup.exe (ODT) automatically
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
			$Check.Content = Get-Translation("Download setup.exe (ODT)")
			$Check.IsChecked = $true
			$Check.Visibility = "Visible"

			$Continue.Content = Get-Translation("Generate Config")
			$XMLForm.Title = $AppTitle
		}

		4 {
			# Step 4: Click Generate Config -> Create configuration.xml
			$selectedProd = $StepChoice.SelectedItem
			$selectedPreset = $script:SelectedPresetCombo.SelectedItem
			$selectedArch = $script:SelectedArchCombo.SelectedItem
			$selectedLang = $script:SelectedLangCombo.SelectedItem

			$cfgXml = Generate-Configuration-Xml $selectedProd.Id $selectedProd.Channel $selectedArch.Code $selectedLang.Code $selectedPreset.Exclude
			$targetFile = "configuration.xml"
			Set-Content -Path $targetFile -Value $cfgXml -Encoding UTF8

			if ($Check.IsChecked) {
				Download-ODT-Executable "." | Out-Null
			}

			[System.Windows.MessageBox]::Show("Office configuration successfully generated: $targetFile`n`nTo install custom Office, run:`nsetup.exe /configure $targetFile", $AppTitle, "OK", "Information") | Out-Null
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
