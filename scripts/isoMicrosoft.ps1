#
# iso Microsoft v1.00 - Microsoft Windows & Office Downloader
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
	[string]$AppTitle = "isoMicrosoft - Microsoft Windows & Office Downloader",
	# (Optional) Pipe-separated localization strings
	[string]$LocData,
	# (Optional) Interface locale override (e.g. "en-US", "pl-PL")
	[string]$Locale,
	# (Optional) Path to icon file
	[string]$Icon,
	# (Optional) Named pipe to send the URL to (e.g. Rufus integration)
	[string]$PipeName,
	# (Optional) Product family to download ("Windows" or "Office") [CLI mode]
	[Alias("Prod", "Type")][string]$Product,
	# (Optional) Version of selected product (Windows: "11", "10", "8.1" | Office: "2024", "2021", "2019", "2016", "365") [CLI mode]
	[Alias("Ver", "Win", "Office")][string]$Version,
	# (Optional) Windows release (e.g. "24H2", "23H2", "22H2", "Latest") [CLI mode]
	[Alias("Rel")][string]$Release,
	# (Optional) Product edition (e.g. "Home/Pro/Edu", "ProPlus", "HomeBusiness") [CLI mode]
	[string]$Ed,
	# (Optional) Language code or name (e.g. "en-us", "English", "pl-pl") [CLI mode]
	[string]$Lang,
	# (Optional) Architecture (e.g. "x64", "x86", "ARM64", "dual") [CLI mode]
	[string]$Arch,
	# (Optional) Return download URL only [CLI mode]
	[switch]$GetUrl = $false,
	# (Optional) Download file directly to disk in CLI mode
	[switch]$Download = $false,
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
if ($Product -or $Version -or $Release -or $Ed -or $Lang -or $Arch -or $GetUrl -or $Download) {
	$Cmd = $true
}

# Auto-detect product in CLI mode if not explicitly stated
if ($Cmd -and !$Product) {
	if ($Release -or $Version -match "^(11|10|8|8\.1)$") {
		$Product = "Windows"
	} elseif ($Version -match "^(2016|2019|2021|2024|365)$") {
		$Product = "Office"
	} else {
		$Product = "Windows"
	}
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

#region Data Catalogs

# Top-level Product Categories
$ProductFamilies = @(
	[PSCustomObject]@{ Name = "Microsoft Windows (Operating System)"; Code = "Windows" },
	[PSCustomObject]@{ Name = "Microsoft Office (Productivity Suite)"; Code = "Office" }
)

# 1. Windows Catalog
$WindowsCatalog = @(
	[PSCustomObject]@{
		Name     = "Windows 11"
		Code     = "11"
		Page     = "windows11"
		Releases = @(
			[PSCustomObject]@{
				Name     = "24H2 / 26H2 (Build 26300.9457 - Latest)"
				Code     = "24H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 11 Home/Pro/Edu"; Ids = @(3813, 3816) },
					[PSCustomObject]@{ Name = "Windows 11 Home China"; Ids = @(3814, 3817) },
					[PSCustomObject]@{ Name = "Windows 11 Pro China"; Ids = @(3815, 3818) }
				)
			},
			[PSCustomObject]@{
				Name     = "23H2 v2 (Build 22631.2861)"
				Code     = "23H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 11 Home/Pro/Edu"; Ids = @(3113) },
					[PSCustomObject]@{ Name = "Windows 11 Home China"; Ids = @(3114) }
				)
			},
			[PSCustomObject]@{
				Name     = "22H2 (Build 22621.525)"
				Code     = "22H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 11 Home/Pro/Edu"; Ids = @(2470) },
					[PSCustomObject]@{ Name = "Windows 11 Home China"; Ids = @(2471) }
				)
			},
			[PSCustomObject]@{
				Name     = "21H2 (Build 22000.194)"
				Code     = "21H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 11 Home/Pro/Edu"; Ids = @(2018) },
					[PSCustomObject]@{ Name = "Windows 11 Home China"; Ids = @(2019) }
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "Windows 10"
		Code     = "10"
		Page     = "windows10ISO"
		Releases = @(
			[PSCustomObject]@{
				Name     = "22H2 v1 (Build 19045.2965 - Latest)"
				Code     = "22H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 10 Home/Pro/Edu"; Ids = @(2618) },
					[PSCustomObject]@{ Name = "Windows 10 Home China"; Ids = @(2378) }
				)
			},
			[PSCustomObject]@{
				Name     = "21H2 (Build 19044.1288)"
				Code     = "21H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 10 Home/Pro/Edu"; Ids = @(2267) },
					[PSCustomObject]@{ Name = "Windows 10 Home China"; Ids = @(2268) }
				)
			},
			[PSCustomObject]@{
				Name     = "20H2 (Build 19042.508)"
				Code     = "20H2"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 10 Home/Pro/Edu"; Ids = @(1782) },
					[PSCustomObject]@{ Name = "Windows 10 Home China"; Ids = @(1783) }
				)
			}
		)
	},
	[PSCustomObject]@{
		Name     = "Windows 8.1"
		Code     = "8.1"
		Page     = "windows8ISO"
		Releases = @(
			[PSCustomObject]@{
				Name     = "Windows 8.1 with Update"
				Code     = "8.1"
				Editions = @(
					[PSCustomObject]@{ Name = "Windows 8.1"; Ids = @(52) },
					[PSCustomObject]@{ Name = "Windows 8.1 Professional"; Ids = @(53) },
					[PSCustomObject]@{ Name = "Windows 8.1 Single Language"; Ids = @(54) }
				)
			}
		)
	}
)

