<#
.SYNOPSIS
    isoVentoy - Standalone Ventoy Multi-Boot USB Tool & ISO Manager
.DESCRIPTION
    Standalone utility to automate Ventoy multi-boot USB drive creation,
    manage ISO images, download the latest Ventoy package, configure Windows 11
    TPM/SecureBoot/Online Account bypass rules (ventoy.json), and copy ISO files
    with real-time progress feedback.
.PARAMETER ListDrives
    List all detected removable drives and USB volumes.
.PARAMETER DownloadVentoy
    Download and extract the latest official Ventoy package from GitHub.
.PARAMETER TargetDrive
    Drive letter of the USB drive (e.g., "E:" or "E:\").
.PARAMETER ConfigureBypass
    Generate or update ventoy.json on the target drive to bypass Windows 11 requirements (TPM, CPU, SecureBoot, NRO).
.PARAMETER CopyIso
    Path to an ISO file to copy to the target Ventoy drive.
.PARAMETER SourceDir
    Source folder to scan for ISO files to copy.
.PARAMETER Gui
    Force graphical user interface (WPF).
.EXAMPLE
    .\isoVentoy.ps1 -ListDrives
.EXAMPLE
    .\isoVentoy.ps1 -DownloadVentoy
.EXAMPLE
    .\isoVentoy.ps1 -TargetDrive "I:" -ConfigureBypass
.EXAMPLE
    .\isoVentoy.ps1 -TargetDrive "I:" -CopyIso "Win11_24H2_English_x64.iso"
.EXAMPLE
    .\isoVentoy.ps1 -Gui
.NOTES
    Author: Sebastian Januchowski @ polsoft.ITS(TM) Dev
#>

[CmdletBinding()]
param(
    [switch]$ListDrives,
    [switch]$DownloadVentoy,
    [string]$TargetDrive,
    [switch]$ConfigureBypass,
    [string]$CopyIso,
    [string]$SourceDir,
    [switch]$Gui
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $PSScriptRoot 'isoCommon.psm1') -Force

$Script:Version = "1.2.0"

$AppTitle = "isoVentoy - Multi-Boot USB & ISO Manager"
$AppAuthor = "Sebastian Januchowski @ polsoft.ITS(TM) Dev"

# Base directory for Ventoy package
$VentoyToolsDir = Join-Path -Path $env:TEMP -ChildPath "VentoyTools"

# --- Drive Enumeration Function ---
function Get-UsbDrives {
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    $results = @()
    foreach ($d in $drives) {
        $isVentoy = (Test-Path -LiteralPath (Join-Path $d.Name "ventoy")) -or ($d.VolumeLabel -like "*Ventoy*")
        $isRemovable = ($d.DriveType -eq [System.IO.DriveType]::Removable) -or $isVentoy
        
        $totalGB = [Math]::Round($d.TotalSize / 1GB, 2)
        $freeGB = [Math]::Round($d.AvailableFreeSpace / 1GB, 2)
        $label = if ([string]::IsNullOrWhiteSpace($d.VolumeLabel)) { "No Label" } else { $d.VolumeLabel }

        $results += [PSCustomObject]@{
            Letter      = $d.Name.TrimEnd('\')
            VolumeLabel = $label
            TotalGB     = $totalGB
            FreeGB      = $freeGB
            DriveType   = $d.DriveType.ToString()
            IsVentoy    = $isVentoy
            IsRemovable = $isRemovable
            Format      = $d.DriveFormat
        }
    }
    return $results
}

# --- Download Latest Ventoy Release ---
function Get-LatestVentoyRelease {
    param([scriptblock]$OnProgress = $null)

    if (-not (Test-Path -LiteralPath $VentoyToolsDir)) {
        New-Item -ItemType Directory -Path $VentoyToolsDir -Force | Out-Null
    }

    # Check existing Ventoy executable
    $existingExe = Get-ChildItem -Path $VentoyToolsDir -Recurse -Filter "Ventoy2Disk.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingExe) {
        return $existingExe.Directory.FullName
    }

    Write-Host "Fetching latest Ventoy release metadata from GitHub..." -ForegroundColor Cyan
    $downloadUrl = $null
    $fileName = "ventoy-windows.zip"

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ventoy/Ventoy/releases/latest" -Headers @{"User-Agent"="PowerShell"} -TimeoutSec 10
        $asset = $release.assets | Where-Object { $_.name -like "*windows.zip" } | Select-Object -First 1
        if ($asset) {
            $downloadUrl = $asset.browser_download_url
            $fileName = $asset.name
        }
    }
    catch {
        Write-Warning "GitHub API rate limit or network issue. Using direct release link fallback."
    }

    if (-not $downloadUrl) {
        $downloadUrl = "https://github.com/ventoy/Ventoy/releases/download/v1.1.18/ventoy-1.1.18-windows.zip"
        $fileName = "ventoy-1.1.18-windows.zip"
    }

    $zipPath = Join-Path -Path $VentoyToolsDir -ChildPath $fileName
    Write-Host "Downloading $fileName..." -ForegroundColor Yellow

    if (-not (Test-Path -LiteralPath $zipPath)) {
        Invoke-IsoDownload -Source $downloadUrl -Destination $zipPath -DisplayName "Ventoy package download" -UserAgent "PowerShell" | Out-Null
    }

    Write-Host "Extracting Ventoy package..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $zipPath -DestinationPath $VentoyToolsDir -Force

    $found = Get-ChildItem -Path $VentoyToolsDir -Recurse -Filter "Ventoy2Disk.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        Write-Host "Ventoy ready at: $($found.Directory.FullName)" -ForegroundColor Green
        return $found.Directory.FullName
    } else {
        throw "Ventoy2Disk.exe not found after extraction."
    }
}

