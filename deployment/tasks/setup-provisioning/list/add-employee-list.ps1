
$siteUrl = $apps.default.url

Write-Step "Connect to Site '$($siteUrl)'... " -nonewline

$connectionChild = Connect-PnPOnline -Url $siteUrl -Credentials $apps.default.credential -ReturnConnection

if($connectionChild -ne $null){

    Write-Success "Connection OK!"

    # ====================================================================================================
    # add content type and list
    # ====================================================================================================

    # Set-PnPTraceLog -On -Level Debug -Delimiter ";" -LogFile "c:\log\traceoutput.csv"

    Write-Step "creating information list on $($siteUrl)"
    Apply-PnPProvisioningTemplate -Connection $connectionChild -Path (Resolve-Path $pwd\files\gridworksconfig\lists\employee-list.xml) -Parameters @{"TermGroupName"="$($apps.default.tenant)"}

    # Set-PnPTraceLog -Off
}
