#-------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
#-------------------------------------------------------------------

function Test-GitStatus {
    return [bool](Get-Command -Name 'Get-GitStatus' -ErrorAction SilentlyContinue)
}
function Get-ExternalTool {
    param (
        $fileName,
        $path
    )
    if (-not $fileName) {
        Throw "filename must not be empty!"
    }
    if (-not $path) {
        Throw "path must not be empty!"
    }

    Write-Debug "Looking for tool $fileName in path $path"
    $item = Get-ChildItem -include $fileName -recurse -path $path | Sort LastWriteTime -Descending | Select -First 1

    if ($item -eq $null -or (Test-Path $item.Fullname) -eq $false) {
        Throw "$fileName was not found in $path or its subdirectories!"
    }

    return $item.Fullname
}

function EnsurePaths {

    if ((Test-Path $externals_dir) -eq $false) {
        mkdir -Path $externals_dir | Out-Null
    }

    if ((Test-Path $wsp_dir) -eq $false){
        mkdir -Path $wsp_dir | Out-Null
    }

    # Create optional directories only if defined
    if ($out_dir -ne $null -and (Test-Path $out_dir) -eq $false){
        mkdir -Path $out_dir | Out-Null
    }

    if ($tests_dir -ne $null -and (Test-Path $tests_dir) -eq $false){
        mkdir -Path $tests_dir | Out-Null
    }


    $repositories | ForEach {
        if ($_.path -eq $null) {
            if ($_.external -eq $true) {
                $_.path = "$externals_dir\$($_.name)"
            } else {
                $_.path = "$working_dir\$($_.path)"
            }
        }

        $_.exists = $false
        try {
            $item = Get-Item $_.path
            $_.path = $item.FullName
            $_.exists = $item.Exists
        } catch {
        }
    }
}

function Set-DatabaseSimpleRecovery {
    param(
        $app
    )

    if ($app) {
        Write-Warning "Must specify an application config."
    }

    Write-Step "changing recovery model of $($app.content_db) to simple"
    Import-AssemblyFromGac "Microsoft.SqlServer.SMO"

    $smo_server = New-Object ('Microsoft.SqlServer.Management.Smo.Server') -argumentlist $app.db_server
    $smo_server.Databases | where {$_.Name -eq $app.content_db } | foreach {
        $_.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple; $_.Alter()
    }
}

function Remove-Directory {
    param(
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $path
    )
    process {
        $exists = Test-Path $path
        if ($exists) {
            try {
                $relativePath = $path.ToString().Replace($working_dir, "")
                Write-Debug "Deleting directory $relativePath ..."
                Remove-Item $path -Recurse -Force
            } catch {
                Write-Error "Failed to delete $relativePath -> $_"
                #Info "The following programs have open references:"
                #handle $path
            }
        }
    }
}

function Start-MsBuild {
    Param(
        [string] $target = "rebuild",
        [string] $solution = "",
        [string] $verbosity = "quiet",
        [string] $configuration = "Debug",
        [switch] $output_cmd = $true,
        [switch] $performance = $false,

        # build parameter that drives the inclusion of the sharepoint targets from the path
        # C:\Program Files (x86)\MSBuild\Microsoft\VisualStudio\v11.0\SharePointTools\Microsoft.VisualStudio.SharePoint.targets
        # if they are included, the wsp solution package is built on every build action.
        # we disable that, and build the wsp only if overriden explictely or on release build.
        [switch] $package = $false
    )

    $msbuild = Get-MsBuildPath

    if ((Test-Path $solution) -eq $false){
        Throw "Solution file $solution does not exist!"
    }

    $consoleLoggerParameters = "/clp:NoSummary /clp:Verbosity=$verbosity"
    if ($performance) {
        $consoleLoggerParameters = " /clp:PerformanceSummary"
    }

    $nologo = "/nologo"
    $target = "/t:$target"
    $verbosity = "/v:$verbosity"
    $isPackaging = "/p:IsPackaging=$package"
    $maxCpuCount = "/maxcpucount"
    $vsVersion = "/p:VisualStudioVersion=15.0"

    $configuration -split "," | ForEach {
        $configuration = "/p:Configuration=$_"

        $name = (Get-Item $solution).Name
        if ($target -match "clean") {
            Write-Debug "Cleaning " -Highlight $name -Normal "..."
            Write-Debug "Configuration" -Highlight $configuration -Normal "..."
        } else {
            Write-Debug "Building" -Highlight $name -Normal "..."
            Write-Debug "Configuration" -Highlight $configuration -Normal "..."
            Write-Debug "Target" -Highlight $target -Normal "..."
        }

        try {
            & $msbuild $solution $nologo $target $verbosity $consoleLoggerParameters $configuration $isPackaging $maxCpuCount $vsVersion 2>&1

        } catch {
            Write-Debug "& $msbuild $solution $nologo $target $verbosity $consoleLoggerParameters $configuration $isPackaging $maxCpuCount $vsVersion 2>&1"
            Write-Error $_
            throw "Error while building $name!"
        }
    }
}

