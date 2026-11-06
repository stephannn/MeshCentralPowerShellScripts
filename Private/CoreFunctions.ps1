Function Convert-FromUnixDate ($UnixDate) {
    if([string]::IsNullOrEmpty($UnixDate) -eq $false) {
        return ((Get-Date "1970-01-01 00:00:00").AddSeconds($UnixDate / 1000))
    }
    return $null
}

function Write-Log{
    Param(
        [Parameter(
        Mandatory = $true,
        ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogText,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string]$Component = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information','Warning','Error')]
        [string]$Type = 'Information',

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [int]$Thread = $PID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string]$File = '',

        [Parameter(Mandatory = $false)]
        [int]$LogMaxSize = 2.5MB,

        [Parameter(Mandatory = $false)]
        [int]$LogMaxHistory = 1
    )
    
    Begin
    {
        switch ($Type)
        {
            'Information' { $TypeNum = 1 }
            'Warning'     { $TypeNum = 2 }
            'Error'       { $TypeNum = 3 }
        }
    
        if (-not $Global:LogFilePath) {
            Write-Error -Message 'Variable $LogFilePath not defined in scope $Global:'
            exit 1
        }
		
		if (-not (Test-Path -Path (Split-Path $Global:LogFilePath -Parent) -PathType Container)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $Global:LogFilePath -Parent) | Out-Null
        }
        
        if (-not (Test-Path -Path $Global:LogFilePath -PathType Leaf)) {
            New-Item -Path $Global:LogFilePath -ItemType File -ErrorAction Stop | Out-Null
        }
        
        $LogFile = Get-Item -Path $Global:LogFilePath
        if ($LogFile.Length -ge $LogMaxSize) {
            $ArchiveLogFiles = Get-ChildItem -Path $LogFile.Directory -Filter "$($LogFile.BaseName)*.log" | Where-Object {$_.Name -match "$($LogFile.BaseName)-\d{8}-\d{6}\.log"} | Sort-Object -Property BaseName
            if ($ArchiveLogFiles.Count -gt $LogMaxHistory) {
                $ArchiveLogFiles | Select-Object -Skip ($ArchiveLogFiles.Count - $LogMaxHistory) | Remove-Item
            }

            $NewFileName = "{0}-{1:yyyyMMdd-HHmmss}{2}" -f $LogFile.BaseName, $LogFile.LastWriteTime, $LogFile.Extension
            $LogFile | Rename-Item -NewName $NewFileName
            New-Item -Path $Global:LogFilePath -ItemType File -ErrorAction Stop | Out-Null
        }
    }
    
    Process
    {
        $now = Get-Date
        $Bias = ($now.ToUniversalTime() - $now).TotalMinutes
        [string]$Line = "<![LOG[{0}]LOG]!><time=`"{1:HH:mm:ss.fff}{2}`" date=`"{1:MM-dd-yyyy}`" component=`"{3}`" context=`"`" type=`"{4}`" thread=`"{5}`" file=`"{6}`">" -f $LogText, $now, $Bias, $Component, $TypeNum, $Thread, $File
        $Line | Out-File -FilePath $Global:LogFilePath -Encoding utf8 -Append -ErrorAction Stop
        #Write-Host $LogText
    }
    
    End
    {
    }
}


function Receive-WebSocketMessage {
    param(
        [System.Net.WebSockets.ClientWebSocket]$WebSocket,
        [int]$BufferSize = 8192
    )

    $buffer = New-Object byte[] $BufferSize
    $ms = New-Object System.IO.MemoryStream

    do {
        $segment = [System.ArraySegment[byte]]::new($buffer)
        $result = $WebSocket.ReceiveAsync($segment, [System.Threading.CancellationToken]::None).Result

        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            return $null
        }

        # Append bytes received
        $ms.Write($buffer, 0, $result.Count)

    } while (-not $result.EndOfMessage)

    # Convert accumulated bytes to string
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Switch-Action {
    param(
        [PSCustomObject]$json
    )
    #Write-Host "Switch Action"

    $meshesResult      = @()
    $nodesResult       = @()
    $nodesDetailResult = @()
    $removeDeviceMesh  = $null
    $changeDeviceMesh  = $null

    #Write-Host $json
    switch ($json.action.ToLower()) {
        'serverinfo' {
            Write-Verbose "Server info received:"
            $json.serverinfo | ConvertTo-Json -Compress | Write-Verbose
        }
        'serverwarnings' {
            Write-Verbose "Server warning received:"
            $json.serverwarnings | ConvertTo-Json -Compress | Write-Verbose
        }
        'meshes' {
            foreach ($m in $json.meshes) {
                #$id = ($m._id -split '/')[2]
                $meshesResult += [pscustomobject][ordered]@{GroupID = ($m._id -split '/')[2]; GroupName = $($m.name)}
            }
        }
        'nodes' {

            foreach ($meshId in $json.nodes.PSObject.Properties.Name) {
                $nodes = $json.nodes.$meshId
                $DeviceGroupId = ($meshId -split '//')[1]
                foreach ($node in $nodes) {
                    $nodesResult += [pscustomobject][ordered]@{DeviceId = ($node._id -split '/')[2]; DeviceName = $($node.name); OS = $node.osdesc; DeviceGroupId = $DeviceGroupId}
                }
            }
        }
        'getDeviceDetails' {
            #Write-Verbose $json.data
            foreach ($detail in ($json.data | ConvertFrom-CSV)){
                #$nodesDetailResult += [pscustomobject][ordered]@{DeviceId = ($detail.id -split '/')[2]; DeviceName = $($detail.name); SerialNumber = $detail.biosSerial ;OS = $detail.osdesc; LastConnectTime = (Convert-FromUnixDate $detail.lastConnectTime)}
                $nodesDetailResult += [pscustomobject][ordered]@{
                    DeviceId        = ($detail.id -split '/')[2]
                    DeviceName      = $detail.rname
                    SerialNumber    = if ($detail.biosSerial) {
                                        $detail.biosSerial
                                    } else {
                                        $detail.boardSerial
                                    }
					MeshName        = $detail.name
                    OS              = $detail.osdesc
                    LastConnectTime = Convert-FromUnixDate $detail.lastConnectTime
                }
            }
        }
        'changeDeviceMesh'{
            $changeDeviceMesh = @($true, "Device moved")
        }
		'changeDevice'{
            $changeDevice = @($true, "Device changed")
        }
        'removedevices'{
            $removeDeviceMesh = @($true, "Device removed")
        }
        'close' {
            Write-Verbose "Close received:"
        }
        default {
            # Uncomment for debugging unknown messages
            # Write-Host "Other message: $response"
        }
    }
    #$nodesDetailResult
    if($meshesResult.Length -gt 0) { return $meshesResult }
    if($nodesResult.Length -gt 0) { return $nodesResult }
    if($nodesDetailResult.Length -gt 0) { return $nodesDetailResult }
    if($null -ne $changeDeviceMesh) { return $changeDeviceMesh }
	if($null -ne $changeDevice) { return $changeDevice }
    if($null -ne $removeDeviceMesh) { return $removeDeviceMesh }

    return $null
}