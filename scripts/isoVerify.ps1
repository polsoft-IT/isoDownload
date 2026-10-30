<#
.SYNOPSIS
    isoVerify - Standalone ISO & File Checksum / Signature Verifier
.DESCRIPTION
    Standalone utility to calculate and verify cryptographic hashes (SHA256, SHA1, MD5)
    and Authenticode digital signatures for ISO images, installers, and disk images.
    Features an embedded database of known official Microsoft MSDN, Windows, Linux,
    and Rescue ISO hashes, clipboard hash matching, and progress feedback for multi-gigabyte files.
.PARAMETER Path
    Path to the file or ISO image to verify.
.PARAMETER ExpectedHash
    Expected hash string (SHA256, SHA1, or MD5) to compare against.
.PARAMETER Algorithm
    Hash algorithm to use in CLI mode (SHA256, SHA1, MD5). Default is SHA256.
.PARAMETER CheckDatabase
    Check calculated hash against the internal database of official release hashes.
.PARAMETER Gui
    Force graphical user interface (WPF).
.EXAMPLE
    .\isoVerify.ps1 -Path "Win11_24H2_English_x64.iso" -CheckDatabase
.EXAMPLE
    .\isoVerify.ps1 -Path "ubuntu-24.04-desktop-amd64.iso" -ExpectedHash "a435f6f3..."
.EXAMPLE
    .\isoVerify.ps1 -Gui
.NOTES
    Author: Sebastian Januchowski @ polsoft.ITS(TM) Dev
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$ExpectedHash,

    [ValidateSet("SHA256", "SHA1", "MD5")]
    [string]$Algorithm = "SHA256",

    [switch]$CheckDatabase,
    [switch]$Gui
)

$Script:Version = "1.2.0"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $PSScriptRoot 'isoCommon.psm1') -Force

$AppTitle = "isoVerify - ISO & File Integrity Checker"
$AppAuthor = "Sebastian Januchowski @ polsoft.ITS(TM) Dev"

# --- Known Official Hashes Database ---
$KnownHashes = @{
    # Windows 11
    "24H2_Win11_x64_EN" = @{
        Name   = "Windows 11 24H2 English x64 (Build 26100.1742)"
        SHA256 = "eb4c5fb3e0984f421f1c79c8d5d45d04ae05d76161fae4e1a63c46927f6e0c03"
        Size   = "5.4 GB"
    }
    "23H2_Win11_x64_EN" = @{
        Name   = "Windows 11 23H2v2 English x64 (Build 22631.2861)"
        SHA256 = "36ae905fb65d0c156e6f1e14b590a37b1fa303d40f745147fdf71744138e4e19"
        Size   = "6.2 GB"
    }
    "22H2_Win10_x64_EN" = @{
        Name   = "Windows 10 22H2 English x64 (Build 19045.2965)"
        SHA256 = "2f52c1110787a229871fe746a4d7d3d2a7167683ca51ae5d3369f91a547b744a"
        Size   = "5.7 GB"
    }
    "22H2_Win10_x86_EN" = @{
        Name   = "Windows 10 22H2 English x86 (Build 19045.2965)"
        SHA256 = "c89be1f60037a3c3aa3ef037e96a46132bb82142d76ffefd0725a3eb8a405100"
        Size   = "4.1 GB"
    }
    # Windows Server
    "Server2025_x64_EN" = @{
        Name   = "Windows Server 2025 Evaluation x64 (Build 26100.1742)"
        SHA256 = "3df02c4815fa258810b4d45d0c5a2c20a8fa7dce95914945f3dfbc6f9cf537b0"
        Size   = "5.1 GB"
    }
    "Server2022_x64_EN" = @{
        Name   = "Windows Server 2022 Evaluation x64 (Build 20348)"
        SHA256 = "3f326020468c2680674e2d1fe41a2afba7a6ebd916ac9962eef367eb6a987710"
        Size   = "4.7 GB"
    }
    "Server2019_x64_EN" = @{
        Name   = "Windows Server 2019 Evaluation x64 (Build 17763)"
        SHA256 = "608d0e466b44747eb4fe80f6ca4ef3592a4e5eeec682c3f875080e774ea059c2"
        Size   = "4.9 GB"
    }
    # Linux Distros
    "Ubuntu_2404_Desktop" = @{
        Name   = "Ubuntu 24.04 LTS Desktop amd64"
        SHA256 = "81fae9cc21e2b1e3a9a5256c5201fa47f6f9630e1b2d34fa1f002c1a73b69f7a"
        Size   = "5.8 GB"
    }
    "Ubuntu_2204_Desktop" = @{
        Name   = "Ubuntu 22.04.4 LTS Desktop amd64"
        SHA256 = "45a31eb93a8d227b686036cb56cb04c3558c42b10a273eb64f691eef2a870716"
        Size   = "4.6 GB"
    }
    "Debian_12_Netinst" = @{
        Name   = "Debian 12 Bookworm amd64 Netinst"
        SHA256 = "e3f169f4935e406325a7a972c4ce06c9fca448b1d6f1a8b13d2f9748b61c9e88"
        Size   = "628 MB"
    }
    "Proxmox_92" = @{
        Name   = "Proxmox Virtual Environment 9.2-1 ISO"
        SHA256 = "c0839e083c276ea9cb7da9b8bc6b5eb9726df21a224a1b02b9e28f38bc539824"
        Size   = "1.4 GB"
    }
    "Proxmox_82" = @{
        Name   = "Proxmox Virtual Environment 8.2-1 ISO"
        SHA256 = "72904c0ec2e91122a7f50a866c1e55047ae378853b0f5ef1ffdfdb7f041ff34e"
        Size   = "1.3 GB"
    }
    # Rescue & Utilities
    "Hiren_BootCD_PE" = @{
        Name   = "Hiren's BootCD PE x64 v1.0.8"
        SHA256 = "2f43cbcf62c4a919ca068ec2e9b2521c7e9921473fa0ca35ae03e7c858b29ec6"
        Size   = "2.8 GB"
    }
    "SystemRescue_13" = @{
        Name   = "SystemRescue 13.02 amd64"
        SHA256 = "266bb6b7e7a57a1e05dcb4ca02c38bf64157fa4cbe6a8dbb96a92823616aeec5"
        Size   = "950 MB"
    }
    "Rescuezilla_25" = @{
        Name   = "Rescuezilla 2.5.1 64-bit"
        SHA256 = "e1fb3c44fc54bbd73489814cf5f95fecfc5da3ef30894fe83bc9e73fae2c1da0"
        Size   = "1.2 GB"
    }
    "GParted_Live" = @{
        Name   = "GParted Live 1.8.1-1 amd64"
        SHA256 = "40be649f85c7c25a0b77b78a9c3d49f05a9ee95fca2818c4c7855b5502aa2fe7"
        Size   = "520 MB"
    }
}

