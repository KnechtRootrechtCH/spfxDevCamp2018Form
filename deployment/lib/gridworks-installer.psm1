# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

function Exit-Installer {
    try {
        $out = Stop-Transcript | Out-Null
    }
    catch {}
    Set-Location $working_dir
    Write-Host ""
    exit
}

function Exit-Success {
    param(
        [string] $message = "Done."
    )
    if ($message) {
        Write-Success $message
    }
    Exit-Installer
}

function Exit-Failure {
    param(
        [string] $message = "Failed."
    )
    if ($message) {
        Write-Error $message
    }
    Exit-Installer
}

function Write-Usage {
    Get-Help .\install.ps1
    Exit-Installer
}

function Get-MenuItem( $items, $filter ) {
    $x = ($items | Where-Object {
            $match = $_.Code -eq $filter -or $_.Name -eq $filter
            Write-Debug "Get-MenuItem() : filter:=$filter, code:=$($_.Code), name:=$($_.Name) -> $match"
            return $match
        } | Select-Object -First 1).Value

    if ($x) {
        return $x
    }
}

function Get-MenuItemUserChoice( $items ) {

    # get maximum code length for string padding
    $maxlength = 0;
    $items | ForEach-Object {
        if ($_.Code -and $_.Code.Length -gt $maxlength) {
            $maxlength = $_.Code.Length
        }
    }

    # render the menu
    $items | ForEach-Object {
        $title = $_.Name
        if ($_.Description) {
            $title = $_.Description
        }
        if (-not $_.Code) {
            Write-Color -White $title
        }
        else {
            Write-Color -DarkGray " [" -Yellow $_.Code.ToString().PadLeft($maxlength) -DarkGray "] " -Gray $title
        }
    }

    write-Host
    Write-Host ">" -nonewline -b Magenta -f White
    $filter = [Console]::ReadLine()
    Write-Debug "User entered '$filter' ..."

    $x = Get-MenuItem $items $filter
    if (-not $x) {
        Write-Debug "User did not choose anything ..."
    }

    return $x
}


function Import-InstallerModules {
    @(
        "gridworks-common.psm1",
        "gridworks-provisioning",
        "gridworks-logging.psm1",
        "gridworks-logging-report.psm1",
        "gridworks-dev.psm1",
        "gridworks-release.psm1",
        "gridworks-git.psm1",
        "gridworks-watcher.psm1",
        "gridworks-translations.psm1",
        "gw-auth.psm1",
        "gw-setup.psm1"
    ) | ForEach-Object {
        $name = $_
        Get-Module | Where-Object { $_.Path -contains "$name" } | Remove-Module
        Import-Module "$($lib_dir)\$($name)" -force -global
    }
}

function Select-InstallerThreadCulture {
    try {
        $de = [System.Globalization.CultureInfo] "de-CH"

        $culture = [Threading.Thread]::CurrentThread.CurrentCulture
        if ($culture.Lcid -ne $de.Lcid) {
            Write-Step "Setting thread culture to $de (was: $culture) ..."
            [Threading.Thread]::CurrentThread.CurrentCulture = $de
        }

        $uiCulture = [Threading.Thread]::CurrentThread.CurrentUICulture
        if ($uiCulture.Lcid -ne $de.Lcid) {
            Write-Step "Setting thread ui culture to $de (was: $uiCulture) ..."
            [Threading.Thread]::CurrentThread.CurrentUICulture = $de
        }

    }
    catch {
        Write-Exception $_
        Exit-Failure
    }
}

function Select-Item( $items, $filter ) {
    if (-not $filter) {
        return $null
    }
    return ($items | Where-Object {
            $match = $_.Code -eq $filter -or $_.Name -eq $filter
            # Write-Host "Select-Item filter: $filter, code:$($_.Code), name: $($_.Name) -> $match"
            return $match
        } | Select-Object -First 1).Value
}

function Get-FileOrder( $path ) {
    if ($path) {
        $item = Get-Item $path
        if ($item) {
            if ($item -is [System.IO.FileInfo]) {
                $content = gc $path
                $content = "$content"
                $match = [Regex]::Match( $content, "# Order:([^#]*)" );
                if ($match -and $match.Success) {
                    return $match.Groups[1].Value.Trim()
                }
            }
        }
    }
    return $null
}

