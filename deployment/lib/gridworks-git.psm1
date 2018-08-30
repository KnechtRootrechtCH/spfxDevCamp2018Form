# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------
function Test-GitStatus {
    return [bool](Get-Command -Name 'Get-GitStatus' -ErrorAction SilentlyContinue)
}
function TagRepositories {
    param (
        $mode = "minor"
    )

    $repositories |% {
        TagRepository $_ $mode
    }

    WriteRepositoriesStatus
}

function TagRepository {
    param (
        $config,
        $mode = "minor"
    )

    $name = $config.name
    Write-Step "Processing" -Highlight $name -Normal "..."

    $path = $config.path
    Push-Location $path

    if(Test-GitStatus){
        $currentTag = (Get-GitStatus).tag
    }

    if ($mode -eq "overwrite") {
        $proposedTag = "$currentTag"
    }

    if ($mode -eq "minor") {
        $parts = $currentTag.Split(".")
        $minorPos = $parts.length - 1
        $last = [int] $parts[$minorPos]
        $parts[$minorPos] = ++$last
        $proposedTag = $parts -join "."
    }

    if ($mode -eq "major") {
        $parts = $currentTag.Split(".")
        $majorPos = $parts.length - 2
        $last = [int] $parts[$majorPos]
        $parts[$majorPos] = ++$last
        $proposedTag = $parts -join "."
    }

    $proposedTag = Get-InputString "Confirm/Enter tag (current: $currentTag, enter 'n' to skip)" $proposedTag
    $proposedTag = "$proposedTag".Trim()

    $gitForce = "";
    $tagMessage = "Adding tag '$proposedTag' ..."
    $pushMessage = "Pushing tags ..."

    if ($proposedTag -and $proposedTag -ne "n") {
        if ($currentTag -eq $proposedTag) {
            $gitForce = "-f"
            $tagMessage = "Overwriting tag '$proposedTag' ..."
            $pushMessage = "Force pushing tags ..."
        }

        Write-SubStep $tagMessage
        try {
            $command = "git tag $proposedTag $gitForce"
            $output = git tag $proposedTag -m $proposedTag $gitForce 2>&1
        } catch {
            $warning = $_
        }
        Write-GitOutput $output $warning $command

        Write-SubStep $pushMessage
        try {
            $command = "git push --tags $gitForce"
            $output = git push --tags $gitForce 2>&1
        } catch {
            $warning = $_
        }
        Write-GitOutput $output $warning $command
    }

    Write-Host
    Pop-Location
}

function PushRepositories {
    param (
        $mode = "ahead"
    )

    FetchRepositories

    $repositories |% {
        PushRepository $_ $mode
    }

    WriteRepositoriesStatus
}

function PushRepository {
    param (
        $config,
        $mode = "ahead"
    )

    $name = $config.name
    Write-Step "Processing" -Highlight $name -Normal "..."

    if ($mode -match "all") {
        $pushCommits = $true
        $pushTags = $true
    }
    if ($mode -match "tags") {
        $pushTags = $true
    }

    $path = $config.path
    Push-Location $path

    if(Test-GitStatus){
        $gitStatus = Get-GitStatus
        $ahead = $gitStatus.AheadBy
        $isAhead = $gitStatus.AheadBy -gt 0

        if ($isAhead) {
            Write-SubStep "is ahead by" -Highlight $ahead -Normal " ..."
            $pushCommits = $true
        }
    }

    # make sure we are not pushing anything badly. list remote branches and tags.
    $branch = $gitstatus.branch
    if (-not $pushCommits) {
        Write-SubStep "Checking for unpushed branches ..."
        try {
             $output = git push -n --porcelain 2>&1
        } catch {}

        $unpushedBranches = @( $output | where { "$_".Contains("[new branch]") })
        if ($unpushedBranches) {
            $unpushedBranches | ForEach {
                $x = $_.Trim(' ','*').Replace("refs/heads/").split(":")[0]
                if ($x -eq $branch) {
                    $pushUpstream = $true
                }
                Write-SubStep("  Found $x")
            }
            $pushCommits = $true
        }
    }

    $tag = $gitstatus.tag
    if (-not $pushTags) {
        Write-SubStep "Checking for unpushed tags ..."
        try {
             $output = git push --tags -n --porcelain 2>&1
        } catch {}

        $unpushedTags = @( $output | where { "$_".Contains("[new tag]") })
        if ($unpushedTags) {
            $unpushedTags | ForEach {
                $x = $_.Trim(' ', '*').Replace("refs/tags/", "").split(":")[0]
                Write-SubStep ("Found {0} ..." -f $_.Trim(' ','*'))
            }
            $pushTags = $true
        }
    }

    if ($pushCommits) {
        Write-SubStep "Pushing commits ..."

        try {
            if ($pushUpstream) {
                $command = "git push --set-upstream origin $branch --follow-tags"
                $output = git push --set-upstream origin $branch --follow-tags 2>&1
            } else {
                $command = "git push --follow-tags"
                $output = git push --follow-tags 2>&1
            }
        } catch {
            $warning = "$_"
        }
        Write-GitOutput $output $warning $command
    }

    if ($pushTags) {
        Write-SubStep "Pushing tags ..."

        try {
            $warning = ""
            $command = "git push --tags"
            $output = & git push --tags 2>&1
        } catch {
            $warning = "$_"
        }
        Write-GitOutput $output $warning $command
    }

    Pop-Location
}