# --- Core Calculation Function with Progress Callback ---
function Get-FileHashWithProgress {
    param(
        [string]$FilePath,
        [string]$HashAlgorithm = "SHA256",
        [scriptblock]$OnProgress = $null
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    $fileInfo = Get-Item -LiteralPath $FilePath
    $totalBytes = $fileInfo.Length

    $hasher = switch ($HashAlgorithm.ToUpper()) {
        "SHA256" { [System.Security.Cryptography.SHA256]::Create() }
        "SHA1"   { [System.Security.Cryptography.SHA1]::Create() }
        "MD5"    { [System.Security.Cryptography.MD5]::Create() }
        default  { [System.Security.Cryptography.SHA256]::Create() }
    }

    $buffer = New-Object byte[] (4 * 1024 * 1024) # 4MB buffer for maximum performance
    $stream = [System.IO.File]::OpenRead($FilePath)
    $bytesRead = 0
    $totalRead = 0
    $lastReportPercent = -1

    try {
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalRead += $bytesRead
            $hasher.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null

            if ($totalBytes -gt 0 -and $OnProgress) {
                $percent = [int][Math]::Floor(($totalRead / $totalBytes) * 100)
                if ($percent -ne $lastReportPercent) {
                    $lastReportPercent = $percent
                    & $OnProgress -Percent $percent -BytesRead $totalRead -TotalBytes $totalBytes
                }
            }
        }
        $hasher.TransformFinalBlock($buffer, 0, 0) | Out-Null
        $hashBytes = $hasher.Hash
        $hashString = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
        return $hashString
    }
    finally {
        $stream.Close()
        $stream.Dispose()
        $hasher.Dispose()
    }
}

# --- Database Lookup Function ---
function Find-KnownHashMatch {
    param([string]$CalculatedHash)
    $clean = $CalculatedHash.Trim().ToLower()
    foreach ($key in $KnownHashes.Keys) {
        $entry = $KnownHashes[$key]
        if ($entry.SHA256.ToLower() -eq $clean) {
            return $entry
        }
    }
    return $null
}