function Get-MsBuildPath {
    # use visual studio 2015 build as preferred version.
    # if not available, fall back to .net framework 4.
    $msbuild = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe"
    If (!(Test-Path $msbuild)) {
        $msbuild = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe"
    }
    If (!(Test-Path $msbuild)) {
        throw "msbuild.exe not found!"
    }
    return $msbuild
}

function Get-NugetPath {
    $nuget = "C:\COL-Tools\Dev\NuGet\nuget.exe"
    If (!(Test-Path $nuget)) {
        throw "nuget.exe not found!"
    }
    return $nuget
}

function Start-NugetClean {
    $nuget = Get-NuGetPath
    . $nuget locals all -Clear
}

function Start-PublishWebApp {
    Param(
        [string] $configuration = "Debug",
        [string] $verbosity = "quiet",
        [string] $solution = ""
    )

    $msbuild = Get-MsBuildPath

    if ((Test-Path $solution) -eq $false){
        Throw "Solution file '$solution' does not exist!"
    }

    $consoleLoggerParameters = "/clp:NoSummary /clp:Verbosity=$verbosity"
    if ($performance) {
        $consoleLoggerParameters = " /clp:PerformanceSummary"
    }

    $nologo = "/nologo"
    $target = "/t:Build"
    $verbosity = "/v:quiet"
    $isPackaging = "/p:IsPackaging=$package"
    $maxCpuCount = "/maxcpucount"
    $deployOnBuild = "/p:DeployOnBuild=true"
    $publishProfile = "/p:PublishProfile=Meet.pubxml"
    $vsVersion = "/p:VisualStudioVersion=15.0"

    $configuration -split "," | ForEach {
        $configuration = "/p:Configuration=$_"

        $name = (Get-Item $solution).Name

        try {
            Write-SubStep -nonewline "Publishing solution" -Highlight $name -Normal "$configuration, $target ..."
            & $msbuild $solution $nologo $target $verbosity $consoleLoggerParameters $configuration $isPackaging $maxCpuCount $deployOnBuild $publishProfile $vsVersion 2>&1

        } catch {
            Write-Debug "& $msbuild $solution $nologo $target $verbosity $consoleLoggerParameters $configuration $isPackaging $maxCpuCount $deployOnBuild $publishProfile $vsVersion 2>&1"
            Write-Error $_
            throw "Error while building $name!"
        }
    }

    Write-Success "OK!"
}

function CleanSolutions {
    param (
        $external = $null
    )

    $r = $repositories
    if ($external -ne $null) {
        $r = $r |? { $_.external -eq $external }
    }

    Write-Host "`nRemoving build directories ..."
    if ($out_dir -ne $null -and (Test-Path $out_dir) -eq $false){
        Remove-Directory $out_dir
    }

    dir -Recurse | Where {$_.psIsContainer -eq $true -and $_.Name -eq "obj" } | ForEach { Remove-Directory $_.FullName }
    dir -Recurse | Where {$_.psIsContainer -eq $true -and $_.Name -eq "bin" } | ForEach { Remove-Directory $_.FullName }
    dir -Recurse | Where {$_.psIsContainer -eq $true -and $_.Name -eq "pkg" } | ForEach { Remove-Directory $_.FullName }
    dir -Recurse | Where {$_.psIsContainer -eq $true -and $_.Name -eq "pkgobj" } | ForEach { Remove-Directory $_.FullName }
    dir -Recurse | Where {$_.psIsContainer -eq $true -and $_.Name -eq "packages" } | ForEach { Remove-Directory $_.FullName }

    Write-Host "`nCleaning ..."
    $r | ForEach { CleanSolution $_ }
}