# --- Configure ventoy.json ---
function Set-VentoyBypassConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,
        [bool]$BypassWin11Check = $true,
        [bool]$BypassNRO = $true
    )

    $cleanDrive = $DriveLetter.TrimEnd('\') + "\"
    if (-not (Test-Path -LiteralPath $cleanDrive)) {
        throw "Drive not accessible: $cleanDrive"
    }

    $ventoyDir = Join-Path -Path $cleanDrive -ChildPath "ventoy"
    if (-not (Test-Path -LiteralPath $ventoyDir)) {
        New-Item -ItemType Directory -Path $ventoyDir -Force | Out-Null
    }

    $configPath = Join-Path -Path $ventoyDir -ChildPath "ventoy.json"
    
    # Read existing config if present
    $controlArray = @()
    if ($BypassWin11Check) {
        $controlArray += @{ "VTOY_WIN11_BYPASS_CHECK" = "1" }
    }
    if ($BypassNRO) {
        $controlArray += @{ "VTOY_WIN11_BYPASS_NRO" = "1" }
    }
    $controlArray += @{ "VTOY_DEFAULT_MENU_MODE" = "0" }

    $jsonObj = @{
        "control" = $controlArray
    }

    $jsonContent = $jsonObj | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $configPath -Value $jsonContent -Encoding UTF8 -Force
    return $configPath
}

# --- Copy File with Progress ---
function Copy-FileWithProgress {
    param(
        [string]$SourceFile,
        [string]$DestinationDir,
        [scriptblock]$OnProgress = $null
    )

    if (-not (Test-Path -LiteralPath $SourceFile)) { throw "Source file not found: $SourceFile" }
    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $srcInfo = Get-Item -LiteralPath $SourceFile
    $destFile = Join-Path -Path $DestinationDir -ChildPath $srcInfo.Name
    $totalBytes = $srcInfo.Length

    $buffer = New-Object byte[] (8 * 1024 * 1024) # 8MB buffer
    $inStream = [System.IO.File]::OpenRead($SourceFile)
    $outStream = [System.IO.File]::Create($destFile)

    $bytesRead = 0
    $totalRead = 0
    $lastPercent = -1

    try {
        while (($bytesRead = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $bytesRead)
            $totalRead += $bytesRead

            if ($totalBytes -gt 0 -and $OnProgress) {
                $percent = [int][Math]::Floor(($totalRead / $totalBytes) * 100)
                if ($percent -ne $lastPercent) {
                    $lastPercent = $percent
                    & $OnProgress -Percent $percent -BytesCopied $totalRead -TotalBytes $totalBytes -FileName $srcInfo.Name
                }
            }
        }
        return $destFile
    }
    finally {
        $inStream.Close()
        $inStream.Dispose()
        $outStream.Close()
        $outStream.Dispose()
    }
}