# --- CLI Execution Mode ---
if ($Path -and -not $Gui) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "File not found: $Path"
        exit 1
    }

    $targetFile = (Resolve-Path -LiteralPath $Path).Path
    $fileItem = Get-Item -LiteralPath $targetFile
    $sizeMB = [Math]::Round($fileItem.Length / 1MB, 2)
    Write-Host "`n=== isoVerify Integrity Checker ===" -ForegroundColor Cyan
    Write-Host "File: $($fileItem.Name)" -ForegroundColor White
    Write-Host "Size: $sizeMB MB ($($fileItem.Length) bytes)" -ForegroundColor Gray
    Write-Host "Hashing ($Algorithm)... Please wait." -ForegroundColor Yellow

    $hash = Get-FileHashWithProgress -FilePath $targetFile -HashAlgorithm $Algorithm -OnProgress {
        param($Percent)
        Write-Progress -Activity "Calculating $Algorithm hash" -Status "$Percent% complete" -PercentComplete $Percent
    }
    Write-Progress -Activity "Calculating $Algorithm hash" -Completed

    Write-Host "`nCalculated $($Algorithm):" -ForegroundColor White
    Write-Host $hash -ForegroundColor Yellow

    # Check Authenticode signature
    try {
        $sig = Get-AuthenticodeSignature -FilePath $targetFile -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -ne "NotSigned") {
            $sigColor = if ($sig.Status -eq "Valid") { "Green" } else { "Red" }
            Write-Host "`nAuthenticode Signature: $($sig.Status)" -ForegroundColor $sigColor
            if ($sig.SignerCertificate) {
                Write-Host "Signer: $($sig.SignerCertificate.Subject)" -ForegroundColor Gray
            }
        }
    } catch {}

    # Compare with expected hash if provided
    if ($ExpectedHash) {
        $cleanExpected = $ExpectedHash.Trim().ToLower()
        Write-Host "`nExpected Hash:   $cleanExpected" -ForegroundColor White
        Write-Host "Calculated Hash: $hash" -ForegroundColor White
        if ($hash.ToLower() -eq $cleanExpected) {
            Write-Host "`n[+] MATCH! Integrity verified successfully." -ForegroundColor Green
        } else {
            Write-Host "`n[-] MISMATCH! The file hash does not match expected value." -ForegroundColor Red
            exit 2
        }
    }

    # Compare with known database
    if ($CheckDatabase -or (-not $ExpectedHash)) {
        $match = Find-KnownHashMatch -CalculatedHash $hash
        if ($match) {
            Write-Host "`n[+] KNOWN OFFICIAL RELEASE MATCH!" -ForegroundColor Green
            Write-Host "Product: $($match.Name)" -ForegroundColor White
            Write-Host "Expected Size: $($match.Size)" -ForegroundColor Gray
        } else {
            Write-Host "`nDatabase check: No exact match found in built-in common release database." -ForegroundColor Gray
        }
    }

    Write-Host "`n$AppAuthor`n" -ForegroundColor DarkGray
    exit 0
}

# --- Graphical User Interface (WPF) ---