function CleanSolution {
    param (
        $config,
        [switch] $package = $false
    )

    $name = $config.name
    Write-Step -nonewline "Cleaning" -Highlight $name -Normal "..."

    Push-Location $config.path
    $build_target = $config.build.target
    switch ( $config.build.tool ) {
        "msbuild" {
            $solutionFile = (Get-ChildItem -path $path -include $build_target -recurse) | Select-Object -First 1
            if (-not $solutionFile) {
                throw "Solution file $build_target not found in $path"
            }
            Start-MsBuild -solution $solutionFile -target "clean" -configuration "Debug,Release"
            break
        }
        "publishwebapp" {
            $solutionFile = (Get-ChildItem -path $path -include $build_target -recurse) | Select-Object -First 1
            if (-not $solutionFile) {
                throw "Solution file $build_target not found in $path"
            }
            Start-MsBuild -solution $solutionFile -target "clean" -configuration "Debug,Release"
            break
        }
        "psake" {
            psake $build_target "clean"
            break
        }
    }

    Write-Host
    Pop-Location
}

function BuildInit {
    EnsurePaths

    if (($repositories | where { -not $_.exists } | measure).Count -gt 0) {
        UpdateRepositories -fetch:$true
    }
}

function BuildSolutions {
    param (
        $configuration = "Debug",
        [switch] $package = $false,
        $target = "rebuild",
        $external = $null
    )

    $r = $repositories
    if ($external -ne $null) {
        $r = $r |? { $_.external -eq $external }
    }

    Write-Host "`nPre-Build..."
    $r | ForEach {
        PreBuildSolution $_ -package:$package -target $target -configuration $configuration
    }

    Write-Host "`nBuilding ..."
    $r | ForEach {
        BuildSolution $_ -package:$package -target $target -configuration $configuration
    }

    Write-Host "`nPost-Build ..."
    $r | ForEach {
        PostBuildSolution $_ -package:$package -target $target -configuration $configuration
    }
}


function BuildSolution {
    param (
        $config,
        $configuration = "Debug",
        [switch] $package = $false,
        $target = "rebuild"
    )

    $name = $config.name
    Write-Step -nonewline "Building" -Highlight $name -Normal "..."

    try {
        $path = $config.path
        $exists = $config.exists
        $build = $config.build
        $external = $config.external
        $packages = $config.packages

        Push-Location $path
        $build_target = $build.target
        $build_task = $build.task

        if ($package) {
            $build_task = "package"
        }
        switch ( $config.build.tool ) {
            "batch" {
                $cmd = "$path\$build_target".Replace("{configuration}", $configuration)
                $path = (Split-Path -Parent $cmd)
                Push-Location $path
                . $cmd
                Pop-Location
                break
            }
            "msbuild" {
                $solutionFile = (Get-ChildItem -path $path -include $build_target -recurse) | Select-Object -First 1
                if (-not $solutionFile) {
                    throw "Solution file $build_target not found in $path"
                }
                Start-MsBuild -solution $solutionFile -package:$package -configuration:$configuration -target:$target
                break
            }
            "publishwebapp" {
                $solutionFile = (Get-ChildItem -path $path -include $build_target -recurse) | Select-Object -First 1
                if (-not $solutionFile) {
                    throw "Solution file $build_target not found in $path"
                }
                Start-PublishWebApp -solution $solutionFile -configuration:$configuration -target:$target
                break
            }
            "psake" {
                psake $target $build_task -properties @{ "configuration" = $configuration }
                break
            }
        }

    } catch {
        Write-Error $_
        throw
    }

    Pop-Location
}