# 2. Office Catalog
$OfficeCatalog = @(
	[PSCustomObject]@{
		Name     = "Microsoft 365"
		Code     = "365"
		Editions = @(
			[PSCustomObject]@{ Name = "Microsoft 365 Family & Personal (Home Premium)"; Code = "O365HomePremRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote" },
			[PSCustomObject]@{ Name = "Microsoft 365 Apps for Enterprise (ProPlus)"; Code = "O365ProPlusRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, Access, OneNote, Teams" },
			[PSCustomObject]@{ Name = "Microsoft 365 Business (Standard / Premium)"; Code = "O365BusinessRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Teams" }
		)
	},
	[PSCustomObject]@{
		Name     = "Office 2024"
		Code     = "2024"
		Editions = @(
			[PSCustomObject]@{ Name = "Office 2024 Professional Plus"; Code = "ProPlus2024Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access" },
			[PSCustomObject]@{ Name = "Office 2024 Home & Business"; Code = "HomeBusiness2024Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote" },
			[PSCustomObject]@{ Name = "Office 2024 Home (Home & Student)"; Code = "Home2024Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, OneNote" },
			[PSCustomObject]@{ Name = "Project 2024 Professional"; Code = "ProjectPro2024Retail"; Ext = "img"; Apps = "Microsoft Project 2024 Professional" },
			[PSCustomObject]@{ Name = "Project 2024 Standard"; Code = "ProjectStd2024Retail"; Ext = "img"; Apps = "Microsoft Project 2024 Standard" },
			[PSCustomObject]@{ Name = "Visio 2024 Professional"; Code = "VisioPro2024Retail"; Ext = "img"; Apps = "Microsoft Visio 2024 Professional" },
			[PSCustomObject]@{ Name = "Visio 2024 Standard"; Code = "VisioStd2024Retail"; Ext = "img"; Apps = "Microsoft Visio 2024 Standard" },
			[PSCustomObject]@{ Name = "Word 2024"; Code = "Word2024Retail"; Ext = "img"; Apps = "Microsoft Word 2024" },
			[PSCustomObject]@{ Name = "Excel 2024"; Code = "Excel2024Retail"; Ext = "img"; Apps = "Microsoft Excel 2024" },
			[PSCustomObject]@{ Name = "PowerPoint 2024"; Code = "PowerPoint2024Retail"; Ext = "img"; Apps = "Microsoft PowerPoint 2024" },
			[PSCustomObject]@{ Name = "Outlook 2024"; Code = "Outlook2024Retail"; Ext = "img"; Apps = "Microsoft Outlook 2024" },
			[PSCustomObject]@{ Name = "Access 2024"; Code = "Access2024Retail"; Ext = "img"; Apps = "Microsoft Access 2024" }
		)
	},
	[PSCustomObject]@{
		Name     = "Office 2021"
		Code     = "2021"
		Editions = @(
			[PSCustomObject]@{ Name = "Office 2021 Professional Plus"; Code = "ProPlus2021Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2021 Professional"; Code = "Professional2021Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2021 Home & Business"; Code = "HomeBusiness2021Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote" },
			[PSCustomObject]@{ Name = "Office 2021 Home & Student"; Code = "HomeStudent2021Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, OneNote" },
			[PSCustomObject]@{ Name = "Project 2021 Professional"; Code = "ProjectPro2021Retail"; Ext = "img"; Apps = "Microsoft Project 2021 Professional" },
			[PSCustomObject]@{ Name = "Project 2021 Standard"; Code = "ProjectStd2021Retail"; Ext = "img"; Apps = "Microsoft Project 2021 Standard" },
			[PSCustomObject]@{ Name = "Visio 2021 Professional"; Code = "VisioPro2021Retail"; Ext = "img"; Apps = "Microsoft Visio 2021 Professional" },
			[PSCustomObject]@{ Name = "Visio 2021 Standard"; Code = "VisioStd2021Retail"; Ext = "img"; Apps = "Microsoft Visio 2021 Standard" },
			[PSCustomObject]@{ Name = "Word 2021"; Code = "Word2021Retail"; Ext = "img"; Apps = "Microsoft Word 2021" },
			[PSCustomObject]@{ Name = "Excel 2021"; Code = "Excel2021Retail"; Ext = "img"; Apps = "Microsoft Excel 2021" },
			[PSCustomObject]@{ Name = "PowerPoint 2021"; Code = "PowerPoint2021Retail"; Ext = "img"; Apps = "Microsoft PowerPoint 2021" },
			[PSCustomObject]@{ Name = "Outlook 2021"; Code = "Outlook2021Retail"; Ext = "img"; Apps = "Microsoft Outlook 2021" },
			[PSCustomObject]@{ Name = "Access 2021"; Code = "Access2021Retail"; Ext = "img"; Apps = "Microsoft Access 2021" }
		)
	},
	[PSCustomObject]@{
		Name     = "Office 2019"
		Code     = "2019"
		Editions = @(
			[PSCustomObject]@{ Name = "Office 2019 Professional Plus"; Code = "ProPlus2019Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2019 Professional"; Code = "Professional2019Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2019 Home & Business"; Code = "HomeBusiness2019Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote" },
			[PSCustomObject]@{ Name = "Office 2019 Home & Student"; Code = "HomeStudent2019Retail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, OneNote" },
			[PSCustomObject]@{ Name = "Project 2019 Professional"; Code = "ProjectPro2019Retail"; Ext = "img"; Apps = "Microsoft Project 2019 Professional" },
			[PSCustomObject]@{ Name = "Project 2019 Standard"; Code = "ProjectStd2019Retail"; Ext = "img"; Apps = "Microsoft Project 2019 Standard" },
			[PSCustomObject]@{ Name = "Visio 2019 Professional"; Code = "VisioPro2019Retail"; Ext = "img"; Apps = "Microsoft Visio 2019 Professional" },
			[PSCustomObject]@{ Name = "Visio 2019 Standard"; Code = "VisioStd2019Retail"; Ext = "img"; Apps = "Microsoft Visio 2019 Standard" },
			[PSCustomObject]@{ Name = "Word 2019"; Code = "Word2019Retail"; Ext = "img"; Apps = "Microsoft Word 2019" },
			[PSCustomObject]@{ Name = "Excel 2019"; Code = "Excel2019Retail"; Ext = "img"; Apps = "Microsoft Excel 2019" },
			[PSCustomObject]@{ Name = "PowerPoint 2019"; Code = "PowerPoint2019Retail"; Ext = "img"; Apps = "Microsoft PowerPoint 2019" },
			[PSCustomObject]@{ Name = "Outlook 2019"; Code = "Outlook2019Retail"; Ext = "img"; Apps = "Microsoft Outlook 2019" },
			[PSCustomObject]@{ Name = "Access 2019"; Code = "Access2019Retail"; Ext = "img"; Apps = "Microsoft Access 2019" }
		)
	},
	[PSCustomObject]@{
		Name     = "Office 2016"
		Code     = "2016"
		Editions = @(
			[PSCustomObject]@{ Name = "Office 2016 Professional Plus"; Code = "ProPlusRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2016 Professional"; Code = "ProfessionalRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher" },
			[PSCustomObject]@{ Name = "Office 2016 Home & Business"; Code = "HomeBusinessRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, Outlook, OneNote" },
			[PSCustomObject]@{ Name = "Office 2016 Home & Student"; Code = "HomeStudentRetail"; Ext = "img"; Apps = "Word, Excel, PowerPoint, OneNote" },
			[PSCustomObject]@{ Name = "Project 2016 Professional"; Code = "ProjectProRetail"; Ext = "img"; Apps = "Microsoft Project 2016 Professional" },
			[PSCustomObject]@{ Name = "Project 2016 Standard"; Code = "ProjectStdRetail"; Ext = "img"; Apps = "Microsoft Project 2016 Standard" },
			[PSCustomObject]@{ Name = "Visio 2016 Professional"; Code = "VisioProRetail"; Ext = "img"; Apps = "Microsoft Visio 2016 Professional" },
			[PSCustomObject]@{ Name = "Visio 2016 Standard"; Code = "VisioStdRetail"; Ext = "img"; Apps = "Microsoft Visio 2016 Standard" },
			[PSCustomObject]@{ Name = "Word 2016"; Code = "WordRetail"; Ext = "img"; Apps = "Microsoft Word 2016" },
			[PSCustomObject]@{ Name = "Excel 2016"; Code = "ExcelRetail"; Ext = "img"; Apps = "Microsoft Excel 2016" },
			[PSCustomObject]@{ Name = "PowerPoint 2016"; Code = "PowerPointRetail"; Ext = "img"; Apps = "Microsoft PowerPoint 2016" },
			[PSCustomObject]@{ Name = "Outlook 2016"; Code = "OutlookRetail"; Ext = "img"; Apps = "Microsoft Outlook 2016" },
			[PSCustomObject]@{ Name = "Access 2016"; Code = "AccessRetail"; Ext = "img"; Apps = "Microsoft Access 2016" }
		)
	}
)