# Check STA thread mode required for WPF
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    Write-Host "Re-launching in STA mode for WPF GUI..." -ForegroundColor Cyan
    $procPath = (Get-Process -Id $PID).Path
    $procArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $PSCommandPath)
    if ($Path) { $procArgs += @("-Path", $Path) }
    $procArgs += "-Gui"
    Start-Process -FilePath $procPath -ArgumentList $procArgs
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="isoVerify"
    Height="680" Width="720"
    WindowStartupLocation="CenterScreen"
    Background="#181825"
    Foreground="#cdd6f4"
    FontFamily="Segoe UI"
    ResizeMode="CanMinimize"
    AllowDrop="True">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#45475a"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.4"/>
                    <Setter Property="Cursor" Value="Arrow"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1e1e2e"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="BorderBrush" Value="#45475a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Consolas, Segoe UI"/>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Margin="0,0,0,16" Padding="0,0,0,12" BorderBrush="#313244" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="isoVerify" FontSize="24" FontWeight="Bold" Foreground="#cba6f7"/>
                    <TextBlock Text="Cryptographic Hash, Authenticode &amp; MSDN Integrity Verifier" FontSize="12" Foreground="#a6adc8" Margin="0,3,0,0"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#313244" CornerRadius="6" Padding="10,6" VerticalAlignment="Center">
                    <TextBlock Text="STANDALONE TOOL" FontSize="11" FontWeight="Bold" Foreground="#89b4fa"/>
                </Border>
            </Grid>
        </Border>

        <!-- File Selection & Drag Drop Target -->
        <Border Grid.Row="1" Background="#1e1e2e" CornerRadius="8" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <TextBlock Grid.Row="0" Text="TARGET FILE (Drag &amp; Drop Supported):" FontSize="11" FontWeight="Bold" Foreground="#89dceb" Margin="0,0,0,6"/>
                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="TxtFilePath" Grid.Column="0" IsReadOnly="True" Margin="0,0,10,0"/>
                    <Button x:Name="BtnBrowse" Grid.Column="1" Content="Browse..." Width="90"/>
                </Grid>

                <Grid Grid.Row="2" Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="LblFileInfo" Grid.Column="0" Text="Select an ISO or drag and drop a file anywhere into this window." FontSize="12" Foreground="#6c7086" VerticalAlignment="Center"/>
                    <Button x:Name="BtnCalculate" Grid.Column="1" Content="Calculate Hashes" Background="#a6e3a1" Foreground="#11111b" Width="140" IsEnabled="False"/>
                </Grid>
            </Grid>
        </Border>

        <!-- Results & Comparison -->
        <Border Grid.Row="2" Background="#1e1e2e" CornerRadius="8" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel>
                    <!-- Progress Bar -->
                    <Grid x:Name="PnlProgress" Margin="0,0,0,12" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock x:Name="LblProgress" Grid.Row="0" Text="Calculating hash... 0%" FontSize="12" Foreground="#f9e2af" Margin="0,0,0,4"/>
                        <ProgressBar x:Name="PrgHash" Grid.Row="1" Height="8" Minimum="0" Maximum="100" Value="0" Foreground="#a6e3a1" Background="#313244" BorderThickness="0"/>
                    </Grid>

                    <!-- SHA-256 -->
                    <TextBlock Text="SHA-256:" FontSize="11" FontWeight="Bold" Foreground="#cba6f7" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtSHA256" Grid.Column="0" IsReadOnly="True" Margin="0,0,8,0"/>
                        <Button x:Name="BtnCopySHA256" Grid.Column="1" Content="Copy" Width="60"/>
                    </Grid>

                    <!-- SHA-1 -->
                    <TextBlock Text="SHA-1:" FontSize="11" FontWeight="Bold" Foreground="#89b4fa" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtSHA1" Grid.Column="0" IsReadOnly="True" Margin="0,0,8,0"/>
                        <Button x:Name="BtnCopySHA1" Grid.Column="1" Content="Copy" Width="60"/>
                    </Grid>

                    <!-- MD5 -->
                    <TextBlock Text="MD5:" FontSize="11" FontWeight="Bold" Foreground="#fab387" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,14">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtMD5" Grid.Column="0" IsReadOnly="True" Margin="0,0,8,0"/>
                        <Button x:Name="BtnCopyMD5" Grid.Column="1" Content="Copy" Width="60"/>
                    </Grid>

                    <!-- Expected Hash Input for Live Comparison -->
                    <TextBlock Text="COMPARE WITH EXPECTED HASH / CHECKSUM:" FontSize="11" FontWeight="Bold" Foreground="#f38ba8" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtExpected" Grid.Column="0" Margin="0,0,8,0" Text="" ToolTip="Paste expected SHA256, SHA1, or MD5 checksum to verify"/>
                        <Button x:Name="BtnPaste" Grid.Column="1" Content="Paste" Width="60"/>
                    </Grid>

                    <!-- Match Status Banner -->
                    <Border x:Name="BrdStatus" Background="#313244" CornerRadius="6" Padding="12,10" Margin="0,4,0,0">
                        <TextBlock x:Name="LblStatus" Text="No file calculated yet. Click 'Calculate Hashes' to begin." FontSize="13" FontWeight="SemiBold" Foreground="#cdd6f4" TextWrapping="Wrap"/>
                    </Border>
                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- Action Buttons -->
        <Grid Grid.Row="3" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="BtnCheckDb" Grid.Column="0" Content="Search Built-in Database of Official Releases" HorizontalAlignment="Left" Width="290"/>
            <Button x:Name="BtnClear" Grid.Column="1" Content="Clear" Width="80"/>
        </Grid>

        <!-- Footer -->
        <TextBlock Grid.Row="4" Text="Sebastian Januchowski @ polsoft.ITS(TM) Dev" FontSize="11" Foreground="#585b70" HorizontalAlignment="Center"/>
    </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $XAML