function PreBuildSolution {
    param (
        $config,
        $configuration = "Debug",
        $target = "rebuild",

        [switch] $package = $false,

        # this build parameter drives the inclusion of the nuget.targets file
        # if included, the nuget packages are checked and updated against their repositories
        [switch] $restore_packages = $true
    )

    $name = $config.name
    Write-Step -nonewline "Pre-build" -Highlight $name -Normal "..."
    $messages = New-Object System.Collections.ArrayList

    try {

        $path = $config.path
        $exists = $config.exists
        $build = $config.build
        $external = $config.external
        $packages = $config.packages

        Push-Location $path

        if ($configuration -eq "Release" -or $package) {
            if(Test-GitStatus) {
                $gitStatus = Get-GitStatus

                $git_rev = $config["release"].split(":")[0]
                $git_revid = $config["release"].split(":")[1]

                if ($git_rev -eq "branch" -and $gitStatus.Branch -ne $git_revid) {
                    $messages.Add("Repository branch is $($gitStatus.Branch), but should be $git_revid") | Out-Null
                }
                if ($git_rev -eq "tag" -and $gitStatus.Tag -ne $git_revid) {
                    $messages.Add("Repository tag is $($gitStatus.Tag), but should be $git_revid") | Out-Null
                }
                if ($gitStatus.TagAhead -ne 0) {
                    $messages.Add("Repository is $($gitStatus.TagAhead) commits ahead of last tag $($gitStatus.Tag)") | Out-Null
                }
                if ($gitStatus.HasUntracked -or $gitStatus.HasWorking) {
                    $messages.Add("Repository has uncommitted changes") | Out-Null
                }
            }
        }

        try {
            $message = & C:\COL-Tools\Dev\AssemblyInfoUpdater\AssemblyInfoUpdater.exe -skipGitWarnings
        } catch {
            $message = "$_"
            $LASTEXITCODE = -1
        }
        if ($LASTEXITCODE -ne 0) {
            $messages.Add("AssemblyInfoUpdater reported errors: $message") | Out-Null
        }

        if ($restore_packages) {
            Write-SubStep "Restoring .nuget packages ..." -nonewline

            $nuget = Get-NugetPath
            try {
                $output = & $nuget restore 2>&1
            } catch {
                Write-Debug "& $nuget restore 2>&1"
                Write-Error $_
                throw "Error while restoring .nuget packages!"
            }
        }

    } catch {
        $messages.Add($_) | Out-Null
    }

    if ($messages.Count) {
        Write-Host
        $messages | ForEach {
            Write-SubStep -Error "$_"
        }
    } else {
        Write-Success "OK!"
    }

    Pop-Location
}


function PostBuildSolution {
    param (
        $config,
        $configuration = "Debug",
        [switch] $package = $false,
        $target = "rebuild"
    )

    $name = $config.name
    Write-Step -nonewline "Post-build" -Highlight $name -Normal "..."
    $messages = New-Object System.Collections.ArrayList

    try {
        # get wsp solution package path from repository config.
        # if a solution is configured as a build target, use the solution folder as a search path
        $packagePath = $config.path
        $solutionFile = (Get-ChildItem -path $packagePath -include $config.build.target -recurse) | Select-Object -First 1
        if ($solutionFile) {
            $packagePath = split-path -parent $solutionFile
        }

        Push-Location $path

        if ($configuration -eq "Release" -and (-not $config.build.skipDisposeCheck)) {
            $disposeCheck = DisposeCheck -path $packagePath
            if (-not $disposeCheck) {
                $messages.Add("SPDisposeCheck failed!") | Out-Null
            }
        }

        $packages = $config.packages
        $package_expected = $package -and $packages
        if ($package_expected) {
            $packages | ForEach {
                Write-Debug "Looking for $_ in $packagePath ..."
                $built_packages = @( Get-ChildItem -path $packagePath -include $_ -recurse )
                if (-not $built_packages -or $built_packages.Count -lt 1) {
                    $messages.Add("package $_ not found in $packagePath!") | Out-Null
                }

                $built_packages | ForEach {
                    $source = $_.FullName
                    $target = "$wsp_dir\"

                    Write-Debug "Moving $($_.Name) to $target ..."
                    Move-Item $source $target -Force
                }
            }
        }
    } catch {
        $messages.Add($_) | Out-Null
    }

    if ($messages.Count) {
        Write-Host
        $messages | ForEach {
            Write-SubStep -Warning "$_"
        }
    }

    Write-Host
    Pop-Location
}