# --- CLI Execution Handlers ---
if ($ListDrives -or $DownloadVentoy -or $TargetDrive -or $CopyIso) {
    if ($ListDrives) {
        Write-Host "`n=== Detected Storage Drives ===" -ForegroundColor Cyan
        $drives = Get-UsbDrives
        foreach ($d in $drives) {
            $tag = if ($d.IsVentoy) { "[VENTOY]" } elseif ($d.IsRemovable) { "[REMOVABLE]" } else { "[FIXED]" }
            $color = if ($d.IsVentoy) { "Green" } elseif ($d.IsRemovable) { "Yellow" } else { "Gray" }
            Write-Host (" {0,-5} {1,-12} {2,-10} {3,7} GB Free / {4,7} GB Total ({5})" -f $d.Letter, $tag, $d.VolumeLabel, $d.FreeGB, $d.TotalGB, $d.Format) -ForegroundColor $color
        }
        Write-Host "`n$AppAuthor`n" -ForegroundColor DarkGray
        exit 0
    }

    if ($DownloadVentoy) {
        $path = Get-LatestVentoyRelease
        Write-Host "`nVentoy ready at: $path" -ForegroundColor Green
        Write-Host "You can run Ventoy2Disk.exe to format / install Ventoy on your USB." -ForegroundColor White
        Write-Host "`n$AppAuthor`n" -ForegroundColor DarkGray
        exit 0
    }

    if ($TargetDrive -and $ConfigureBypass) {
        $cfg = Set-VentoyBypassConfig -DriveLetter $TargetDrive -BypassWin11Check $true -BypassNRO $true
        Write-Host "`n[+] Configured Windows 11 bypasses in $cfg" -ForegroundColor Green
        Write-Host "`n$AppAuthor`n" -ForegroundColor DarkGray
        exit 0
    }

    if ($TargetDrive -and $CopyIso) {
        $destDir = $TargetDrive.TrimEnd('\') + "\"
        Write-Host "`nCopying $CopyIso to $destDir..." -ForegroundColor Cyan
        $result = Copy-FileWithProgress -SourceFile $CopyIso -DestinationDir $destDir -OnProgress {
            param($Percent, $BytesCopied, $TotalBytes, $FileName)
            Write-Progress -Activity "Copying $FileName" -Status "$Percent% complete" -PercentComplete $Percent
        }
        Write-Progress -Activity "Copying $FileName" -Completed
        Write-Host "[+] ISO copied successfully: $result" -ForegroundColor Green
        Write-Host "`n$AppAuthor`n" -ForegroundColor DarkGray
        exit 0
    }
}

# --- GUI Launch (WPF) ---

# Check STA thread mode required for WPF
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    Write-Host "Re-launching in STA mode for WPF GUI..." -ForegroundColor Cyan
    $procPath = (Get-Process -Id $PID).Path
    $procArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $PSCommandPath, "-Gui")
    Start-Process -FilePath $procPath -ArgumentList $procArgs
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="isoVentoy"
    Height="720" Width="780"
    WindowStartupLocation="CenterScreen"
    Background="#181825"
    Foreground="#cdd6f4"
    FontFamily="Segoe UI"
    ResizeMode="CanMinimize">

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

        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#1e1e2e"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="BorderBrush" Value="#45475a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="ListView">
            <Setter Property="Background" Value="#1e1e2e"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="BorderBrush" Value="#313244"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
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
                    <TextBlock Text="isoVentoy" FontSize="24" FontWeight="Bold" Foreground="#a6e3a1"/>
                    <TextBlock Text="Ventoy Multi-Boot USB Manager &amp; ISO Copier" FontSize="12" Foreground="#a6adc8" Margin="0,3,0,0"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#313244" CornerRadius="6" Padding="10,6" VerticalAlignment="Center">
                    <TextBlock Text="STANDALONE TOOL" FontSize="11" FontWeight="Bold" Foreground="#89b4fa"/>
                </Border>
            </Grid>
        </Border>

        <!-- Drive Selector -->
        <Border Grid.Row="1" Background="#1e1e2e" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="SELECT TARGET USB DRIVE:" FontSize="11" FontWeight="Bold" Foreground="#89dceb" VerticalAlignment="Center"/>
                    <Button x:Name="BtnRefreshDrives" Grid.Column="1" Content="Refresh Drives" Width="110"/>
                </Grid>

                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <ComboBox x:Name="CmbDrives" Grid.Column="0" Margin="0,0,10,0"/>
                    <Button x:Name="BtnLaunchVentoy" Grid.Column="1" Content="Launch Ventoy2Disk" Background="#cba6f7" Foreground="#11111b" Width="150" ToolTip="Download and open Ventoy installer to format USB"/>
                </Grid>
            </Grid>
        </Border>

        <!-- ISO List in Current / Chosen Folder -->
        <Border Grid.Row="2" Background="#1e1e2e" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="AVAILABLE ISO IMAGES IN WORKSPACE:" FontSize="11" FontWeight="Bold" Foreground="#f9e2af" VerticalAlignment="Center"/>
                    <Button x:Name="BtnBrowseSource" Grid.Column="1" Content="Change Folder..." Width="120"/>
                </Grid>

                <!-- ISO List -->
                <ListView x:Name="LstIsos" Grid.Row="1" MinHeight="150">
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Header="Copy" Width="50">
                                <GridViewColumn.CellTemplate>
                                    <DataTemplate>
                                        <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center"/>
                                    </DataTemplate>
                                </GridViewColumn.CellTemplate>
                            </GridViewColumn>
                            <GridViewColumn Header="ISO File Name" Width="360" DisplayMemberBinding="{Binding Name}"/>
                            <GridViewColumn Header="Size" Width="90" DisplayMemberBinding="{Binding SizeDisplay}"/>
                            <GridViewColumn Header="Status on USB" Width="170" DisplayMemberBinding="{Binding Status}"/>
                        </GridView>
                    </ListView.View>
                </ListView>

                <Grid Grid.Row="2" Margin="0,8,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="LblIsoSummary" Grid.Column="0" Text="0 ISO files found." FontSize="12" Foreground="#a6adc8" VerticalAlignment="Center"/>
                    <Button x:Name="BtnSelectAll" Grid.Column="1" Content="Select All" Width="90"/>
                </Grid>
            </Grid>
        </Border>

        <!-- Ventoy Options & Bypasses -->
        <Border Grid.Row="3" Background="#1e1e2e" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="VENTOY CONFIGURATION &amp; WINDOWS 11 BYPASSES (ventoy.json):" FontSize="11" FontWeight="Bold" Foreground="#f38ba8" Margin="0,0,0,8"/>
                
                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <CheckBox x:Name="ChkWin11Check" Content="Bypass Windows 11 TPM 2.0, Secure Boot &amp; 4GB RAM checks (VTOY_WIN11_BYPASS_CHECK)" IsChecked="True"/>
                        <CheckBox x:Name="ChkWin11NRO" Content="Bypass Microsoft Online Account requirement - allow Local Account (VTOY_WIN11_BYPASS_NRO)" IsChecked="True"/>
                    </StackPanel>
                    <Button x:Name="BtnApplyConfig" Grid.Column="1" Content="Apply ventoy.json" Width="140" VerticalAlignment="Center"/>
                </Grid>
            </Grid>
        </Border>

        <!-- Progress and Actions -->
        <Grid Grid.Row="4" Margin="0,0,0,10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Copy Progress Bar -->
            <Grid x:Name="PnlProgress" Grid.Row="0" Margin="0,0,0,10" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock x:Name="LblProgress" Grid.Row="0" Text="Copying file... 0%" FontSize="12" Foreground="#89b4fa" Margin="0,0,0,4"/>
                <ProgressBar x:Name="PrgCopy" Grid.Row="1" Height="8" Minimum="0" Maximum="100" Value="0" Foreground="#89b4fa" Background="#313244" BorderThickness="0"/>
            </Grid>

            <!-- Primary Buttons -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="LblStatus" Grid.Column="0" Text="Select a drive and ISOs to copy to Ventoy." FontSize="13" Foreground="#cdd6f4" VerticalAlignment="Center"/>
                <Button x:Name="BtnCopySelected" Grid.Column="1" Content="Copy Selected ISOs to USB" Background="#89b4fa" Foreground="#11111b" Width="220" IsEnabled="False"/>
            </Grid>
        </Grid>

        <!-- Footer -->
        <TextBlock Grid.Row="5" Text="Sebastian Januchowski @ polsoft.ITS(TM) Dev" FontSize="11" Foreground="#585b70" HorizontalAlignment="Center"/>
    </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $XAML