function FetchRepositories {
    param(
        $fetch = $true,
        $prune = $false
    )

    $throttle = 5
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool( 1, $throttle )
    $pool.Open()

    $scriptBlock = {
        param(
            $config,
            $fetch,
            $prune
        )

        try {
            $name = $config.name
            $url = $config.url
            $external = $config.external
            $path = $config.path

            if ($external) {
                if ((Test-Path $path) -eq $false) {
                    Write-Output "Path $path does not exist yet, cloning ..."
                    Push-Location (Split-Path -Parent $path)
                    try {
                        $output = git clone --recursive $url $path 2>&1
                    } catch {
                        $output = "$_"
                    }
                    Write-Output "$output".trim()

                    Pop-Location
                    $fetch = $false
                }
            }

            if ($fetch) {
                $output = "";
                Push-Location $path

                try {
                    $output = & git remote -v 2>&1
                } catch {
                    $output = "$output : $_"
                }

                $updateRemote = -not ("$output".Trim().ToLower().Contains($url.ToLower()))
                if ($updateRemote) {
                    Write-Output "Updating remote url to $url ..."
                    try {
                        $output = & git remote set-url origin $url
                    } catch {
                        $output = "$output : $_"
                    }
                    if ($output) {
                        Write-Output "$output".trim()
                    }
                }

                try {
                    Write-Output "Fetching commits ...`n"
                    $output = & git fetch 2>&1
                } catch {
                    $output = "$output : $_"
                }

                Write-Output "$output".trim()

                $output = "";
                try {
                    Write-Output "Fetching tags ...`n"
                    $output = &  git fetch --prune origin "+refs/tags/*:refs/tags/*" 2>&1
                    $output += & git fetch --tags 2>&1
                } catch {
                    $output = "$output : $_"
                }
                Write-Output "$output".trim()

                Pop-Location
            }

            if ($prune) {
                Push-Location $path

                try {
                    Write-Output "Pruning ..."
                    $output = & git fetch --prune 2>&1
                } catch {
                    $output = "$output : $_"
                }

                Write-Output "$output".trim()

                try {
                    Write-Output "Setting default branch ..."
                    $output = & git remote set-head origin -a 2>&1
                } catch {
                    $output = "$output : $_"
                }

                Write-Output "$output".trim()

                Pop-Location
            }

        } catch {
            $x = ($_ | Out-String)
            Write-Output "Error: $x"
        }
    }

    $activity = "Queueing repository updates ..."
    Write-Step $activity

    $runspaces = New-Object System.Collections.ArrayList
    $repositories | ForEach {
        $name = $_.Name

        $ps = [powershell ]::Create().AddScript($scriptBlock)
        $ps.AddArgument($_) | Out-Null
        $ps.AddArgument($fetch) | Out-Null
        $ps.AddArgument($prune) | Out-Null

        $ps.RunspacePool = $pool
        $runspace = New-Object PSObject -Property @{ Name = $name; Powershell = $ps; Runspace = $ps.BeginInvoke() }

        Write-SubStep "Queuing" -Highlight $name -Normal "..."
        $runspaces.Add($runspace) | Out-Null
    }

    Write-Host
    Write-Step "Waiting for repository updates ..."
    $activity = "Fetching repositories"
    $totalrunspaces = $runspaces.Count
    $elapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 1
        $status = ("{0}/{1} remaining... " -f $runspaces.Count, $totalrunspaces)

        $completed = $runspaces | Where { $_.Runspace.IsCompleted }

        if ($completed.Count) {
            $status += (", Completed {0} runspaces: " -f $completed.Count)
            $completed | ForEach {
                Write-SubStep "Completed" -Highlight $_.Name -Normal "..."
                $result = $_.Powershell.EndInvoke($_.Runspace)
                $result = "$result".trim()

                if ($result) {
                    $result = $result.split("`n");
                    $result |% { $_ = "$_".Trim(); Write-SubSubStep "$_" }
                }
                $_.Powershell.Dispose()
                $runspaces.Remove($_)
            }
        }

        $status += [string]::Format("Elapsed: {0:d2}:{1:d2}:{2:d2}", $elapsedTime.Elapsed.hours, $elapsedTime.Elapsed.minutes, $elapsedTime.Elapsed.seconds)
        $complete = 100 - (($runspaces.Count / [float]$totalrunspaces)*100)
        Write-Progress -activity $activity -status $status -percentcomplete $complete

    } while ($runspaces.Runspace.IsCompleted -contains $false)

    $pool.Close()

    Write-Progress -activity $activity -Completed
    Write-Host
}

