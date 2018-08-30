# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

# parameters
param(
    [string] $environment = "",
    [string] $task = ""
)

# parameters
$currentFile = $MyInvocation.MyCommand.Definition
$PSScriptRoot = Split-Path -Parent -Path $currentFile

# check whether shell needs to be relaunched in 64 bit
if ($pshome -like "*syswow64*") {
    Write-Host "Detected 32-bit shell, restarting script under 64 bit powershell ..." -f DarkYellow
    & (join-path ($pshome -replace "syswow64", "sysnative") powershell.exe) -version 2 -file $currentFile $environment $task
    exit
}

# configure log level (0=debug, 1=info, 2=warning, 3=error)
Set-Variable -scope global -name log_level -value 1

# init script variables
Set-Location $PSScriptRoot
Set-Variable -scope global -name working_dir -value $PSScriptRoot
Set-Variable -scope global -name deployment_dir -value "$working_dir"
Set-Variable -scope global -name implementation_dir -value "$working_dir\..\implementation"
$start_time     = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
$log_file       = Get-Date -format yyyy-MM-dd


Write-Host ("-" * 80)
Write-Host ("Install tool started @ $start_time")
Write-Debug "arguments:   (environment: '$environment', task: '$task')"

Set-Variable -scope global -name env_dir                    -value "$deployment_dir\env"
Set-Variable -scope global -name lib_dir                    -value "$deployment_dir\lib"
Set-Variable -scope global -name content_dir                -value "$deployment_dir\files"
Set-Variable -scope global -name tasks_dir                  -value "$deployment_dir\tasks"

Import-Module $lib_dir\gridworks-installer.psm1 -force -global
Import-InstallerModules

# start transcript
$start_time     = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
$log_file       = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
if (-not (Test-Path "$deployment_dir\logs")) { mkdir "$deployment_dir\logs" | Out-Null }
Start-LogTranscript "$deployment_dir\logs\$log_file.log"

# set thread culture
Select-InstallerThreadCulture

# always prompt environment from user in installer.
$environment = Set-Environment $environment -resetGlobal
if (-not $environment) {
    Exit-Success "No environment choosen."
    Exit
}

Write-Host ("-" * 80)
Write-Info "Environment '$environment'"

Test-GwCommands
Connect-GwCurrentEnvironment

$selectedFolder = "tasks"
$selectedTask = $task
do {
    Import-InstallerModules

    $selectedTask = Set-Task $selectedTask $selectedFolder
    $selectedTaskDirectoryInfo = [System.IO.DirectoryInfo] $selectedTask

    while ($selectedTaskDirectoryInfo.Exists) {
        $selectedTask = ""
        $selectedFolder = $selectedTaskDirectoryInfo.FullName
        $selectedTask = Set-Task $selectedTask $selectedFolder
        $selectedTaskDirectoryInfo = [System.IO.DirectoryInfo] $selectedTask
    }

    $repeat = $selectedTask -ne $null

    if ($selectedTask) {
        $selectedName = Get-FileTitle( $selectedTask )

        Write-TimedBlock( $selectedName ) {
            . $selectedTask
        }

        $selectedTask = $null
    }

} while ($repeat)

Exit-Success