$Form = [System.Windows.Markup.XamlReader]::Load($Reader)

# Dynamically set Title to avoid XML entity issues
$Form.Title = $AppTitle

# Find Controls
$TxtFilePath   = $Form.FindName("TxtFilePath")
$BtnBrowse     = $Form.FindName("BtnBrowse")
$LblFileInfo   = $Form.FindName("LblFileInfo")
$BtnCalculate  = $Form.FindName("BtnCalculate")
$PnlProgress   = $Form.FindName("PnlProgress")
$LblProgress   = $Form.FindName("LblProgress")
$PrgHash       = $Form.FindName("PrgHash")
$TxtSHA256     = $Form.FindName("TxtSHA256")
$TxtSHA1       = $Form.FindName("TxtSHA1")
$TxtMD5        = $Form.FindName("TxtMD5")
$BtnCopySHA256 = $Form.FindName("BtnCopySHA256")
$BtnCopySHA1   = $Form.FindName("BtnCopySHA1")
$BtnCopyMD5    = $Form.FindName("BtnCopyMD5")
$TxtExpected   = $Form.FindName("TxtExpected")
$BtnPaste      = $Form.FindName("BtnPaste")
$BrdStatus     = $Form.FindName("BrdStatus")
$LblStatus     = $Form.FindName("LblStatus")
$BtnCheckDb    = $Form.FindName("BtnCheckDb")
$BtnClear      = $Form.FindName("BtnClear")

# Helper to update compare status
$UpdateCompareStatus = {
    $expected = $TxtExpected.Text.Trim().ToLower()
    $sha256 = $TxtSHA256.Text.Trim().ToLower()
    $sha1 = $TxtSHA1.Text.Trim().ToLower()
    $md5 = $TxtMD5.Text.Trim().ToLower()

    if ([string]::IsNullOrWhiteSpace($expected)) {
        if (-not [string]::IsNullOrWhiteSpace($sha256)) {
            $dbMatch = Find-KnownHashMatch -CalculatedHash $sha256
            if ($dbMatch) {
                $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e3a2f")
                $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
                $LblStatus.Text = "[+] OFFICIAL RELEASE VERIFIED: $($dbMatch.Name)"
            } else {
                $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
                $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#cdd6f4")
                $LblStatus.Text = "Hash calculation complete. Paste expected checksum above or search database."
            }
        }
        return
    }

    if ($expected -eq $sha256) {
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e3a2f")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
        $LblStatus.Text = "[+] MATCH! SHA-256 matches the expected checksum exactly."
    } elseif ($expected -eq $sha1) {
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e3a2f")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
        $LblStatus.Text = "[+] MATCH! SHA-1 matches the expected checksum exactly."
    } elseif ($expected -eq $md5) {
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e3a2f")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
        $LblStatus.Text = "[+] MATCH! MD5 matches the expected checksum exactly."
    } else {
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3f232b")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f38ba8")
        $LblStatus.Text = "[-] MISMATCH! The provided checksum does NOT match SHA-256, SHA-1, or MD5."
    }
}

# Helper to load file
$SetTargetFile = {
    param([string]$FilePath)
    if (Test-Path -LiteralPath $FilePath) {
        $item = Get-Item -LiteralPath $FilePath
        $TxtFilePath.Text = $item.FullName
        $sizeMB = [Math]::Round($item.Length / 1MB, 2)
        $LblFileInfo.Text = "$($item.Name)  ($sizeMB MB)"
        $BtnCalculate.IsEnabled = $true
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#cdd6f4")
        $LblStatus.Text = "File loaded. Ready to calculate hashes."
    }
}

# Drag & Drop Events
$Form.Add_DragEnter({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
    } else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
})

$Form.Add_Drop({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($files.Count -gt 0) {
            & $SetTargetFile -FilePath $files[0]
        }
    }
})

# Browse Button
$BtnBrowse.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select ISO, Image, or File to Verify"
    $dlg.Filter = "Disk Images (*.iso;*.img;*.vhd;*.esd;*.wim)|*.iso;*.img;*.vhd;*.esd;*.wim|All Files (*.*)|*.*"
    if ($dlg.ShowDialog()) {
        & $SetTargetFile -FilePath $dlg.FileName
    }
})