function DisposeCheck {
    param (
        [string] $path = (Get-Location)
    )

    [System.Collections.ArrayList] $problems = @()

    Write-SubStep "DisposeCheck: Processing $path ..." -nonewline
    $command = "C:\COL-Tools\SharePoint\SPDisposeCheck\SPDisposeCheck.exe $path -xml"
    $result = invoke-expression $command

    [xml] $xml = $result
    $nodes = @( $xml.SelectNodes("/ArrayOfProblem/Problem") )

    foreach ($node in $nodes) {

        # <?xml version="1.0" encoding="ibm850"?>
        # <ArrayOfProblem xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        #   <Problem>
        #       <ID>SPDisposeCheckID_650</ID>
        #       <Module>Assembly.dll</Module>
        #       <Method>Assembly.WebParts.SomeWebpart.OnInit(System.EventArgs)</Method>
        #       <Assignment>web.{System.IDisposable}Dispose()</Assignment>
        #       <Line>0</Line>
        #       <Notes>Dispose should not be called on this object.
        #             initial Assignment: web := Microsoft.SharePoint.SPContext.get_Current().{Microsoft.SharePoint.SPContext}get_Web()</Notes>
        #       <Source></Source>
        # </Problem>

        # prepare a PSObject with all properties. they are not mandatory on the xml
        $o = "" | select ID,Module,Source,Method,Assignment,Line,Notes
        $o.ID = $node.ID; $o.Module = $node.Module; $o.Source = $node.Source; $o.Method = $node.Method;
        $o.Assignment = $node.Assignment; $o.Line = $node.Line; $o.Notes = $node.Notes

        [void] $problems.Add($o)
    }

    $count = $problems.Count
    if ($count -eq 0) {
        Write-Success "OK!"
        return $true
    }

    $warnings = ""
    $errors = ""

    $groups = $problems | Group Module
    $groups | foreach {
        $group = $_.Name
        $count = $_.Count
        $items = $_.Group

        $message = ("Assembly {0} has {1} problems:`n" -f $group, $count)
        $items | ForEach {
            $i = $_
            $message += "  $($i.ID): $($i.Assignment)`n"
            $message += "    Source: $($i.Source) #$($i.Line)`n"
            $message += "    Method: $($i.Method)`n`n"
        }

        if ($disposecheck_as_warnings -contains $group) {
            $warnings += $message
        } else {
            $errors += $message
        }
    }

    if ( $warnings ) {
        # finish line started above, then list problems
        Write-Warning "Has Warnings!"
        Write-Warning "Found $count problems!`n" + $warnings
    }

    if ( $errors ) {
        # finish line started above, then list errors
        Write-Error "Has Errors!"
        Write-Error "Found $count problems!`n" + $errors
        return $false
    }

    return $true
}

function Get-ItemWaitForLock($path) {
    $numTries = 0
    $file = $null
    while (++$numTries -lt 10){
        try {
            $file = Get-Item $path | Out-Null
        } catch {
            Write-Host "$path($numTries): failed to read $_" -f Yellow
            sleep -m 200
        }
    }
    Write-Host "Get-ItemWaitForLock -> $file"
    return $file
}

function ExecNunit {
    param(
        $project,
        $directory,
        $includeTags
    )

    $cmd = Get-ExternalTool "nunit-console.exe" $tools_dir

    try {
        $txt = "/out=$directory\$project.txt"
        $xml = "/xml=$directory\$project.xml"

        $filename = "$project.nunit"
        $projectfile = @(Get-ChildItem -path $working_dir -include $filename -recurse) | Select -First 1
        if ($projectfile -eq $null) {
            Throw "nunit project file $filename does not exist in $working_dir!"
        }

        if ($includeTags) {
            $includeTags = "/include:$includeTags"
        }

        & $cmd $projectfile /labels $txt $xml $includeTags

        if ($LASTEXITCODE -ne 0) {
            throw "Nunit runner returned error. "
        }

    } catch {
        Write-Error "Error while executing nunit`n  Command was: $cmd $projectfile /labels $txt $xml`n  $_"
    }
}

