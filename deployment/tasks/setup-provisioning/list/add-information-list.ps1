
$siteUrl = $apps.default.url

Write-Step "Connect to Site '$($siteUrl)'... " -nonewline

$connectionChild = Connect-PnPOnline -Url $siteUrl -Credentials $apps.default.credential -ReturnConnection

if($connectionChild -ne $null){

    Write-Success "Connection OK!"

    # ====================================================================================================
    # add content type and list
    # ====================================================================================================

    # Set-PnPTraceLog -On -Level Debug -Delimiter ";" -LogFile "c:\log\traceoutput.csv"

    Write-Step "creating information item content types on $($siteUrl)"
    Apply-PnPProvisioningTemplate -Connection $connectionChild -Path (Resolve-Path $pwd\files\gridworksconfig\contenttypes\information-items-group-0.xml) -Parameters @{"TermGroupName"="$($apps.default.tenant)"}

    Write-Step "creating information list on $($siteUrl)"
    Apply-PnPProvisioningTemplate -Connection $connectionChild -Path (Resolve-Path $pwd\files\gridworksconfig\lists\information-list.xml) -Parameters @{"TermGroupName"="$($apps.default.tenant)"}

    Write-Step "Add Inforamtion Datarows"
    $ProjectOwner = "$($apps.default.administrator)"
    $OwnerEmail = "$($apps.default.administrator)"
    Apply-PnPProvisioningTemplate -Connection $connectionChild -Path (Resolve-Path $pwd\files\gridworksconfig\lists\datarows\ppm-projects-datarows.xml) -Parameters @{"$ProjectOwner" = $ProjectOwner; "OwnerEmail" = $OwnerEmail;}

    # Set-PnPTraceLog -Off
}
