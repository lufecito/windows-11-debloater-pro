# Windows 11 Debloater Pro

Herramienta profesional, auditable y autocontenida para preparar instalaciones nuevas de Windows 11. Elimina aplicaciones promocionales, reduce contenido sugerido y evita que las aplicaciones desaprovisionadas vuelvan a instalarse.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11)](https://www.microsoft.com/windows/windows-11)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Principios

- No descarga ni ejecuta código remoto.
- No elimina Microsoft Store, Windows Update, Defender, Terminal, Notepad, Calculadora, Fotos ni frameworks AppX.
- Desaprovisiona paquetes de la imagen para que no aparezcan en usuarios nuevos.
- Permite simular todos los cambios con `-WhatIf`.
- Genera respaldo del registro, logs y reporte JSON.
- Ofrece perfiles editables y una persistencia opcional para actualizaciones de características.

## Perfiles disponibles

| Perfil | Uso recomendado | Profundidad |
|---|---|---|
| `Minimal` | Equipos personales y pruebas piloto | Conservadora |
| `Balanced` | Instalación limpia de uso general | Recomendada |
| `Enterprise` | Estaciones corporativas administradas | Profunda |

La lista exacta de paquetes está en [`config/profiles.json`](config/profiles.json). Revísala y adáptala antes de un despliegue masivo.

## Inicio rápido

Abre PowerShell como administrador y ejecuta primero una simulación:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Invoke-Windows11Debloat.ps1 -Profile Balanced -WhatIf
```

Aplicar el perfil recomendado:

```powershell
.\Invoke-Windows11Debloat.ps1 -Profile Balanced
```

Instalación corporativa profunda con control persistente:

```powershell
.\Invoke-Windows11Debloat.ps1 -Profile Enterprise -InstallPersistence
```

Reiniciar el Explorador para ver inmediatamente los cambios de la barra de tareas:

```powershell
.\Invoke-Windows11Debloat.ps1 -Profile Balanced -RestartExplorer
```

## Cómo evita la reinstalación

La herramienta utiliza tres capas:

1. **Desaprovisionamiento AppX:** elimina el paquete instalado y su copia aprovisionada para usuarios futuros.
2. **Políticas de Cloud Content:** desactiva experiencias del consumidor, instalaciones silenciosas, sugerencias y contenido promocional.
3. **Cumplimiento persistente opcional:** `-InstallPersistence` instala una copia local y una tarea ejecutada como `SYSTEM` al iniciar Windows. Esto vuelve a aplicar el perfil después de actualizaciones de características.

La persistencia puede retirarse con:

```powershell
.\Remove-Persistence.ps1
```

Esta operación elimina la tarea y su copia local, pero conserva las políticas aplicadas.

## Qué configura

- Experiencias del consumidor y aplicaciones sugeridas.
- Instalaciones silenciosas de contenido promocional.
- Widgets, Chat y recomendaciones del Explorador.
- Integración web de Bing en la búsqueda.
- Recopilación de diagnóstico en el nivel permitido para Windows Pro.
- Funciones de análisis de IA/Recall cuando la política está disponible.

Las políticas no sustituyen una solución MDM. En entornos corporativos deben replicarse en Intune o GPO para convertirlas en la fuente de autoridad.

## Uso durante una instalación nueva

Momento recomendado:

1. Instala Windows 11 y completa OOBE.
2. Instala controladores y actualizaciones acumulativas.
3. Ejecuta el debloater como administrador.
4. Reinicia el equipo.
5. Instala las aplicaciones corporativas.
6. Une el equipo a Entra ID, dominio o plataforma MDM.

Para una imagen de referencia, ejecuta el script antes de `sysprep` y valida el resultado en una máquina virtual aislada.

## Parámetros

| Parámetro | Descripción |
|---|---|
| `-Profile` | `Minimal`, `Balanced` o `Enterprise` |
| `-ConfigurationPath` | Ruta a un archivo de perfiles personalizado |
| `-InstallPersistence` | Instala control de cumplimiento al inicio |
| `-SkipRestorePoint` | Omite la creación del punto de restauración |
| `-RestartExplorer` | Reinicia Explorer al terminar |
| `-OutputDirectory` | Cambia la carpeta de logs y reportes |
| `-WhatIf` | Simula sin modificar el equipo |
| `-Confirm` | Solicita confirmación por operación |

## Logs y recuperación

Los resultados se guardan en:

```text
C:\ProgramData\Windows11DebloaterPro
```

Incluyen:

- Registro cronológico `.log`.
- Reporte estructurado `.json`.
- Exportaciones `.reg` de las políticas existentes.
- Punto de restauración cuando Windows System Restore está disponible.

Las aplicaciones pueden reinstalarse desde Microsoft Store o mediante `winget`. Para restaurar políticas, importa los archivos `.reg` guardados antes de la ejecución.

## Despliegue empresarial

Prácticas recomendadas:

- Firma digitalmente los scripts.
- Mantén una copia versionada y revisada internamente.
- Ejecuta `-WhatIf` sobre la versión exacta de Windows que desplegarás.
- Prueba aplicaciones de línea de negocio, impresión, VPN, Microsoft 365 y autenticación.
- Usa Intune, GPO o RMM para políticas duraderas; la tarea incluida es apropiada para equipos no administrados o preparación técnica.

## Advertencias

Un debloater modifica la experiencia estándar de Windows. Microsoft puede cambiar nombres de paquetes o comportamiento de políticas entre versiones. Prueba siempre en un equipo piloto o máquina virtual antes de usarlo en producción.

## Licencia

Distribuido bajo licencia MIT. Consulta [LICENSE](LICENSE).