function ExecSpecFlow {
    param(
        $project,
        $directory
    )

    $cmd = Get-ExternalTool "specflow.exe" $tools_dir
    $configfile = "$cmd.config"

    if ((Test-Path $configfile) -eq $false){
        @"
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
    <startup>
        <supportedRuntime version="v4.0.30319" />
    </startup>
</configuration>
"@ | Out-File -Encoding "utf8" $configfile | Out-Null
    }

    try {
        $xml = "/xmlTestResult:$directory\$project.xml"
        $html = "/out:$directory\$project.html"

        $filename = "$project.csproj"

        $projectfile = @(get-childitem -path $working_dir -include $filename -recurse) | Select -First 1
        if ($projectfile -eq $null) {
            Throw "specflow project file $filename does not exist in $working_dir!"
        }

        & $cmd nunitexecutionreport $projectfile $xml $html

        if ($LASTEXITCODE -ne 0) {
            throw "Specflow returned error."
        }

    } catch {
        Write-Error "Error while executing specflow`n  Command was: $cmd nunitexecutionreport $projectfile $xml $html`n  $_"
    }
}

function New-CommonAssembly {
    param (
        $path
    )

    Set-Location $path
    Write-Step "New-CommonAssembly : path:=$path"
    $path = "$path\CommonAssemblyInfo.cs"

    $gitUrl = git config --get remote.origin.url
    if ($gitUrl -contains "https"){
        $arrUrl = $gitUrl -split "/scm/"
        $gitPath = $arrUrl[1] -split ".git"
    } else {
        $arrUrl = $gitUrl -split "(:\d\d\d\d\/)"
        $gitPath = $arrUrl[2] -split ".git"
    }

    $year = ("Copyright (c) {0}" -f (Date).Year);
    Write-SubStep "AssemblyCopyright:=$year"

    $company = "Garaio AG";
    Write-SubStep "AssemblyCompany:=$company"

    $product = $gitPath -replace "/","-"
    Write-SubStep "AssemblyProduct:=$product"

    $version = git describe --tags --long
    $version = $version -replace "-","."
    $versions = $version.split(".");
    $version = $versions[0] + "." + $versions[1] + "." + $versions[2] + "." + $versions[3];
    Write-SubStep "AssemblyFileVersion:=$version"

    $content = "using System.Reflection;`n";
    $content += ("[assembly: AssemblyCompany(`"Garaio AG`")]`n" -f $company)
    $content += ("[assembly: AssemblyProduct(`"{0}`")]`n" -f $product)
    $content += ("[assembly: AssemblyCopyright(`"{0}`")]`n" -f $copyright)
    $content += ("[assembly: AssemblyFileVersion(`"{0}`")]`n" -f $version)

    Write-SubStep "Writing file to $path"
    Set-Content -path $path -Value $content -Encoding UTF8 -Force
}

function Add-CommonAssembly {
        param(
            $currentPath
        )

    if (!$currentPath) {
        $currentPath = $working_dir
    }

    set-location -path $currentPath
    $solutions = get-childitem . "*garaio*.sln" -r | ? {!$_.PSIsContainer}

    foreach ($path in $solutions) {
        # get string as a string from the PSObject
        $path = Convert-Path $path.PSParentPath
        New-CommonAssembly -path $path
        Write-Host
    }

    set-location $currentPath
}


function Stop-DevServer {
    Get-Process iisexpresstray -ea SilentlyContinue | Stop-Process
    Get-Process iisexpress -ea SilentlyContinue | Stop-Process
}

function Start-DevServer($config) {
    Start-Process powershell.exe "& '${env:ProgramFiles(x86)}\IIS Express\iisexpress.exe' /config:$config"
}

Export-ModuleMember -Function *