# Office Languages Catalog
$OfficeLanguages = @(
	[PSCustomObject]@{ Display = "English (United States)"; Code = "en-us" },
	[PSCustomObject]@{ Display = "English (United Kingdom)"; Code = "en-gb" },
	[PSCustomObject]@{ Display = "Polski (Polish)"; Code = "pl-pl" },
	[PSCustomObject]@{ Display = "Deutsch (German)"; Code = "de-de" },
	[PSCustomObject]@{ Display = "Francais (French)"; Code = "fr-fr" },
	[PSCustomObject]@{ Display = "Espanol (Spanish)"; Code = "es-es" },
	[PSCustomObject]@{ Display = "Italiano (Italian)"; Code = "it-it" },
	[PSCustomObject]@{ Display = "Portugues (Brasil)"; Code = "pt-br" },
	[PSCustomObject]@{ Display = "Portugues (Portugal)"; Code = "pt-pt" },
	[PSCustomObject]@{ Display = "Ukrainian"; Code = "uk-ua" },
	[PSCustomObject]@{ Display = "Czech"; Code = "cs-cz" },
	[PSCustomObject]@{ Display = "Slovak"; Code = "sk-sk" },
	[PSCustomObject]@{ Display = "Slovenian"; Code = "sl-si" },
	[PSCustomObject]@{ Display = "Hungarian"; Code = "hu-hu" },
	[PSCustomObject]@{ Display = "Romanian"; Code = "ro-ro" },
	[PSCustomObject]@{ Display = "Bulgarian"; Code = "bg-bg" },
	[PSCustomObject]@{ Display = "Croatian"; Code = "hr-hr" },
	[PSCustomObject]@{ Display = "Serbian (Latin)"; Code = "sr-latn-rs" },
	[PSCustomObject]@{ Display = "Nederlands (Dutch)"; Code = "nl-nl" },
	[PSCustomObject]@{ Display = "Danish"; Code = "da-dk" },
	[PSCustomObject]@{ Display = "Finnish"; Code = "fi-fi" },
	[PSCustomObject]@{ Display = "Norwegian (Bokmal)"; Code = "nb-no" },
	[PSCustomObject]@{ Display = "Swedish"; Code = "sv-se" },
	[PSCustomObject]@{ Display = "Greek"; Code = "el-gr" },
	[PSCustomObject]@{ Display = "Turkish"; Code = "tr-tr" },
	[PSCustomObject]@{ Display = "Russian"; Code = "ru-ru" },
	[PSCustomObject]@{ Display = "Hebrew"; Code = "he-il" },
	[PSCustomObject]@{ Display = "Arabic"; Code = "ar-sa" },
	[PSCustomObject]@{ Display = "Chinese (Simplified)"; Code = "zh-cn" },
	[PSCustomObject]@{ Display = "Chinese (Traditional)"; Code = "zh-tw" },
	[PSCustomObject]@{ Display = "Japanese"; Code = "ja-jp" },
	[PSCustomObject]@{ Display = "Korean"; Code = "ko-kr" },
	[PSCustomObject]@{ Display = "Thai"; Code = "th-th" },
	[PSCustomObject]@{ Display = "Vietnamese"; Code = "vi-vn" },
	[PSCustomObject]@{ Display = "Indonesian"; Code = "id-id" },
	[PSCustomObject]@{ Display = "Malay"; Code = "ms-my" }
)