function Get-FileTitle( $path ) {
    if ($path) {
        $item = Get-Item $path
        if ($item) {
            if ($item -is [System.IO.FileInfo]) {
                $content = gc $path
                $content = "$content"
                $match = [Regex]::Match( $content, "# Title:([^#]*)" );
                if ($match -and $match.Success) {
                    return $match.Groups[1].Value.Trim()
                }
            }

            $value = $item.Name -replace (".ps1", "") -replace ("-", " ") -replace ("_", " ")
            $s = ""
            foreach ($word in ($value -split " ")) {
                if ($word.Length -gt 1) {
                    $word = $word.SubString(0, 1).ToUpper() + $word.SubString(1)
                }
                $s += "$word "
            }
            return $s.Trim()
        }
    }
    return $path
}

function Set-Environment {
    param(
        $environment = "",
        $globalName = "environment",
        [switch] $resetGlobal = $false
    )
    if ($resetGlobal) {
        Remove-Variable -scope global -name $globalName -ea SilentlyContinue
    }
    if (-not $environment) {
        $environment = Get-Variable -scope global -name $globalName -ea SilentlyContinue -ValueOnly
    }

    $choices = @()
    $values = @()
    $i = 1

    $options = @(
        @{ "Code" = "C"; Description = "Cancels and exits the script."; "Value" = "" };
        @{ "Code" = ""; Description = ""; };
    )

    # select only directories under env\
    $items = Get-ChildItem -path $env_dir | Where-Object { $_.PSIsContainer }
    $items | ForEach-Object {
        $options += @{ "Code" = "$i"; Description = "$($_.BaseName)"; "Value" = "$($_.Name)"; "Name" = "$($_.Name)" }
        $i++
    }

    $y = Select-Item $options $environment
    if ($y) {
        $environment = $y
    }

    if ( -not $environment) {
        Write-Color -White "`nPlease choose the environment to install" -Gray "(Default is 'C')."

        # get maximum code length for string padding
        $length = 0
        $options | ForEach-Object { $i = "$($_.Code)".Length; if ($i -gt $length) { $length = $i } }

        $options | ForEach-Object {
            if (-not $_.Code) {
                Write-Color -White $_.Description
            }
            else {
                Write-Color -DarkGray " [" -Yellow $_.Code.ToString().PadLeft($length) -DarkGray "] " -Gray $_.Description
            }
        }

        Write-Host
        Write-Host ">" -nonewline -b Magenta -f White
        $input = [Console]::ReadLine()
        $environment = Select-Item $options $input
    }

    Set-EnvironmentCommon
    Set-EnvironmentActual $environment

    Set-Variable -scope global -name $globalName -value $environment
    return $environment
}

function Set-EnvironmentCommon {

    # load common configuration file from.
    # must be dot-sourced in main scope.
    # if loaded in a function, variables are not available
    $init_path = "$env_dir\init.ps1"
    if (!(Test-Path $init_path)) {
        Exit-Failure "Failed to find common init file in $init_path!"
    }
    else {
        . $init_path
    }
}

function Set-EnvironmentActual {
    param(
        $environment = ""
    )

    # load environment configuration file.
    # must be dot-sourced in main scope.
    # if loaded in a function, variables are not available
    $init_path = "$env_dir\$environment\init.ps1"
    if (!(Test-Path $init_path )) {
        Exit-Failure "Failed to find environment init file in $init_path!"
    }
    else {
        . $init_path
    }
}

