[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PlanetUrl,

    [Parameter(Mandatory = $true)]
    [string]$FileKey,

    [string]$NetworkId,

    [switch]$AllowInsecureHttp
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this script from an elevated PowerShell session.'
}

if ($PlanetUrl -notmatch '^https://') {
    if ($PlanetUrl -match '^http://' -and $AllowInsecureHttp) {
        Write-Warning 'Using a plain HTTP planet URL because -AllowInsecureHttp was set.'
    } else {
        Fail 'PlanetUrl must start with https:// unless -AllowInsecureHttp is set for http:// URLs.'
    }
}

function Get-ZeroTierCli {
    $candidates = @(
        'C:\ProgramData\ZeroTier\One\zerotier-cli.bat',
        'zerotier-cli.bat'
    )

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'ZeroTier\One\zerotier-cli.bat')
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'ZeroTier\One\zerotier-cli.bat')
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }
        $resolved = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($resolved) {
            return $resolved.Source
        }
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Install-ZeroTier {
    if (Get-ZeroTierCli) {
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source install --id=ZeroTier.ZeroTierOne -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0 -and (Get-ZeroTierCli)) {
            return
        }
        Write-Warning 'winget install failed or did not expose zerotier-cli; falling back to the official MSI.'
    }

    $msiPath = Join-Path $env:TEMP 'ZeroTier One.msi'
    Invoke-WebRequest -Uri 'https://download.zerotier.com/dist/ZeroTier%20One.msi' -OutFile $msiPath
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msiPath, '/qn', '/norestart') -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Fail "MSI installation failed with exit code $($process.ExitCode)."
    }
}

Install-ZeroTier

$zeroTierCli = Get-ZeroTierCli
if (-not $zeroTierCli) {
    Fail 'zerotier-cli.bat was not found after installation.'
}

$planetPath = 'C:\ProgramData\ZeroTier\One\planet'
$planetDir = Split-Path -Parent $planetPath
New-Item -ItemType Directory -Force -Path $planetDir | Out-Null

$tmpPlanet = Join-Path $env:TEMP ('zerotier-planet-{0}.planet' -f ([Guid]::NewGuid().ToString('N')))
$headers = @{
    Authorization = "Bearer $FileKey"
}

try {
    Invoke-WebRequest -Uri $PlanetUrl -Headers $headers -OutFile $tmpPlanet
    if ((Get-Item $tmpPlanet).Length -le 0) {
        Fail 'Downloaded planet file is empty.'
    }

    Copy-Item -Path $tmpPlanet -Destination $planetPath -Force

    Restart-Service -Name 'ZeroTierOneService' -Force

    if ($NetworkId) {
        & $zeroTierCli join $NetworkId
        if ($LASTEXITCODE -ne 0) {
            Fail "zerotier-cli join failed with exit code $LASTEXITCODE."
        }
    }

    Write-Host "ZeroTier planet installed successfully: $planetPath"
} finally {
    Remove-Item -Path $tmpPlanet -Force -ErrorAction SilentlyContinue
}