# Office Architecture Options
$OfficeArchitectures = @(
	[PSCustomObject]@{ Name = "x64 & x86 (Dual 64-bit / 32-bit Offline IMG)"; Code = "dual"; Arch = "dual" },
	[PSCustomObject]@{ Name = "x64 (64-bit)"; Code = "x64"; Arch = "x64" },
	[PSCustomObject]@{ Name = "x86 (32-bit)"; Code = "x86"; Arch = "x86" }
)
#endregion

#region Globals
$ErrorActionPreference = "Stop"
$DefaultTimeout = 30
$dh = 58
$Stage = 0
$SelectedIndex = 0
$MaxStage = 5
$ExitCode = 100

$OrgId = "y6jn8c31"
$ProfileId = "606624d44113"
$InstanceId = "560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"

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
$EnglishMessages = "en-US|Product|Version|Release|Edition|Language|Architecture|Download|Continue|Back|Close|Cancel|Error|Please wait...|" +
	"Download using a browser|Download is unavailable.|" +
	"PowerShell 3.0 or later is required to run this script.|Do you want to go online and download it?|" +
	"This feature is not available on this platform."

$PolishMessages = "pl-PL|Produkt|Wersja|Wydanie|Edycja|JÄ™zyk|Architektura|Pobierz|Dalej|Wstecz|Zamknij|Anuluj|BĹ‚Ä…d|ProszÄ™ czekaÄ‡...|" +
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
		$res = $req.GetResponse()
		$len = [uint64]$res.ContentLength
		$res.Close()
		if ($len -gt 0) {
			return (Size-To-Human-Readable $len)
		}
	} catch {}
	return $null
}

function Get-Arch-From-Type([int]$Type)
{
	switch ($Type) {
		0 { return "x86" }
		1 { return "x64" }
		2 { return "ARM64" }
		default { return "Unknown" }
	}
}

function Select-Office-Language-Index([array]$Languages)
{
	$target = if ($Locale) { $Locale.ToLower() } else { "en-us" }
	$shortTarget = $target.Split('-')[0]
	$idx = 0
	foreach ($l in $Languages) {
		if ($l.Code.ToLower() -eq $target -or $l.Code.ToLower().StartsWith($shortTarget)) {
			return $idx
		}
		$idx++
	}
	return 0
}

