#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Provisiona Windows 11 con una configuracion limpia, segura y repetible.

.DESCRIPTION
    Elimina aplicaciones opcionales para usuarios existentes y de la imagen
    aprovisionada, aplica politicas contra contenido sugerido, reduce telemetria
    y puede instalar una tarea de cumplimiento para evitar que las apps vuelvan
    despues de actualizaciones de caracteristicas.

.EXAMPLE
    .\Invoke-Windows11Debloat.ps1 -Profile Balanced -WhatIf

.EXAMPLE
    .\Invoke-Windows11Debloat.ps1 -Profile Enterprise -InstallPersistence
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Balanced', 'Minimal', 'Enterprise')]
    [string]$Profile = 'Balanced',

    [string]$ConfigurationPath = "$PSScriptRoot\config\profiles.json",

    [switch]$InstallPersistence,

    [switch]$SkipRestorePoint,

    [switch]$RestartExplorer,

    [string]$OutputDirectory = "$env:ProgramData\Windows11DebloaterPro"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Version = '1.0.0'
$script:StartedAt = Get-Date
$script:LogFile = $null
$script:ReportFile = $null
$script:Result = [ordered]@{
    RemovedInstalledPackages = [System.Collections.Generic.List[string]]::new()
    RemovedProvisionedPackages = [System.Collections.Generic.List[string]]::new()
    AppliedPolicies = [System.Collections.Generic.List[string]]::new()
    Skipped = [System.Collections.Generic.List[string]]::new()
    Warnings = [System.Collections.Generic.List[string]]::new()
    Errors = [System.Collections.Generic.List[string]]::new()
}

function Initialize-DebloatWorkspace {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = Join-Path $OutputDirectory "Debloat_$stamp.log"
    $script:ReportFile = Join-Path $OutputDirectory "Debloat_$stamp.json"
}

function Write-DebloatLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $colors = @{ INFO = 'Gray'; SUCCESS = 'Green'; WARNING = 'Yellow'; ERROR = 'Red' }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor $colors[$Level]

    if ($Level -eq 'WARNING') { $script:Result.Warnings.Add($Message) }
    if ($Level -eq 'ERROR') { $script:Result.Errors.Add($Message) }
}

function Get-Configuration {
    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
        throw "No se encontro la configuracion: $ConfigurationPath"
    }
    $configuration = Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $selected = $configuration.profiles.$Profile
    if ($null -eq $selected) { throw "El perfil '$Profile' no existe en la configuracion." }
    return $selected
}

function Backup-RegistryConfiguration {
    $backupDirectory = Join-Path $OutputDirectory 'RegistryBackup'
    if (-not (Test-Path -LiteralPath $backupDirectory)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }

    $keys = @{
        'CloudContent-HKLM.reg' = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        'WindowsAI-HKLM.reg' = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
        'DataCollection-HKLM.reg' = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        'ContentDelivery-HKCU.reg' = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    }
    foreach ($entry in $keys.GetEnumerator()) {
        $destination = Join-Path $backupDirectory $entry.Key
        & reg.exe export $entry.Value $destination /y 2>$null | Out-Null
    }
    Write-DebloatLog "Respaldo de registro disponible en $backupDirectory"
}

function New-SafeRestorePoint {
    if ($SkipRestorePoint) {
        Write-DebloatLog 'Punto de restauracion omitido por parametro'
        return
    }
    if (-not $PSCmdlet.ShouldProcess('System Restore', 'Crear punto de restauracion')) { return }

    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Windows11DebloaterPro-$($script:Version)" -RestorePointType MODIFY_SETTINGS
        Write-DebloatLog 'Punto de restauracion creado' 'SUCCESS'
    }
    catch {
        Write-DebloatLog "No fue posible crear un punto de restauracion: $($_.Exception.Message)" 'WARNING'
    }
}

function Set-RegistryPolicy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'String')]
        [string]$Type = 'DWord'
    )

    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "Establecer en $Value")) { return }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    $script:Result.AppliedPolicies.Add("$Path\$Name=$Value")
}

function Remove-AppxPattern {
    param([Parameter(Mandatory)][string]$Pattern)

    $protected = @(
        'Microsoft.WindowsStore',
        'Microsoft.StorePurchaseApp',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.WindowsTerminal',
        'Microsoft.WindowsNotepad',
        'Microsoft.Paint',
        'Microsoft.WindowsCalculator',
        'Microsoft.Windows.Photos',
        'Microsoft.SecHealthUI',
        'Microsoft.VCLibs',
        'Microsoft.UI.Xaml',
        'Microsoft.NET.Native',
        'Microsoft.WindowsAppRuntime',
        'Microsoft.AAD.BrokerPlugin',
        'Microsoft.AccountsControl',
        'Microsoft.LockApp',
        'Microsoft.ShellExperienceHost',
        'Microsoft.StartMenuExperienceHost'
    )
    if ($protected | Where-Object { $Pattern -like "*$_*" -or $_ -like "*$Pattern*" }) {
        $message = "Patron protegido omitido: $Pattern"
        $script:Result.Skipped.Add($message)
        Write-DebloatLog $message 'WARNING'
        return
    }

    $installed = Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction SilentlyContinue
    foreach ($package in $installed) {
        if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Eliminar Appx instalada para todos los usuarios')) {
            try {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                $script:Result.RemovedInstalledPackages.Add($package.Name)
                Write-DebloatLog "App instalada eliminada: $($package.Name)" 'SUCCESS'
            }
            catch {
                Write-DebloatLog "No se pudo eliminar $($package.Name): $($_.Exception.Message)" 'WARNING'
            }
        }
    }

    $provisioned = Get-AppxProvisionedPackage -Online |
        Where-Object { $_.DisplayName -like $Pattern }
    foreach ($package in $provisioned) {
        if ($PSCmdlet.ShouldProcess($package.PackageName, 'Desaprovisionar Appx de la imagen de Windows')) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
                $script:Result.RemovedProvisionedPackages.Add($package.DisplayName)
                Write-DebloatLog "App desaprovisionada: $($package.DisplayName)" 'SUCCESS'
            }
            catch {
                Write-DebloatLog "No se pudo desaprovisionar $($package.DisplayName): $($_.Exception.Message)" 'WARNING'
            }
        }
    }
}