# Copy Buttons
$BtnCopySHA256.Add_Click({ if ($TxtSHA256.Text) { [System.Windows.Clipboard]::SetText($TxtSHA256.Text) } })
$BtnCopySHA1.Add_Click({ if ($TxtSHA1.Text) { [System.Windows.Clipboard]::SetText($TxtSHA1.Text) } })
$BtnCopyMD5.Add_Click({ if ($TxtMD5.Text) { [System.Windows.Clipboard]::SetText($TxtMD5.Text) } })

# Paste Button
$BtnPaste.Add_Click({
    if ([System.Windows.Clipboard]::ContainsText()) {
        $TxtExpected.Text = [System.Windows.Clipboard]::GetText().Trim()
        & $UpdateCompareStatus
    }
})

$TxtExpected.Add_TextChanged({
    & $UpdateCompareStatus
})

# Check Built-in Database
$BtnCheckDb.Add_Click({
    $sha256 = $TxtSHA256.Text.Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($sha256)) {
        [System.Windows.MessageBox]::Show("Please calculate the SHA-256 hash first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    $dbMatch = Find-KnownHashMatch -CalculatedHash $sha256
    if ($dbMatch) {
        $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e3a2f")
        $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
        $LblStatus.Text = "[+] OFFICIAL RELEASE VERIFIED: $($dbMatch.Name)`nExpected Size: $($dbMatch.Size)"
        [System.Windows.MessageBox]::Show("MATCH FOUND IN OFFICIAL DATABASE!`n`nProduct: $($dbMatch.Name)`nExpected Size: $($dbMatch.Size)`nSHA-256: $($dbMatch.SHA256)", "Authenticity Confirmed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } else {
        [System.Windows.MessageBox]::Show("No exact match found in the built-in database for this SHA-256 hash.`n`nTip: Custom builds, language packs, or newer versions may differ. You can paste the vendor-provided hash in the comparison box.", "No Direct Match", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

# Clear Button
$BtnClear.Add_Click({
    $TxtFilePath.Text = ""
    $LblFileInfo.Text = "Select an ISO or drag and drop a file anywhere into this window."
    $TxtSHA256.Text = ""
    $TxtSHA1.Text = ""
    $TxtMD5.Text = ""
    $TxtExpected.Text = ""
    $BtnCalculate.IsEnabled = $false
    $PnlProgress.Visibility = [System.Windows.Visibility]::Collapsed
    $BrdStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
    $LblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#cdd6f4")
    $LblStatus.Text = "Ready."
})

# Calculate Button
$BtnCalculate.Add_Click({
    $targetPath = $TxtFilePath.Text
    if (-not (Test-Path -LiteralPath $targetPath)) { return }

    $BtnCalculate.IsEnabled = $false
    $BtnBrowse.IsEnabled = $false
    $PnlProgress.Visibility = [System.Windows.Visibility]::Visible
    $LblProgress.Text = "Calculating SHA-256... 0%"
    $PrgHash.Value = 0

    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

    $progressCallback = {
        param($Percent, $BytesRead, $TotalBytes)
        $dispatcher.Invoke([Action]{
            $PrgHash.Value = $Percent
            $mbRead = [Math]::Round($BytesRead / 1MB, 0)
            $mbTotal = [Math]::Round($TotalBytes / 1MB, 0)
            $LblProgress.Text = "Calculating SHA-256... $Percent% ($mbRead / $mbTotal MB)"
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    try {
        # Calculate SHA256 with live progress
        $sha256 = Get-FileHashWithProgress -FilePath $targetPath -HashAlgorithm "SHA256" -OnProgress $progressCallback
        $TxtSHA256.Text = $sha256

        # Fast calculation for SHA1 & MD5 (using standard .NET stream)
        $LblProgress.Text = "Calculating SHA-1 & MD5..."
        $PrgHash.Value = 100
        $dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        $sha1 = Get-FileHashWithProgress -FilePath $targetPath -HashAlgorithm "SHA1"
        $TxtSHA1.Text = $sha1

        $md5 = Get-FileHashWithProgress -FilePath $targetPath -HashAlgorithm "MD5"
        $TxtMD5.Text = $md5

        & $UpdateCompareStatus
    }
    catch {
        [System.Windows.MessageBox]::Show("Error calculating hashes: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    finally {
        $PnlProgress.Visibility = [System.Windows.Visibility]::Collapsed
        $BtnCalculate.IsEnabled = $true
        $BtnBrowse.IsEnabled = $true
    }
})

# Preload path if provided via CLI
if ($Path) {
    & $SetTargetFile -FilePath $Path
}

# Run GUI
$Form.ShowDialog() | Out-Null