function UpdateRepositories {
    param (
        $fetch = $false,
        $mode =  $null
    )

    if ($fetch) {
        FetchRepositories
    }

    # read configuration before updating main repositories
    # UNCOMMENT below if you wish to use the configuration comparer
    #  $configurationBefore = [string]::concat((gc "$deployment_dir\env\init.ps1"), (gc "$working_dir\deployment\env\Ga-Dev-kni\init.ps1"))
    $repositories |? { -not $_.external } | ForEach {
        UpdateRepository -config $_ -mode $mode
    }

    # read configuration after updating main repositories
    # if configuration has changed, update all, else only external.
    # UNCOMMENT below if you wish to use the configuration comparer
    #$configurationAfter  = [string]::concat((gc "$deployment_dir\env\init.ps1"), (gc "$working_dir\deployment\env\Ga-Dev-kni\init.ps1"))
    #if ($configurationAfter -ne $configurationBefore) {
    #    . "$working_dir\env\init.ps1"
    #    . "$working_dir\env\Ga-Dev-Ske\init.ps1"
    #    $updates = $repositories
    #} else {
    #    $updates = $repositories |? { $_.external }
    #}

    $updates = $repositories |? { $_.external }

    $updates | ForEach {
        UpdateRepository -config $_ -mode $mode
    }

    WriteRepositoriesStatus
}

