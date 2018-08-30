#-------------------------------------------------------------------
# Author: thomas.burkhart@garaio.com
#-------------------------------------------------------------------

function Copy-ReleaseFileSets {
    $basePath = "C:\projects\_release\{ProjectName}-{LatestTag}"
    $basePath = $basePath.replace("{ProjectName}", $projectname)
    $basePath = $basePath.replace("{LatestTag}", (get-gitstatus).tag)
    Write-Host "Path: $basePath"

    $release_file_sets | % { Copy-ReleaseFileSet $_ $basePath}

    Start-ZipReleaseFiles $basePath
}

function Copy-ReleaseFileSet($fileSet, $basePath){
    $destination = $fileSet.destination
    Write-Step "Destination: $destination"

    $destination = Join-Path $basePath $fileSet.destination
    $source = $fileSet.source

    #get all files
    if ($fileSet.recursive){
        $items = Get-ChildItem $fileSet.source -filter $fileSet.filter -rec
    } else {
        $items = Get-ChildItem $fileSet.source -filter $fileSet.filter
    }

    #filter directories
    $items = $items | ? { ! $_.PSIsContainer }

    #filter ecludes
    $_.exlude | ForEach {
        $e = $_
        $items = $items | ? { $_.FullName -notlike $e }
    }

    if ((Test-Path $destination) -and $_.clear) {
        Write-SubStep "Deleting '$destination' and all its contents"
        Remove-Item $destination -rec | Out-Null
    }

    if (-not (Test-Path $destination)) {
        Write-SubStep "Creating folder '$destination'"
        New-Item $destination -type directory | Out-Null
    }

    if($items -is [System.array]) {
        $count = $items.Count
        Write-SubStep "Copying $count files to folder '$destination'"
    } else {
        Write-SubStep "Copying 1 file to folder '$destination'"
    }

    $items | ForEach {
        #create directory if neccessary (Copy-Item $_.FullName $dest -Recurse -Force did not work)
        $dir = $_.DirectoryName -replace [regex]::escape($source), $destination
        if (-not (Test-Path $dir)) {
            New-Item $dir -type directory | Out-Null
        }

        #copy the file
        $dest = $_.FullName -replace [regex]::escape($source), $destination
        Copy-Item $_.FullName $dest
    }
}

function Start-ZipReleaseFiles($source) {
    Add-Type -assembly "system.io.compression.filesystem"

    $zipName =  split-path -leaf $source
    $dest = Split-Path $source -Parent

    $zipName = "$zipName.zip"
    $zipPath = Join-Path "C:\temp" $zipName
    $destZipPath = Join-Path $dest $zipName

    If(Test-path $zipPath) {Remove-item $zipPath}
    If(Test-path $destZipPath) {Remove-item $destZipPath}

    Write-Step "Creating zip $zipName from $source ... " -nonewline
    [io.compression.zipfile]::CreateFromDirectory($source, $zipPath)
    Write-Success "OK!"

    Write-Step "Moving to $dest ... " -nonewline
    Move-Item $zipPath $dest
    Write-Success "OK!"
}

Export-ModuleMember -Function *
