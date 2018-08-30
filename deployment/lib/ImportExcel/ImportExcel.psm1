Add-Type -Path "$($PSScriptRoot)\EPPlus.dll"

function Import-Excel {
    param(
        [Alias("FullName")]
        [Parameter(ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, Mandatory=$true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        $Path,
        [Alias("Sheet")]
        $WorkSheetname=1,
        [int]$HeaderRow=1,
        [string[]]$Header,
        [switch]$NoHeader
    )

    Process {

        $Path = (Resolve-Path $Path).ProviderPath
        write-debug "target excel file $Path"

        $stream = New-Object -TypeName System.IO.FileStream -ArgumentList $Path,"Open","Read","ReadWrite"
        $xl = New-Object -TypeName OfficeOpenXml.ExcelPackage -ArgumentList $stream

        $workbook  = $xl.Workbook

        $worksheet=$workbook.Worksheets[$WorkSheetname]
        $dimension=$worksheet.Dimension

        $Rows=$dimension.Rows
        $Columns=$dimension.Columns

        if($NoHeader) {
            foreach ($Row in 0..($Rows-1)) {
                $newRow = [Ordered]@{}
                foreach ($Column in 0..($Columns-1)) {
                    $propertyName = "P$($Column+1)"
                    $newRow.$propertyName = $worksheet.Cells[($Row+1),($Column+1)].Value
                }

                [PSCustomObject]$newRow
            }
        } else {
            if(!$Header) {
                $Header = foreach ($Column in 1..$Columns) {
                    $worksheet.Cells[$HeaderRow,$Column].Value
                }
            }

            if($Rows -eq 1) {
                $Header | ForEach {$h=[Ordered]@{}} {$h.$_=''} {[PSCustomObject]$h}
            } else {
                foreach ($Row in ($HeaderRow+1)..$Rows) {
                    $h=[Ordered]@{}
                    foreach ($Column in 0..($Columns-1)) {
                        if($Header[$Column].Length -gt 0) {
                            $Name    = $Header[$Column]
                            $h.$Name = $worksheet.Cells[$Row,($Column+1)].Value
                        }
                    }
                    [PSCustomObject]$h
                }
            }
        }

        $stream.Close()
        $stream.Dispose()
        $xl.Dispose()
        $xl = $null
    }
}