function Set-Task( $x = "", $path = "tasks" ) {

    $choices = @()
    $values = @()
    $i = 1

    # select all *.ps1 files under tasks\
    $items = Get-ChildItem -path "$path\*" -include "*.ps1"

    $versionTasks = $items | Where-Object { $_.Name -match "\d+\.\d+\.\d+\.ps1" }
    $latestVersionTask = $versionTasks | Sort-Object | Select-Object -Last 1
    $scriptTasks = $items | Where-Object { $_.Name -notMatch "\d+\.\d+\.\d+\.ps1" }

    $options = @(
        @{
            "Code"        = "C";
            "Description" = "Cancels and exits the script.";
            "Value"       = "";
        }
    );

    if ($latestVersionTask) {
        $options += @{
            "Code"        = "L";
            "Description" = "Update to the latest version (=$($latestVersionTask.BaseName))";
            "Value"       = "$($latestVersionTask.FullName)";
        }
    }

    # list all folders unter the current directory
    $folders = Get-ChildItem -path "$path\*" | ? { $_.PSIsContainer }
    $options += @{
        "Description" = "`nFolder Navigation:"
    }

    if (-not $path.EndsWith("tasks")) {
        $parentFolder = split-path -parent $path
        $options += @{
            "IsFolder"       = $true;
            "IsParentFolder" = $true;
            "Code"           = "$i";
            "Description"    = "...";
            "Value"          = "$parentFolder";
            "Name"           = "$i";
        }
        $i++
    }

    $folders | ForEach-Object {
        if ($_.Name -ne "content") {
            $options += @{
                "IsFolder"    = $true;
                "Code"        = "$i";
                "Description" = "$($_.BaseName)";
                "Value"       = "$($_.FullName)";
                "Name"        = "$($_.Name)";
            }
            $i++
        }
    }

    # list all scripts that follow the x.x.x.ps1 naming pattern
    if ($versionTasks) {
        $versionTasks | ForEach-Object {
            $options += @{
                "Code"        = "$i";
                "Description" = "$($_.BaseName)";
                "Value"       = "$($_.FullName)";
                "Name"        = "$($_.Name)"
            }
            $i++
        }
    }

    if ($scriptTasks) {
        $options += @{ Description = "`nScripts:" }

        $orderedScriptTasks = @()
        $order = 0;
        $customOrder = $false

        $scriptTasks | ForEach-Object {
            $orderedScriptTask = @{
                "Description" = "$($_.BaseName)";
                "Value"       = "$($_.FullName)";
                "Name"        = "$($_.Name)";
                "Order"       = $order
            }


            $fileOrder = Get-FileOrder $orderedScriptTask.Value
            if ($fileOrder) {
                $customOrder = $true
                $orderedScriptTask.Order = $fileOrder
            }

            $orderedScriptTasks += $orderedScriptTask
            $order += 10;
        }

        if ($customOrder) {
            $orderedScriptTasks = $orderedScriptTasks | Sort-Object { $_.Order -as [int] }
        }

        $orderedScriptTasks | ForEach-Object {
            $_.Code = "$i";
            $options += $_
            $i++
        }
    }

    $y = Select-Item $options $x
    if ($y) {
        $x = $y
    }

    $options | % {
        if (-not $_.IsParentFolder) {
            $fileTitle = Get-FileTitle $_.Value
            if ($fileTitle) {
                $_.Description = $fileTitle
            }
        }
    }

    # dump options to console:
    #$options |% { Write-Host "$($_.Code)".Padright(4), Write-Host "$($_.Order)".Padright(4), "$($_.Value)".Replace($deployment_dir, "").Padright(60), "$($_.Description)".Padright(40) }

    if ( -not $x ) {
        Write-Color -White "`nPlease choose the task to execute" -Gray "(Default is 'C')."

        # get maximum code length for string padding
        $length = 0
        $options | ForEach-Object {
            $i = "$($_.Code)".Length;
            if ($i -gt $length) {
                $length = $i
            }
        }

        # output all options.
        $options | ForEach-Object {
            if (-not $_.Code) {
                Write-Color -White $_.Description
            }
            else {
                Write-Color -DarkGray " [" -Yellow $_.Code.ToString().PadLeft($length) -DarkGray "] " -Gray $_.Description
            }
        }

        Write-Host ""
        Write-Host ">" -nonewline -b Magenta -f White
        $input = [Console]::ReadLine()
        $x = Select-Item $options $input
    }

    if ( -not $x ) {
        Exit-Success "No task choosen."
    }

    $x
}

Export-ModuleMember -Function *