$Form = [System.Windows.Markup.XamlReader]::Load($Reader)
$Form.Title = $AppTitle

# Controls
$BtnRefreshDrives = $Form.FindName("BtnRefreshDrives")
$CmbDrives        = $Form.FindName("CmbDrives")
$BtnLaunchVentoy  = $Form.FindName("BtnLaunchVentoy")
$BtnBrowseSource  = $Form.FindName("BtnBrowseSource")
$LstIsos          = $Form.FindName("LstIsos")
$LblIsoSummary    = $Form.FindName("LblIsoSummary")
$BtnSelectAll     = $Form.FindName("BtnSelectAll")
$ChkWin11Check    = $Form.FindName("ChkWin11Check")
$ChkWin11NRO      = $Form.FindName("ChkWin11NRO")
$BtnApplyConfig   = $Form.FindName("BtnApplyConfig")
$PnlProgress      = $Form.FindName("PnlProgress")
$LblProgress      = $Form.FindName("LblProgress")
$PrgCopy          = $Form.FindName("PrgCopy")
$LblStatus        = $Form.FindName("LblStatus")
$BtnCopySelected  = $Form.FindName("BtnCopySelected")

# Global State
$Script:CurrentSourceDir = if ($SourceDir -and (Test-Path -LiteralPath $SourceDir)) { (Resolve-Path $SourceDir).Path } else { (Get-Location).Path }
$Script:IsoCollection = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$LstIsos.ItemsSource = $Script:IsoCollection

