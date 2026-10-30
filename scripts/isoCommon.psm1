<#
.SYNOPSIS
    isoCommon - Shared helper module for isoDownload Tools Hub scripts.
.DESCRIPTION
    Common logging, disk-space and hash helpers used by iso*.ps1 scripts.
    Import at the top of each script:
        Import-Module "$PSScriptRoot\isoCommon.psm1" -Force
.NOTES
    Author: Sebastian Januchowski @ polsoft.ITS(TM) Dev
#>

$Script:CommonVersion = "1.2.0"

# --- Logging -----------------------------------------------------------

function Write-Step {
    <#
    .SYNOPSIS
        Unified step logging with timestamp.
    .EXAMPLE
        Write-Step "Downloading ISO..."
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("Info", "Ok", "Warn", "Err")]
        [string]$Level = "Info"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Level) {
        "Ok"   { $color = "Green" }
        "Warn" { $color = "Yellow" }
        "Err"  { $color = "Red" }
        default { $color = "Cyan" }
    }
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

function Write-Err {
    <#
    .SYNOPSIS
        Error-level logging shortcut.
    #>
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Step -Message $Message -Level "Err"
}

# --- Disk space --------------------------------------------------------

function Get-FreeDiskGB {
    <#
    .SYNOPSIS
        Returns free disk space (GB) for the drive of a given path.
    .EXAMPLE
        Get-FreeDiskGB -Path "C:\iso"
    #>
    param(
        [string]$Path = (Get-Location).Path,

        [double]$MinimumGB = 10
    )
    $drive = if (Test-Path $Path) {
        (Get-Item $Path -ErrorAction SilentlyContinue).PSDrive
    } else {
        $null
    }
    if (-not $drive) {
        # fallback: root of path or current location
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $resolved) { $resolved = $Path }
        $root = [System.IO.Path]::GetPathRoot($resolved)
        $drive = Get-PSDrive -Name ($root.TrimEnd(':')) -ErrorAction SilentlyContinue
    }
    if (-not $drive) {
        Write-Err "Get-FreeDiskGB: could not resolve drive for '$Path'"
        return $null
    }
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGB -lt $MinimumGB) {
        Write-Step -Message ("Low disk space on {0}: - only {1} GB free (minimum {2} GB)" -f $drive.Name, $freeGB, $MinimumGB) -Level "Warn"
    }
    return $freeGB
}

# --- Hash verification --------------------------------------------------

function Test-FileHash {
    <#
    .SYNOPSIS
        Verifies a file hash (SHA256/SHA1/MD5) against an expected value.
    .OUTPUTS
        $true when the hash matches, otherwise $false.
    .EXAMPLE
        Test-FileHash -Path "Win11.iso" -Expected "abc123..." -Algorithm SHA256
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Expected,

        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256"
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Err "Test-FileHash: file not found: $Path"
        return $false
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
    $match = $actual -eq ($Expected -replace '\s', '').ToUpper()
    if ($match) {
        Write-Step -Message "$Algorithm hash OK: $Path" -Level "Ok"
    } else {
        Write-Err ("{0} hash MISMATCH for {1}`n  expected: {2}`n  actual:   {3}" -f $Algorithm, $Path, $Expected, $actual)
    }
    return $match
}

# --- Resumable downloads -----------------------------------------------

function Invoke-IsoDownload {
    <#
    .SYNOPSIS
        Downloads a file with BITS first and an HTTP range-resume fallback.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [string]$DisplayName = "ISO download",

        [string]$UserAgent = "isoDownload Tools Hub"
    )

    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    $destinationDirectory = [System.IO.Path]::GetDirectoryName($destinationPath)
    if (-not [System.IO.Directory]::Exists($destinationDirectory)) {
        [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    }

    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $Source -Destination $destinationPath -DisplayName $DisplayName -ErrorAction Stop
            Write-Progress -Activity $DisplayName -Completed
            return $destinationPath
        } catch {
            Write-Step -Message "BITS failed; continuing with resumable HTTP download: $($_.Exception.Message)" -Level "Warn"
        }
    }

    $existingLength = if ([System.IO.File]::Exists($destinationPath)) {
        (Get-Item -LiteralPath $destinationPath).Length
    } else {
        0L
    }

    $request = [System.Net.HttpWebRequest]::Create($Source)
    $request.UserAgent = $UserAgent
    $request.AllowAutoRedirect = $true
    if ($existingLength -gt 0) {
        $request.AddRange([long]$existingLength)
    }

    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $response = $request.GetResponse()
        $append = $existingLength -gt 0 -and $response.StatusCode -eq [System.Net.HttpStatusCode]::PartialContent
        $offset = if ($append) { $existingLength } else { 0L }
        $totalBytes = if ($response.ContentLength -ge 0) { $offset + $response.ContentLength } else { 0L }
        $fileMode = if ($append) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
        $outputStream = [System.IO.File]::Open($destinationPath, $fileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $inputStream = $response.GetResponseStream()
        $buffer = New-Object byte[] (1MB)
        $downloadedBytes = $offset

        while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $bytesRead)
            $downloadedBytes += $bytesRead
            $status = "{0:N1} MB downloaded" -f ($downloadedBytes / 1MB)
            if ($totalBytes -gt 0) {
                $percent = [int][Math]::Min(100, [Math]::Floor(($downloadedBytes / $totalBytes) * 100))
                Write-Progress -Activity $DisplayName -Status $status -PercentComplete $percent
            } else {
                Write-Progress -Activity $DisplayName -Status $status
            }
        }

        Write-Progress -Activity $DisplayName -Completed
        return $destinationPath
    } catch {
        Write-Progress -Activity $DisplayName -Completed
        throw
    } finally {
        if ($inputStream) { $inputStream.Dispose() }
        if ($outputStream) { $outputStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

# --- Export -------------------------------------------------------------

Export-ModuleMember -Function @('Write-Step', 'Write-Err', 'Get-FreeDiskGB', 'Test-FileHash', 'Invoke-IsoDownload')