function Disable-ConsumerReinstallation {
    $machinePolicies = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' = @{
            DisableWindowsConsumerFeatures = 1
            DisableCloudOptimizedContent = 1
            DisableConsumerAccountStateContent = 1
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' = @{
            AllowTelemetry = 1
            DisableOneSettingsDownloads = 1
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{
            DisableAIDataAnalysis = 1
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' = @{
            AllowNewsAndInterests = 0
        }
    }
    foreach ($path in $machinePolicies.Keys) {
        foreach ($name in $machinePolicies[$path].Keys) {
            Set-RegistryPolicy -Path $path -Name $name -Value $machinePolicies[$path][$name]
        }
    }

    $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $contentSettings = @{
        ContentDeliveryAllowed = 0
        OemPreInstalledAppsEnabled = 0
        PreInstalledAppsEnabled = 0
        PreInstalledAppsEverEnabled = 0
        SilentInstalledAppsEnabled = 0
        SoftLandingEnabled = 0
        SystemPaneSuggestionsEnabled = 0
        RotatingLockScreenEnabled = 0
        RotatingLockScreenOverlayEnabled = 0
    }
    foreach ($name in $contentSettings.Keys) {
        Set-RegistryPolicy -Path $contentPath -Name $name -Value $contentSettings[$name]
    }

    Set-RegistryPolicy -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0
    Set-RegistryPolicy -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0
    Set-RegistryPolicy -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0
    Set-RegistryPolicy -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Value 0
}

function Install-ComplianceTask {
    if (-not $InstallPersistence) { return }
    if (-not $PSCmdlet.ShouldProcess('Windows11DebloaterPro-Enforce', 'Instalar tarea de cumplimiento al iniciar')) { return }

    $installDirectory = Join-Path $env:ProgramData 'Windows11DebloaterPro\Enforcement'
    New-Item -ItemType Directory -Path (Join-Path $installDirectory 'config') -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $installDirectory 'Invoke-Windows11Debloat.ps1') -Force
    Copy-Item -LiteralPath $ConfigurationPath -Destination (Join-Path $installDirectory 'config\profiles.json') -Force

    $scriptPath = Join-Path $installDirectory 'Invoke-Windows11Debloat.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Profile $Profile -SkipRestorePoint"
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -StartWhenAvailable
    Register-ScheduledTask -TaskName 'Windows11DebloaterPro-Enforce' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description 'Mantiene el perfil de aprovisionamiento y elimina apps promocionales reprovisionadas.' -Force | Out-Null

    Write-DebloatLog 'Tarea persistente instalada: Windows11DebloaterPro-Enforce' 'SUCCESS'
}

function Export-DebloatReport {
    $report = [ordered]@{
        tool = 'Windows 11 Debloater Pro'
        version = $script:Version
        profile = $Profile
        computer = $env:COMPUTERNAME
        windows = [Environment]::OSVersion.VersionString
        startedAt = $script:StartedAt.ToString('o')
        finishedAt = (Get-Date).ToString('o')
        persistenceInstalled = [bool]$InstallPersistence
        results = $script:Result
        logFile = $script:LogFile
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
}

Initialize-DebloatWorkspace
Write-Host ''
Write-Host " Windows 11 Debloater Pro v$script:Version " -ForegroundColor Black -BackgroundColor Cyan
Write-Host " Perfil: $Profile | Equipo: $env:COMPUTERNAME"
Write-Host ''

try {
    $configuration = Get-Configuration
    Write-DebloatLog "Inicio de aprovisionamiento con perfil $Profile"
    Backup-RegistryConfiguration
    New-SafeRestorePoint

    foreach ($pattern in $configuration.removeApps) {
        Remove-AppxPattern -Pattern $pattern
    }

    Disable-ConsumerReinstallation
    Install-ComplianceTask

    if ($RestartExplorer -and $PSCmdlet.ShouldProcess('explorer.exe', 'Reiniciar para aplicar cambios visuales')) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    }

    Write-DebloatLog 'Aprovisionamiento completado' 'SUCCESS'
}
catch {
    Write-DebloatLog "Error no controlado: $($_.Exception.Message)" 'ERROR'
}
finally {
    Export-DebloatReport
}

Write-Host ''
Write-Host ' RESUMEN ' -ForegroundColor Black -BackgroundColor Green
Write-Host " Apps instaladas eliminadas    : $($script:Result.RemovedInstalledPackages.Count)"
Write-Host " Apps desaprovisionadas         : $($script:Result.RemovedProvisionedPackages.Count)"
Write-Host " Politicas aplicadas            : $($script:Result.AppliedPolicies.Count)"
Write-Host " Advertencias                   : $($script:Result.Warnings.Count)"
Write-Host " Errores                        : $($script:Result.Errors.Count)"
Write-Host " Reporte                        : $script:ReportFile"
Write-Host ''

if ($script:Result.Errors.Count -gt 0) { exit 1 }
exit 0
