# https://poeditor.com/docs/api#projects_view
function Get-PoEditorApiToken {
    $token = $translations.api_token
    Write-Debug "Using api token $token ..."
    return $token
}

# https://poeditor.com/docs/api#projects_view
function Get-PoEditorProjectDetails($id) {
    $result  = Invoke-WebRequest -Method POST -Uri https://api.poeditor.com/v2/projects/view -Body @{
        "api_token" = (Get-PoEditorApiToken);
        "id" = $id;
    }

    $result = "$($project.Content)"
    Write-Debug $result

    $json = $result | ConvertFrom-Json
    $project = $json.result.project
    if (-not $project) {
        Write-Error "Expected project in result, got: $result"
    }

    return $project
}

# https://poeditor.com/docs/api#languages_list
function Get-PoEditorProjectLanguages($id) {
    $result = Invoke-WebRequest -Method POST -Uri https://api.poeditor.com/v2/languages/list -Body @{
        "api_token" = (Get-PoEditorApiToken);
        "id" = $id;
    }

    $result = "$($result.Content)"
    Write-Debug $result

    $json = $result | ConvertFrom-Json
    $languages = $json.result.languages
    if (-not $languages) {
        Write-Error "Expected url in result, got: $result"
    }

    return $languages
}

function Import-PoeditorTranslations {
    $translations.projects | ForEach-Object {
        Import-PoeditorTranslation $_
    }
}

function Import-PoeditorTranslation($translation) {
    $id = $translation.id
    $name = $translation.name
    $path = $translation.path

    Write-Step "Importing translation $id, $name ..."

    Write-SubStep "Loading languages ..."
    $languages = Get-PoEditorProjectLanguages $id
    Write-SubSubStep "Project has $($languages.Count) languages"

    $languages | ForEach-Object {
        $language = $_.code
        Write-SubStep "Importing language $language"

        $result = Invoke-WebRequest -Method POST -Uri https://api.poeditor.com/v2/projects/export -Body @{
            "api_token" = (Get-PoEditorApiToken);
            "language" = $language;
            "type" = "json";
            "id" = $id;
        }

        $result = "$($result.Content)"
        Write-Debug $result

        $json = $result | ConvertFrom-Json
        $url = $json.result.url
        if (-not $url) {
            Write-Error "Expected url in result, got: $result"
            continue
        }

        Write-SubSubStep "Downloading json from $url"
        $filename = "$($path)\$name.$($language).json"

        $result = Invoke-WebRequest -Method GET -Uri $url -OutFile $filename
        if ($result) {
            Write-SubSubStep "Result: $result"
        }
    }
}

Export-ModuleMember -Function *
