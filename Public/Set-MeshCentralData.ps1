function Set-MeshCentralData {
	[CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet( 'changeDeviceMesh')]
        [string]$action,
        [hashtable]$requestData
    )

    # WebSocket client
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ct = [System.Threading.CancellationToken]::None

    # Add authentication header
    $ws.Options.SetRequestHeader("x-meshauth", $global:authHeader)

    # Trust all certs
    if([bool]($PSVersionTable.PSVersion.Major -ge 7)){
        $ws.Options.RemoteCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback] [CertCallback]::Validate
    } else {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()
	}

    $uri = [System.Uri]$global:serverUrl
    $errorVar = $null
    try {
        $ws.ConnectAsync($uri, $ct).Wait()
		#Write-Host "Connected"
    }
    catch {
        Write-Host "Error:" $_.Exception.InnerException.Message
        Write-Host "Details:" $_.Exception.InnerException.ToString()
    }

    $request = @{ action = $action; responseid = 'meshctrl' } 
    if($requestData){
        $request += $requestData
    }
    $request = $request | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($request)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    try {
		if ($PSCmdlet.ShouldProcess(
            "MeshCentral",
            "Perform action '$action'" ))
		{
			$ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

			$result = $null

			while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {

				$response = Receive-WebSocketMessage -WebSocket $ws
				if (-not $response) { break }

				$json = $null
				try { $json = $response | ConvertFrom-Json } catch {}

				if ($json -eq $null) { continue }

				# your switch block remains unchanged
				$result = Switch-Action -json $json
				if ($result) {
					$ws.CloseAsync(
						[System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", [System.Threading.CancellationToken]::None
					).Wait()

					return $result
				}
		
			}
		}
    }
    catch {
        #Write-Host "Error:" $_.Exception.InnerException.Message
        #Write-Host "Details:" $_.Exception.InnerException.ToString()
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", [System.Threading.CancellationToken]::None).Wait()
        $ws.Dispose()
    }

    return $result
}