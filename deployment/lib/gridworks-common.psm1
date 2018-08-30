function Get-InputNumber( $message = "Please enter a number", $default = 0 ) {
    Write-Host ""
    Write-Color -White $message -Gray " (Default is '$default')."
    Write-Host ">" -nonewline -b Magenta -f White

    $input = [Console]::ReadLine().Trim()
    if ("$input".length -ne 0) {
        $number = $input -as [int]
        if ($number -is [int]) {
            return $number
        }
        Write-Warning "Input '$input' could not be converted to int, returning default."
    }
    return $default
}

function Get-InputString( $message = "Please enter a string", $default = "" ) {
    Write-Host ""
    Write-Color -White $message -Gray " (Default is '$default')."
    Write-Host ">" -nonewline -b Magenta -f White
    $input = [Console]::ReadLine().Trim()
    if ("$input".length -ne 0) {
        return $input
    }
    return $default
}

function Get-Confirmation {
    param(
        [string] $message = "",
        [string] $title = "Confirm",
        [int] $default = 0
    )

    $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
    $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
    $result = $host.ui.PromptForChoice( $title, $message, $options, $default )

    switch ($result) {
        0 {
            Write-Debug "User confirmed action '$message'."
            return $true
        }
        1 {
            Write-Debug "User did not confirm action '$message'."
            return $false
        }
    }
}

function Get-RelativeDate {
    #.Synopsis
    #  Calculates a relative text version of a duration
    #.Description
    #  Generates a string approximation of a timespan, like "x minutes" or "x days." Note this method does not add "about" to the front, nor "ago" to the end unless you pass them in.
    #.Parameter Span
    #  A TimeSpan to convert to a string
    #.Parameter Before
    #  A DateTime representing the start of a timespan.
    #.Parameter After
    #  A DateTime representing the end of a timespan.
    #.Parameter Prefix
    #  The prefix string, pass "about" to render: "about 4 minutes"
    #.Parameter Postfix
    #  The postfix string, like "ago" to render: "about 4 minutes ago"
    [CmdletBinding(DefaultParameterSetName="TwoDates")]
    PARAM(
       [Parameter(ParameterSetName="TimeSpan",Mandatory=$true)]
       [TimeSpan]$span,

       [Parameter(ParameterSetName="TwoDates",Mandatory=$true,ValueFromPipeline=$true)]
       [Alias("DateCreated")]
       [DateTime]$before,

       [Parameter(ParameterSetName="TwoDates", Mandatory=$true, Position=0)]
       [DateTime]$after,

       [Parameter(Position=1)]
       [String]$prefix = "",

       [Parameter(Position=2)]
       [String]$postfix = ""
    )
    PROCESS {
       if($PSCmdlet.ParameterSetName -eq "TwoDates") {
          $span = $after - $before
       }

       "$(
       switch($span.TotalSeconds) {
          {$_ -le 1}      { "$prefix a second $postfix "; break }
          {$_ -le 60}     { "$prefix $($span.Seconds) seconds $postfix "; break }
          {$_ -le 120}    { "$prefix a minute $postfix "; break }
          {$_ -le 2700}   { "$prefix $($span.Minutes) minutes $postfix "; break } # 45 minutes or less
          {$_ -le 5400}   { "$prefix an hour $postfix "; break } # 45 minutes to 1.5 hours
          {$_ -le 86400}  { "$prefix $($span.Hours) hours $postfix "; break } # less than a day
          {$_ -le 172800} { "$prefix 1 day $postfix "; break } # less than two days
          default         { "$prefix $($span.Days) days $postfix "; break }
       }
       )".Trim()
    }
}

function Get-UserConfirmation {
    param(
        [string]$title = "operation",
        [string]$message = "> are you sure?"
    )

    $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
    $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
    $result = $host.ui.PromptForChoice($title, $message, $options, 1)

    switch ($result) {
        0 { return $true }
        1 { return $false }
    }
}

function Start-ReplaceConfigVars {
    param(
        $app,
        $content = ""
    )

    # coerce to string.
    $content = "$content";

    if (-not $app.configvars) {
        # Write-Warning "App $($app) does not have any ConfigVars."
        return $content
    }

    if ($content.indexOf("{ConfigVar:") -eq -1) {
        # Write-Info "Content $($content) does have any {ConfigVars:*} variables."
        return $content
    }

    $keys = $app.configvars.Keys
    Write-Info -DarkGray "    * Processing $($keys.Count) ContentVars ..."

    # pre-process file content.
    # - replace all instances of key} with their configured values.
    $keys | ForEach {
        $key = "{ConfigVar:$_}"
        $value =  $app.configvars[$_]
        # Write-Info "Processing $($key):=$($value)."

        $after = $content.Replace($key, $value)
        if ($after -ne $content) {
            Write-Info -DarkGray "      * Replaced" -DarkYellow $key -DarkGray ":=" -Yellow $value -DarkGray "..."
            $content = $after
        }
    }

    if ($content.indexOf("{ConfigVar:") -ne -1) {
        Write-Warning "Not all occurences of {ConfigVar:*} were replaced!"
    }

    return $content
}

function Start-ReplaceHtmlEntities {
    param(
        $content = ""
    )

    Write-Debug -DarkGray "    * Processing Html Entities ..."

    # create a case sensitive hashtable, @{} isnt (!)
    # see also https://blogs.technet.microsoft.com/heyscriptingguy/2016/01/09/weekend-scripter-unexpected-case-sensitivity-in-powershell/
    $entities = New-Object -TypeName System.Collections.Hashtable
    $entities.Add('ä', "&auml;");
    $entities.Add('ö', "&ouml;");
    $entities.Add('ü', "&uuml;");
    $entities.Add('ß', "ss");
    $entities.Add('Ä', "&Auml;");
    $entities.Add('Ü', "&Uuml;");
    $entities.Add('Ö',"&Ouml;");

    $entities.Keys | ForEach-Object {
        $key = $_
        $value = $entities[$_]
        $after = $content.Replace($key, $value)
        if ($after -ne $content) {
            Write-Debug -DarkGray "      * Replaced" -DarkYellow $key -DarkGray ":=" -Yellow $value -DarkGray "..."
            $content = $after
        }
    }

    return $content
}

Export-ModuleMember -Function *
