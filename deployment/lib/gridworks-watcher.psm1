# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

function Stop-ProcessWhereCommandLineMatches {
    param(
        $name,
        $commandLine = $working_dir,
        $processName = ""
    )

    $matches = Get-WmiObject Win32_Process | Select-Object ProcessId, ProcessName, CommandLine
    $matches = $matches | Where-Object { "$($_.CommandLine)".Contains($commandLine) }
    $matches = $matches | Where-Object { "$($_.ProcessName)".Contains($processName) }
    if ($matches.Count -lt 1) {
        return;
    }

    Write-Step "Stopping $($matches.Count) $name ..."
    $matches = $matches | Foreach-Object {
        Write-SubStep "* Stopping: $($_.ProcessName) ($($_.ProcessId))"
        try {
            $p = Get-Process -Id $_.ProcessId -ea SilentlyContinue
            if ($p) {
                Stop-Process $p -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Start-Webpack {
    param(
        [switch] $production = $false,
        [switch] $profile = $false,
        [switch] $watch = $false,
        [switch] $wait = $true,
        [switch] $newWindow = $false
    )

    # laravel uses cross-env to set environment
    $arguments = "node_modules/cross-env/dist/bin/cross-env.js NODE_ENV="
    if ($production) {
        $arguments += "production"
    } else {
        $arguments += "development"
    }

    $arguments += " node_modules/webpack/bin/webpack.js";
    $arguments += " --config=node_modules/laravel-mix/setup/webpack.config.js";
    $arguments += " --labeled-modules";

    if ($profile) {
        $arguments += " --profile";
        #$arguments += " --display-modules"
        #$arguments += " --display-reasons"
        $arguments += " --env.bundle-analyzer";
    }

    $arguments += " --progress";

    if ($production) {
        $arguments += " --bail";
    }

    if ($watch) {
        $arguments += " --watch";
    }

    Set-Location $node_dir
    Write-Host "$arguments"

    $NoNewWindow = -not($newWindow)
    Start-Process -NoNewWindow:$NoNewWindow -Wait:$wait powershell.exe "& node.exe $arguments"
}

function Stop-WatchProcess {
    Stop-ProcessWhereCommandLineMatches "watcher scripts" "watcher.ps1"
    Stop-ProcessWhereCommandLineMatches "node processes" "$working_dir" "node.exe"
    Stop-ProcessWhereCommandLineMatches "cmder tabs" "/OMITHOOKSWARN"
}

function Initialize-FrontendBuild {
    Push-Location $node_dir
    Write-Step "Cleaning 'dist' folder ..."
    Remove-Item "$node_dir\dist" -Recurse -Force -Ea SilentlyContinue

    $nodeModulesMissing = -not (Test-Path "$node_dir\node_modules");
    $yarnCheckFailed = $false

    if ($nodeModulesMissing) {
        Write-Step "Directory 'node_modules' is missing ..."
    }

    if (-not $nodeModulesMissing) {

        $devDependencies = (Get-Content package.json) -join "`n" | ConvertFrom-Json | Select -ExpandProperty "devDependencies"
        foreach ($package in $devDependencies.PSObject.Properties) {
            $name = $package.name;

            $exists = (Test-Path "$node_dir\node_modules\$name");
            if (-not $exists) {
                Write-Step "Module $name is missing"
                $yarnCheckFailed = $true
                break;
            }
        }

        if (-not $yarnCheckFailed) {
            Write-Step "Executing 'yarn check' ..."
            $yarnCheck = ""
            try {
                $yarnCheck = . yarn check 2>&1
            } catch {
                $yarnCheck += "$_"
            }

            $yarnCheckFailed = "$yarnCheck".contains("not installed") -or "$yarnCheck".contains("wrong version");
            if ($yarnCheckFailed) {
                Write-Step "Yarn integrity check failed: $yarnCheck"
            }
        }
    }

    if ($nodeModulesMissing -or $yarnCheckFailed) {
        Invoke-Task yarn
    }

    Pop-Location
}

Export-ModuleMember -Function *