function Build-Office-Url([string]$LanguageCode, [string]$ProductCode, [string]$Ext = "img")
{
	return "https://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60/media/$LanguageCode/${ProductCode}.$Ext"
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

# Fetch official Windows SKUs and languages from Microsoft connector API
function Get-Windows-Languages([object]$SelectedEdition)
{
	$languages = [ordered]@{}
	$SessionIndex = 0
	$script:SessionIds = @()

	foreach ($EditionId in $SelectedEdition.Ids) {
		$currentSessionId = [guid]::NewGuid().ToString()
		$script:SessionIds += $currentSessionId

		# Microsoft download token handshake: whitelist sessionId with vlscppe
		$tagUrl = "https://vlscppe.microsoft.com/tags?org_id=$OrgId&session_id=$currentSessionId"
		if ($Verbosity -ge 2) { Write-Host "Querying $tagUrl" }
		try {
			Invoke-WebRequest -UseBasicParsing -TimeoutSec $DefaultTimeout $tagUrl | Out-Null
		} catch {
			Error($_.Exception.Message)
			return @()
		}

		# Retrieve w and rticks from mdt.js
		$mdtUrl = "https://ov-df.microsoft.com/mdt.js?instanceId=$InstanceId&PageId=si&session_id=$currentSessionId"
		if ($Verbosity -ge 2) { Write-Host "Querying $mdtUrl" }
		try {
			$mdt = Invoke-RestMethod -UseBasicParsing -TimeoutSec $DefaultTimeout $mdtUrl
			$w = [regex]::Match($mdt, "[?&]w=([A-F0-9]+)").Groups[1].Value
			$rticks = [regex]::Match($mdt, 'rticks\=\"\+?(\d+)').Groups[1].Value
			if (!$w -or !$rticks) { throw "Unable to extract validation tokens from ov-df" }
		} catch {
			Error($_.Exception.Message)
			return @()
		}

		# Send ov-df verification reply
		$epoch = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
		$dfUrl = "https://ov-df.microsoft.com/?session_id=$currentSessionId&CustomerId=$InstanceId&PageId=si&w=$w&mdt=$epoch&rticks=$rticks"
		if ($Verbosity -ge 2) { Write-Host "Querying $dfUrl" }
		try {
			Invoke-WebRequest -UseBasicParsing -TimeoutSec $DefaultTimeout $dfUrl | Out-Null
		} catch {
			Error($_.Exception.Message)
			return @()
		}

		# Request available language SKUs for this edition
		$skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$ProfileId&productEditionId=$EditionId&SKU=undefined&friendlyFileName=undefined&Locale=$Locale&sessionID=$currentSessionId"
		if ($Verbosity -ge 2) { Write-Host "Querying $skuUrl" }
		try {
			$res = Invoke-RestMethod -UseBasicParsing -TimeoutSec $DefaultTimeout $skuUrl
			if ($res.Errors) { throw $res.Errors[0].Value }
			foreach ($Sku in $res.Skus) {
				if (!$languages.Contains($Sku.Language)) {
					$languages[$Sku.Language] = @{
						DisplayName = $Sku.LocalizedLanguage
						Name        = $Sku.Language
						Data        = @()
					}
				}
				$languages[$Sku.Language].Data += @{ SessionIndex = $SessionIndex; SkuId = $Sku.Id }
			}
		} catch {
			Error($_.Exception.Message)
			return @()
		}
		$SessionIndex++
	}

	$langs = @()
	foreach ($langKey in $languages.Keys) {
		$langs += [PSCustomObject]@{
			DisplayName = $languages[$langKey].DisplayName
			Name        = $languages[$langKey].Name
			Data        = $languages[$langKey].Data
		}
	}
	return $langs
}

# Fetch official direct ISO download links for Windows
function Get-Windows-Download-Links([string]$Page, [PSCustomObject]$SelectedLanguage)
{
	$links = @()
	foreach ($entry in $SelectedLanguage.Data) {
		$sessionId = $script:SessionIds[$entry.SessionIndex]
		$url = "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$ProfileId&productEditionId=undefined&SKU=$($entry.SkuId)&friendlyFileName=undefined&Locale=$Locale&sessionID=$sessionId"
		if ($Verbosity -ge 2) { Write-Host "Querying $url" }
		try {
			$ref = "https://www.microsoft.com/software-download/$Page"
			$res = Invoke-RestMethod -Headers @{ "Referer" = $ref } -UseBasicParsing -TimeoutSec $DefaultTimeout $url
			if ($res.Errors) {
				if ($Verbosity -ge 2) { Write-Host "Microsoft API Notice: $($res.Errors[0].Value)" }
			} elseif ($res.ProductDownloadOptions) {
				foreach ($opt in $res.ProductDownloadOptions) {
					$archName = Get-Arch-From-Type $opt.DownloadType
					$links += [PSCustomObject]@{
						Name = "$archName (Official ISO)"
						Arch = $archName
						Url  = $opt.Uri
					}
				}
			}
		} catch {
			if ($Verbosity -ge 2) { Write-Host "API Warning: $($_.Exception.Message)" }
		}
	}

	if ($links.Count -eq 0) {
		$links += [PSCustomObject]@{
			Name = "Official Microsoft Download Portal"
			Arch = "Web"
			Url  = "https://www.microsoft.com/software-download/$Page"
		}
	}
	return $links
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
			Write-Host "Downloading '$FileName' from Microsoft CDN..."
			$Size = Get-Url-Size $Url
			if ($Size) {
				Write-Host "File size: $Size"
			}
			Invoke-IsoDownload -Source $Url -Destination $FileName -DisplayName "Microsoft Download" | Out-Null
			Write-Host "Download complete: $FileName"
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

	# 0. Product Selection (-Product / -Prod)
	if ($Product -eq "List") {
		Write-Host "Available Products (-Product):"
		foreach ($p in $ProductFamilies) {
			Write-Host " - $($p.Name) [Code: $($p.Code)]"
		}
		exit 0
	}

	$selectedProduct = if ($Product -match "office") { "Office" } else { "Windows" }

	# ---------------- WINDOWS CLI FLOW ----------------
	if ($selectedProduct -eq "Windows") {
		# Version Selection
		if ($Version -eq "List") {
			Write-Host "Available Windows versions (-Ver):"
			foreach ($v in $WindowsCatalog) {
				Write-Host " - $($v.Name) [Code: $($v.Code)]"
			}
			exit 0
		}

		$selectedVersionObj = $null
		if ($Version) {
			foreach ($v in $WindowsCatalog) {
				if ($v.Name -match $Version -or $v.Code -match $Version) {
					$selectedVersionObj = $v
					break
				}
			}
		} else {
			$selectedVersionObj = $WindowsCatalog[0]
			if ($Verbosity -ge 1) {
				Write-Host "No version specified (-Ver). Defaulting to '$($selectedVersionObj.Name)'."
			}
		}

		if ($selectedVersionObj -eq $null) {
			Write-Host "Invalid Windows version."
			Write-Host "Use '-Ver List' to view available versions."
			exit 1
		}

		# Release Selection
		if ($Release -eq "List") {
			Write-Host "Available releases for $($selectedVersionObj.Name) (-Rel):"
			foreach ($r in $selectedVersionObj.Releases) {
				Write-Host " - $($r.Name) [Code: $($r.Code)]"
			}
			exit 0
		}

		$selectedReleaseObj = $null
		if ($Release) {
			foreach ($r in $selectedVersionObj.Releases) {
				if ($Release -eq "Latest" -or $r.Name -match $Release -or $r.Code -match $Release) {
					$selectedReleaseObj = $r
					break
				}
			}
		} else {
			$selectedReleaseObj = $selectedVersionObj.Releases[0]
			if ($Verbosity -ge 1) {
				Write-Host "No release specified (-Rel). Defaulting to '$($selectedReleaseObj.Name)'."
			}
		}

		if ($selectedReleaseObj -eq $null) {
			Write-Host "Invalid Windows release."
			Write-Host "Use '-Rel List' to view available releases."
			exit 1
		}

		# Edition Selection
		if ($Ed -eq "List") {
			Write-Host "Available editions for $($selectedReleaseObj.Name) (-Ed):"
			foreach ($e in $selectedReleaseObj.Editions) {
				Write-Host " - $($e.Name)"
			}
			exit 0
		}

		$selectedEditionObj = $null
		if ($Ed) {
			foreach ($e in $selectedReleaseObj.Editions) {
				if ($e.Name -match $Ed) {
					$selectedEditionObj = $e
					break
				}
			}
		} else {
			$selectedEditionObj = $selectedReleaseObj.Editions[0]
			if ($Verbosity -ge 1) {
				Write-Host "No edition specified (-Ed). Defaulting to '$($selectedEditionObj.Name)'."
			}
		}

		if ($selectedEditionObj -eq $null) {
			Write-Host "Invalid package edition."
			Write-Host "Use '-Ed List' to view available editions."
			exit 1
		}

		# Request Languages from Microsoft
		if ($Verbosity -ge 1) {
			Write-Host "Contacting Microsoft servers for available languages..."
		}
		$languages = Get-Windows-Languages $selectedEditionObj
		if (!$languages -or $languages.Count -eq 0) {
			Write-Host "Failed to retrieve languages from Microsoft servers."
			exit 1
		}

		if ($Lang -eq "List") {
			Write-Host "Available languages (-Lang):"
			foreach ($l in $languages) {
				Write-Host " - $($l.DisplayName) [Name: $($l.Name)]"
			}
			exit 0
		}

		$selectedLangObj = $null
		if ($Lang) {
			foreach ($l in $languages) {
				if ($l.Name -match $Lang -or $l.DisplayName -match $Lang) {
					$selectedLangObj = $l
					break
				}
			}
		} else {
			foreach ($l in $languages) {
				if ($l.Name -like "*English*" -or $l.DisplayName -like "*English*") {
					$selectedLangObj = $l
					break
				}
			}
			if (!$selectedLangObj) { $selectedLangObj = $languages[0] }
			if ($Verbosity -ge 1) {
				Write-Host "No language specified (-Lang). Defaulting to '$($selectedLangObj.DisplayName)'."
			}
		}

		if ($selectedLangObj -eq $null) {
			Write-Host "Invalid language specified."
			Write-Host "Use '-Lang List' to view available languages."
			exit 1
		}

		# Request Download Links
		$links = Get-Windows-Download-Links $selectedVersionObj.Page $selectedLangObj
		if (!$links -or $links.Count -eq 0) {
			Write-Host "Failed to retrieve ISO download links."
			exit 1
		}

		if ($Arch -eq "List") {
			Write-Host "Available architecture options (-Arch):"
			foreach ($a in $links) {
				Write-Host " - $($a.Arch)"
			}
			exit 0
		}

		$selectedArchObj = $null
		if ($Arch) {
			foreach ($a in $links) {
				if ($a.Arch -match $Arch -or $a.Name -match $Arch) {
					$selectedArchObj = $a
					break
				}
			}
			if (!$selectedArchObj -and $links.Count -eq 1) {
				$selectedArchObj = $links[0]
			}
		} else {
			$selectedArchObj = $links[0]
			if ($Verbosity -ge 1) {
				Write-Host "No architecture specified (-Arch). Defaulting to '$($selectedArchObj.Arch)'."
			}
		}

		if ($selectedArchObj -eq $null) {
			Write-Host "Invalid architecture."
			Write-Host "Use '-Arch List' to view available architecture options."
			exit 1
		}

		if ($GetUrl) {
			Write-Output $selectedArchObj.Url
			exit 0
		} else {
			Write-Host "Selected: $($selectedVersionObj.Name) - $($selectedReleaseObj.Name) - $($selectedEditionObj.Name) [$($selectedLangObj.DisplayName) - $($selectedArchObj.Arch)]"
			$isoFileName = ($selectedArchObj.Url.Split('?')[0]).Split('/')[-1]
			$ExitCode = Process-Download-Link $selectedArchObj.Url $isoFileName
			exit $ExitCode
		}
	}

	# ---------------- OFFICE CLI FLOW ----------------
	elseif ($selectedProduct -eq "Office") {
		# Version Selection
		if ($Version -eq "List") {
			Write-Host "Available Office versions (-Ver):"
			foreach ($v in $OfficeCatalog) {
				Write-Host " - $($v.Name) [Code: $($v.Code)]"
			}
			exit 0
		}

		$selectedVersionObj = $null
		if ($Version) {
			foreach ($v in $OfficeCatalog) {
				if ($v.Name -match $Version -or $v.Code -match $Version) {
					$selectedVersionObj = $v
					break
				}
			}
		} else {
			$selectedVersionObj = $OfficeCatalog[0]
			if ($Verbosity -ge 1) {
				Write-Host "No version specified (-Ver). Defaulting to '$($selectedVersionObj.Name)'."
			}
		}

		if ($selectedVersionObj -eq $null) {
			Write-Host "Invalid Office version."
			Write-Host "Use '-Ver List' to view available versions."
			exit 1
		}

		# Edition Selection
		if ($Ed -eq "List") {
			Write-Host "Available editions for $($selectedVersionObj.Name) (-Ed):"
			foreach ($e in $selectedVersionObj.Editions) {
				Write-Host " - $($e.Name) [Code: $($e.Code)]"
			}
			exit 0
		}

		$selectedEditionObj = $null
		if ($Ed) {
			foreach ($e in $selectedVersionObj.Editions) {
				if ($e.Name -match $Ed -or $e.Code -match $Ed) {
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
			Write-Host "Invalid package edition."
			Write-Host "Use '-Ed List' to view available editions."
			exit 1
		}

		# Language Selection
		if ($Lang -eq "List") {
			Write-Host "Available languages (-Lang):"
			foreach ($l in $OfficeLanguages) {
				Write-Host " - $($l.Display) [Code: $($l.Code)]"
			}
			exit 0
		}

		$selectedLangObj = $null
		if ($Lang) {
			foreach ($l in $OfficeLanguages) {
				if ($l.Code -match $Lang -or $l.Display -match $Lang) {
					$selectedLangObj = $l
					break
				}
			}
		} else {
			$defIdx = Select-Office-Language-Index $OfficeLanguages
			$selectedLangObj = $OfficeLanguages[$defIdx]
			if ($Verbosity -ge 1) {
				Write-Host "No language specified (-Lang). Defaulting to '$($selectedLangObj.Display)'."
			}
		}

		if ($selectedLangObj -eq $null) {
			Write-Host "Invalid language."
			Write-Host "Use '-Lang List' to view available languages."
			exit 1
		}

		# Architecture Selection
		if ($Arch -eq "List") {
			Write-Host "Available architecture options (-Arch):"
			foreach ($a in $OfficeArchitectures) {
				Write-Host " - $($a.Name) [Code: $($a.Code)]"
			}
			exit 0
		}

		$finalUrl = Build-Office-Url $selectedLangObj.Code $selectedEditionObj.Code $selectedEditionObj.Ext

		if ($GetUrl) {
			Write-Output $finalUrl
			exit 0
		} else {
			Write-Host "Selected: $($selectedVersionObj.Name) - $($selectedEditionObj.Name) [$($selectedLangObj.Display)]"
			$ExitCode = Process-Download-Link $finalUrl "$($selectedEditionObj.Code).$($selectedEditionObj.Ext)"
			exit $ExitCode
		}
	}
}
#endregion

#region GUI / WPF
# WPF Window definition in XAML
[xml]$XAML = @"
<Window xmlns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	Title = "isoMicrosoft" Height = "184" Width = "384" ResizeMode = "NoResize"
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
		$icon = [WinAPI.Utils]::ExtractIcon("imageres.dll", -109, $true)
		if ($icon) {
			$XMLForm.Icon = $icon | ConvertTo-ImageSource
		}
	} catch {}
}

if ($Locale.StartsWith("ar") -or $Locale.StartsWith("he")) {
	$XMLForm.FlowDirection = "RightToLeft"
}

$StepTitle.Text = Get-Translation("Product")
$Continue.Content = Get-Translation("Continue")
$Back.Content = Get-Translation("Close")

# Populate first list: Top-level Product selection
$StepChoice.ItemsSource = $ProductFamilies
$StepChoice.DisplayMemberPath = "Name"
$StepChoice.SelectedIndex = 0

# Track active selected product ("Windows" or "Office")
$script:ActiveProduct = "Windows"

# Handle Continue / Download button click
$Continue.add_click({
	$script:Stage++
	$XMLGrid.Children[2 * $Stage + 1].IsEnabled = $false
	$Continue.IsEnabled = $false
	$Back.IsEnabled = $false
	Refresh-Control($Continue)
	Refresh-Control($Back)

	# Etap 1: Product Family selected -> Branch into Windows or Office questions
	if ($Stage -eq 1) {
		$script:ActiveProduct = $StepChoice.SelectedItem.Code
		$Back.Content = Get-Translation("Back")
		$XMLForm.Title = $AppTitle

		if ($ActiveProduct -eq "Windows") {
			$script:SelectedVersionCombo = Add-Entry $Stage "Version" $WindowsCatalog "Name"
		} else {
			$script:SelectedVersionCombo = Add-Entry $Stage "Version" $OfficeCatalog "Name"
		}
	}

	# ---------------- WINDOWS STAGES ----------------
	elseif ($ActiveProduct -eq "Windows") {
		switch ($Stage) {
			2 {
				# Step 2: Version selected -> Populate releases
				$selectedVer = $script:SelectedVersionCombo.SelectedItem
				$script:SelectedReleaseCombo = Add-Entry $Stage "Release" $selectedVer.Releases "Name"
				$XMLForm.Title = $AppTitle
			}

			3 {
				# Step 3: Release selected -> Populate editions
				$selectedRel = $script:SelectedReleaseCombo.SelectedItem
				$script:SelectedEditionCombo = Add-Entry $Stage "Edition" $selectedRel.Editions "Name"
				$XMLForm.Title = $AppTitle
			}

			4 {
				# Step 4: Edition selected -> Request available languages from Microsoft servers
				$selectedEd = $script:SelectedEditionCombo.SelectedItem
				$XMLForm.Title = $(Get-Translation("Please wait..."))
				Refresh-Control($XMLForm)

				$langs = Get-Windows-Languages $selectedEd
				if (!$langs -or $langs.Count -eq 0) {
					Error "Unable to retrieve languages from Microsoft servers."
					return
				}

				$script:SelectedLanguageCombo = Add-Entry $Stage "Language" $langs "DisplayName"

				# Auto-select system locale or English
				$defIdx = 0
				$sysLoc = [System.Globalization.CultureInfo]::CurrentUICulture.Name.ToLower()
				for ($i = 0; $i -lt $langs.Count; $i++) {
					if ($langs[$i].Name.ToLower() -match "english" -or $langs[$i].DisplayName -match "English") {
						$defIdx = $i
					}
					if ($langs[$i].DisplayName.ToLower().Contains("pol") -and $sysLoc.StartsWith("pl")) {
						$defIdx = $i
						break
					}
				}
				$script:SelectedLanguageCombo.SelectedIndex = $defIdx
				$XMLForm.Title = $AppTitle
			}

			5 {
				# Step 5: Language selected -> Request download links and populate architecture
				$selectedLang = $script:SelectedLanguageCombo.SelectedItem
				$selectedVer = $script:SelectedVersionCombo.SelectedItem
				$XMLForm.Title = $(Get-Translation("Please wait..."))
				Refresh-Control($XMLForm)

				$links = Get-Windows-Download-Links $selectedVer.Page $selectedLang
				if (!$links -or $links.Count -eq 0) {
					Error "Unable to retrieve ISO links from Microsoft servers."
					return
				}

				$script:SelectedArchitectureCombo = Add-Entry $Stage "Architecture" $links "Name"
				$script:SelectedArchitectureCombo.SelectedIndex = 0

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

			6 {
				# Step 6: Click Download -> Execute Windows download
				$selectedArch = $script:SelectedArchitectureCombo.SelectedItem
				$finalUrl = $selectedArch.Url
				$isoName = ($finalUrl.Split('?')[0]).Split('/')[-1]

				$script:ExitCode = Process-Download-Link $finalUrl $isoName
				$XMLForm.Close()
			}
		}
	}

	# ---------------- OFFICE STAGES ----------------
	elseif ($ActiveProduct -eq "Office") {
		switch ($Stage) {
			2 {
				# Step 2: Version selected -> Populate editions
				$selectedVer = $script:SelectedVersionCombo.SelectedItem
				$script:SelectedEditionCombo = Add-Entry $Stage "Edition" $selectedVer.Editions "Name"
				$XMLForm.Title = $AppTitle
			}

			3 {
				# Step 3: Edition selected -> Populate languages
				$script:SelectedLanguageCombo = Add-Entry $Stage "Language" $OfficeLanguages "Display"
				$defLangIndex = Select-Office-Language-Index $OfficeLanguages
				$script:SelectedLanguageCombo.SelectedIndex = $defLangIndex
				$XMLForm.Title = $AppTitle
			}

			4 {
				# Step 4: Language selected -> Populate architecture & show Download
				$script:SelectedArchitectureCombo = Add-Entry $Stage "Architecture" $OfficeArchitectures "Name"
				$script:SelectedArchitectureCombo.SelectedIndex = 0

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

			5 {
				# Step 5: Click Download -> Generate link and execute Office download
				$selectedLang = $script:SelectedLanguageCombo.SelectedItem
				$selectedEd = $script:SelectedEditionCombo.SelectedItem
				$langCode = $selectedLang.Code
				$edCode = $selectedEd.Code
				$ext = $selectedEd.Ext
				$finalUrl = Build-Office-Url $langCode $edCode $ext

				$script:ExitCode = Process-Download-Link $finalUrl "$edCode.$ext"
				$XMLForm.Close()
			}
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

		# If collapsing from final download stage, hide browser checkbox
		$isFinalStage = ($ActiveProduct -eq "Windows" -and $Stage -eq 5) -or ($ActiveProduct -eq "Office" -and $Stage -eq 4)
		if ($isFinalStage) {
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