# Refresh Drive List
$PopulateDrives = {
    $CmbDrives.Items.Clear()
    $drives = Get-UsbDrives
    $selectedIndex = -1
    $index = 0

    foreach ($d in $drives) {
        $tag = if ($d.IsVentoy) { "[VENTOY]" } elseif ($d.IsRemovable) { "[USB]" } else { "[DRIVE]" }
        $displayText = "$($d.Letter) $tag $($d.VolumeLabel) - $($d.FreeGB) GB Free / $($d.TotalGB) GB"
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $displayText
        $item.Tag = $d
        $CmbDrives.Items.Add($item) | Out-Null

        if ($selectedIndex -eq -1 -and ($d.IsVentoy -or $d.IsRemovable)) {
            $selectedIndex = $index
        }
        $index++
    }

    if ($selectedIndex -ge 0) {
        $CmbDrives.SelectedIndex = $selectedIndex
    } elseif ($CmbDrives.Items.Count -gt 0) {
        $CmbDrives.SelectedIndex = 0
    }
}

# Scan ISOs in current folder
$ScanIsoFiles = {
    $Script:IsoCollection.Clear()
    if (-not (Test-Path -LiteralPath $Script:CurrentSourceDir)) { return }

    $targetDriveObj = if ($CmbDrives.SelectedItem) { $CmbDrives.SelectedItem.Tag } else { $null }
    $targetPath = if ($targetDriveObj) { $targetDriveObj.Letter + "\" } else { $null }

    $isoFiles = Get-ChildItem -LiteralPath $Script:CurrentSourceDir -Filter "*.iso" -ErrorAction SilentlyContinue
    $count = 0
    foreach ($f in $isoFiles) {
        $sizeMB = [Math]::Round($f.Length / 1MB, 0)
        $sizeGB = [Math]::Round($f.Length / 1GB, 2)
        $sizeDisplay = if ($sizeGB -ge 1) { "$sizeGB GB" } else { "$sizeMB MB" }

        $status = "Not on USB"
        if ($targetPath -and (Test-Path -LiteralPath (Join-Path $targetPath $f.Name))) {
            $status = "[Already on USB]"
        }

        $obj = [PSCustomObject]@{
            IsSelected  = $false
            Name        = $f.Name
            FullName    = $f.FullName
            Length      = $f.Length
            SizeDisplay = $sizeDisplay
            Status      = $status
        }
        $Script:IsoCollection.Add($obj)
        $count++
    }

    $LblIsoSummary.Text = "$count ISO files found in: $Script:CurrentSourceDir"
    $BtnCopySelected.IsEnabled = ($count -gt 0)
}

# Drive Selection Changed
$CmbDrives.Add_SelectionChanged({
    & $ScanIsoFiles
})

# Refresh Drives Button
$BtnRefreshDrives.Add_Click({
    & $PopulateDrives
    & $ScanIsoFiles
})

# Change Source Folder
$BtnBrowseSource.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select folder containing ISO images"
    $dlg.SelectedPath = $Script:CurrentSourceDir
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Script:CurrentSourceDir = $dlg.SelectedPath
        & $ScanIsoFiles
    }
})

