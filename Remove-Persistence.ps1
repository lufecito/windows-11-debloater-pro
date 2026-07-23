#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()

$taskName = 'Windows11DebloaterPro-Enforce'
$installDirectory = "$env:ProgramData\Windows11DebloaterPro\Enforcement"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($taskName, 'Eliminar tarea de cumplimiento')) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

if (Test-Path -LiteralPath $installDirectory) {
    if ($PSCmdlet.ShouldProcess($installDirectory, 'Eliminar archivos de cumplimiento')) {
        Remove-Item -LiteralPath $installDirectory -Recurse -Force
    }
}

Write-Host 'Persistencia eliminada. Las politicas aplicadas permanecen activas.' -ForegroundColor Green