function UpdateRepository {
    param (
        $config,
        $mode = $null
    )

    $name = $config.name
    Write-Step "Updating" -Highlight $name -Normal "..."

    # get target branch/tag and name from config.
    # define it as 'branch:name' or 'tag:name'
    if ($mode) {
        $checkout = $config[$mode]
        if (-not $checkout) {
            Write-Error "Repository $name does not have an checkout configuration for mode: $mode"
            return
        }
        $checkoutType = $checkout.split(":")[0]
        $tag = $branch = $checkout.split(":")[1]
    }

    $path = $config.path
    $external = $config.external
    $build = $config.build
    $tool = $build.tool
    $target = $build.target
    $rebase = $true

    Push-Location $path


    # -------------------------------------------------------------------------
    # checking out current branch / tag
    # -------------------------------------------------------------------------
    if(Test-GitStatus){
        $gitStatus = Get-GitStatus

        $currentBranch = (git rev-parse --abbrev-ref HEAD 2>&1).trim()
        if ($currentBranch -eq "HEAD") {
            $describe = git describe --tag --long
            $currentBranch = $describe.split("-")[0]
        }

        Write-SubStep "Currently on" -Highlight $currentBranch -Normal "..." -nonewline
        $tags = git tag 2>&1
        $tagExists = (( $tags | where {$_ -match "$tag"}) | measure ).count -gt 0

        if ($checkoutType -eq "tag" -and $tagExists) {

            # first check repository status, if a working copy changes exist it is not safe to checkout a tag.
            if ($gitStatus.HasUntracked -or $gitStatus.HasWorking) {
                Write-SubStep -Warning "Working copy is dirty, cannot checkout tag $tag!"

            } else {
                Write-SubStep "Checking out tag" -Highlight $tag -Normal "..." -nonewline
                try {
                    $warning = ""
                    $command = "git checkout $tag"
                    $output = & git checkout $tag 2>&1
                } catch {
                    $warning = "$_"
                }
                Write-GitOutput $output $warning $command
            }

            $rebase = $false
        }
    }

    if ($checkoutType -eq "branch") {

        # first check repository status, if a working copy changes exist it is not safe to checkout another branch.
        if ($currentBranch -ne $branch) {
            if(Test-GitStatus){
                if ($gitStatus.HasUntracked -or $gitStatus.HasWorking) {
                    Write-SubStep -Warning "Working copy is dirty, cannot checkout branch $branch!"
                    $currentBranch = $branch
                    $rebase = $false
                }
            }
        }

        if ($currentBranch -ne $branch) {
            # example output of local branches:
            # * (detached from 1.3.2)
            #   master
            #   some other branch
            $localBranches += git branch 2>&1
            $localBranchExists = (( $localBranches | where {$_ -match "$branch"}) | measure ).count -gt 0

            # example output of remote branches:
            # origin/HEAD -> origin/master
            # origin/master
            $remoteBranches = git branch -r 2>&1
            $remoteBranchExists = (( $remoteBranches | where {$_ -match "origin/$branch"}) | measure ).count -gt 0

            if ($localBranchExists) {
                Write-SubStep "Checking out local branch" -Highlight $branch -Normal "..." -nonewline
                try {
                    $warning = ""
                    $command = "git checkout $branch"
                    $output = & git checkout $branch 2>&1
                } catch {
                    $warning = "$_"
                }
                Write-GitOutput $output $warning $command
            }

            $currentBranch = (git rev-parse --abbrev-ref HEAD 2>&1).trim()
            if ($currentBranch -eq "HEAD") {
                $describe = git describe --tag --long
                $currentBranch = $describe.split("-")[0]
            }

            if (-not $localBranchExists -and $currentBranch -ne $branch) {

                if ($remoteBranchExists) {
                    Write-SubStep "Checking out remote branch" -Highlight $branch -Normal "..."
                    try {
                        $warning = ""
                        $command = "git checkout --track origin/$branch"
                        $output = & git checkout --track origin/$branch 2>&1
                    } catch {
                        $warning = "$_"
                    }
                    Write-GitOutput $output $warning $command

                } else {
                    Write-SubStep -Warning "The branch $branch does not exist in the remote branches!"

                    if (Get-Confirmation "Create branch '$branch' at the current commit?") {
                        try {
                            $warning = ""
                            $command = "git checkout -b $branch"
                            $output = git checkout -b $branch 2>&1
                        } catch {
                            $warning = "$_"
                        }
                        Write-GitOutput $output $warning $command

                        try {
                            $warning = ""
                            $command = "git push --set-upstream origin $branch"
                            $output = & git push --set-upstream origin $branch 2>&1
                        } catch {
                            $warning = "$_"
                        }
                        Write-GitOutput $output $warning $command
                    }
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # git rebase
    # -------------------------------------------------------------------------
    if(Test-GitStatus){
        if ($rebase) {
            $gitStatus = Get-GitStatus
            $behind = $gitStatus.BehindBy

            if ($behind -eq 0) {
                Write-SubStep "No changes to rebase ..."
            } else {

                $stash = $gitStatus.HasWorking -or $gitStatus.HasUntracked;
                if ($stash) {
                    Write-SubStep "`nStashing changes ..."
                    try {
                        $warning = ""
                        $command = "git stash -u"
                        $output = & git stash -u 2>&1
                    } catch {
                        $warning = "$_"
                    }
                    Write-GitOutput $output $warning $command
                }

                Write-SubStep "Rebasing remote changes ..."
                try {
                    $warning = ""
                    $command = "git rebase"
                    $output = & git rebase 2>&1
                } catch {
                    $warning = "$_"
                }
                Write-GitOutput $output $warning $command

                if ($stash) {
                    Write-SubStep "`nGetting stashed changes ..."
                    try {
                        $warning = ""
                        $command = "git stash pop"
                        $output = & git stash pop 2>&1
                    } catch {
                        $warning = "$_"
                    }
                    Write-GitOutput $output $warning $command
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # git submodules update
    # -------------------------------------------------------------------------

    $file = ".gitmodules"
    $files = @( get-childitem -include $file -recurse )
    $exists = $files.Count -gt 0
    if ( $exists ) {
        Write-SubStep "Updating submodules ..."
        try {
            $warning = ""
            $command = "git submodule update"
            $output = & git submodule update 2>&1
        } catch {
            $warning = "$_"
        }
        Write-GitOutput $output $warning $command
    }

    # -------------------------------------------------------------------------
    # git gc
    # -------------------------------------------------------------------------

    if ($fetch) {
        Write-SubStep "Optimizing git repository ..."
        try {
            $warning = ""
            $command = "git gc --auto"
            $output = & git gc --auto 2>&1
        } catch {
            $warning = "$_"
        }
        Write-GitOutput $output $warning $command
    }

    # -------------------------------------------------------------------------
    # CommonAssemblyInfo.cs
    # -------------------------------------------------------------------------

    $file = "CommonAssemblyInfo.cs"
    $files = get-childitem -include $file -recurse
    $exists = ($files | measure).Count -gt 0
    if (-not $exists) {
        Write-SubStep "Creating $file ..."
        New-Item $file -type file | Out-Null
    }
    switch ($tool) {
        "psake" {
            psake $target "git:update"
        }
    }

    Pop-Location
    Write-Host ""
}

function Write-GitOutput($output, $warning, $command) {
    $warning = "$output".trim()
    $output = "$warning".trim()

    if ($output -or $warning) {
        $color = "-Normal"
        if ($warning) {
            $output = "$warning`n$output"
            $color = "-Warning"
        }
        $output -split "     " | ForEach { $_.trim() } | Where { $_ } | ForEach {
            Write-Info $color ("     {0}" -f $_)
        }
        if ($warning) {
            Write-Info -Quiet   ("     Location:    {0}" -f (Get-Location))
            Write-Info -Quiet   ("     Git Command: {0}" -f $command)
        }
    }
}

function WriteRepositoriesStatus {
    Write-Color -Yellow "main: "
    $repositories | Where { $_.external -ne $true } | Sort { $_.name } | ForEach {
        WriteRepositoryStatus $_
    }

    Write-Color -Yellow "externals: "
    $repositories | Where { $_.external -eq $true } | Sort { $_.name } | ForEach {
        WriteRepositoryStatus $_
    }

    write-Host ""
}

function WriteRepositoryStatus {
    param(
        $config
    )

    $name = $config.name
    $path = $config.path
    $git_rev = $config["develop"].split(":")[0]
    $git_revid = $config["develop"].split(":")[1]

    $build = $config.build
    $tool = $build.tool
    $target = $build.target

    try {
        Push-Location $path

        switch ( $tool ) {

            "psake" {
                psake $target "git:status"
                break
            }
            default {
                Write-Color "  " -nonewline -Quiet ($name).PadLeft(4).PadRight(30)
                if ((Test-Path $path) -eq $false) {
                    throw "repository $name does not exist."
                }

                # temporary enable file status and tags output of posh-git.
                $status = $GitPromptSettings.EnableFileStatus
                $tags = $GitPromptSettings.EnableTags
                $GitPromptSettings.EnableFileStatus = $true
                $GitPromptSettings.EnableTags = $true

                if(Test-GitStatus){
                    $gitStatus = Get-GitStatus
                    Write-GitStatus $gitStatus

                    # restore posh-git settings
                    $GitPromptSettings.EnableFileStatus = $status
                    $GitPromptSettings.EnableTags = $tags

                    if ($git_rev -eq "branch" -and $gitStatus.Branch -ne $git_revid) {
                        Write-Host " [" -f DarkGray -nonewline
                        Write-Host "Branch mismatch: " -f DarkRed -nonewline
                        Write-Host "$git_revid" -f Red -nonewline
                        Write-Host "]" -f DarkGray -nonewline
                    }
                    if ($git_rev -eq "tag" -and $gitStatus.Tag -ne $git_revid) {
                        Write-Host " [" -f DarkGray -nonewline
                        Write-Host "Tag mismatch: " -f DarkRed -nonewline
                        Write-Host "$git_revid" -f Red -nonewline
                        Write-Host "]" -f DarkGray -nonewline
                    }
                }

                Write-Host ""
            }
        }

    } catch {
        Write-Error $_
    } finally {
        Pop-Location
    }
}

Export-ModuleMember -Function *