# Select All Button
$BtnSelectAll.Add_Click({
    $hasUnselected = $false
    foreach ($item in $Script:IsoCollection) {
        if (-not $item.IsSelected) { $hasUnselected = $true; break }
    }
    foreach ($item in $Script:IsoCollection) {
        $item.IsSelected = $hasUnselected
    }
    $LstIsos.Items.Refresh()
})

# Download & Launch Ventoy2Disk
$BtnLaunchVentoy.Add_Click({
    $BtnLaunchVentoy.IsEnabled = $false
    $LblStatus.Text = "Checking Ventoy installation package..."
    
    try {
        $ventoyDir = Get-LatestVentoyRelease
        $exe = Join-Path -Path $ventoyDir -ChildPath "Ventoy2Disk.exe"
        if (Test-Path -LiteralPath $exe) {
            $LblStatus.Text = "Ventoy ready. Opening Ventoy2Disk..."
            Start-Process -FilePath $exe
        } else {
            [System.Windows.MessageBox]::Show("Ventoy2Disk.exe was not found in: $ventoyDir", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error getting Ventoy: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    finally {
        $BtnLaunchVentoy.IsEnabled = $true
    }
})

# Apply ventoy.json bypass config
$BtnApplyConfig.Add_Click({
    $selected = $CmbDrives.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select a target USB drive first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $driveObj = $selected.Tag
    $driveLetter = $driveObj.Letter

    try {
        $cfgPath = Set-VentoyBypassConfig -DriveLetter $driveLetter -BypassWin11Check $ChkWin11Check.IsChecked -BypassNRO $ChkWin11NRO.IsChecked
        $LblStatus.Text = "Windows 11 bypasses applied to: $cfgPath"
        [System.Windows.MessageBox]::Show("Success! ventoy.json created/updated.`n`nFile: $cfgPath`n- Bypass TPM/CPU/SecureBoot: $($ChkWin11Check.IsChecked)`n- Bypass Online Account (NRO): $($ChkWin11NRO.IsChecked)", "Ventoy Configured", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        [System.Windows.MessageBox]::Show("Error applying config: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Copy Selected ISOs to USB
$BtnCopySelected.Add_Click({
    $selectedDrive = $CmbDrives.SelectedItem
    if (-not $selectedDrive) {
        [System.Windows.MessageBox]::Show("Please select a target USB drive first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $selectedIsos = @($Script:IsoCollection | Where-Object { $_.IsSelected })
    if ($selectedIsos.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please check the 'Copy' box for at least one ISO image in the list.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    $driveObj = $selectedDrive.Tag
    $targetPath = $driveObj.Letter + "\"

    # Check free space
    $totalRequired = 0
    foreach ($iso in $selectedIsos) { $totalRequired += $iso.Length }
    $requiredGB = [Math]::Round($totalRequired / 1GB, 2)
    
    if ($totalRequired -gt ($driveObj.FreeGB * 1GB)) {
        $ans = [System.Windows.MessageBox]::Show("The selected ISOs require $requiredGB GB, but the drive only reports $($driveObj.FreeGB) GB free.`n`nDo you want to continue anyway?", "Disk Space Warning", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $BtnCopySelected.IsEnabled = $false
    $BtnRefreshDrives.IsEnabled = $false
    $BtnLaunchVentoy.IsEnabled = $false
    $PnlProgress.Visibility = [System.Windows.Visibility]::Visible

    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

    try {
        $idx = 1
        $totalCount = $selectedIsos.Count

        foreach ($iso in $selectedIsos) {
            $LblProgress.Text = "[$idx/$totalCount] Copying $($iso.Name)... 0%"
            $PrgCopy.Value = 0

            $copyCallback = {
                param($Percent, $BytesCopied, $TotalBytes, $FileName)
                $dispatcher.Invoke([Action]{
                    $PrgCopy.Value = $Percent
                    $mbCopied = [Math]::Round($BytesCopied / 1MB, 0)
                    $mbTotal = [Math]::Round($TotalBytes / 1MB, 0)
                    $LblProgress.Text = "[$idx/$totalCount] Copying $FileName... $Percent% ($mbCopied / $mbTotal MB)"
                }, [System.Windows.Threading.DispatcherPriority]::Background)
            }

            Copy-FileWithProgress -SourceFile $iso.FullName -DestinationDir $targetPath -OnProgress $copyCallback
            $iso.Status = "[Already on USB]"
            $idx++
        }

        $LstIsos.Items.Refresh()
        $LblStatus.Text = "All $totalCount selected ISO files copied successfully!"
        [System.Windows.MessageBox]::Show("All selected ISO files were successfully copied to $targetPath!", "Transfer Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        [System.Windows.MessageBox]::Show("Error copying files: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    finally {
        $PnlProgress.Visibility = [System.Windows.Visibility]::Collapsed
        $BtnCopySelected.IsEnabled = $true
        $BtnRefreshDrives.IsEnabled = $true
        $BtnLaunchVentoy.IsEnabled = $true
        & $PopulateDrives
    }
})

# Initialize UI
& $PopulateDrives
& $ScanIsoFiles

# Pre-select target drive if provided via CLI
if ($TargetDrive) {
    for ($i = 0; $i -lt $CmbDrives.Items.Count; $i++) {
        $d = $CmbDrives.Items[$i].Tag
        if ($d.Letter.ToLower() -eq $TargetDrive.TrimEnd('\').ToLower()) {
            $CmbDrives.SelectedIndex = $i
            break
        }
    }
}

# Run GUI
$Form.ShowDialog() | Out-Null
