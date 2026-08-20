add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}

public class CertCallback {
    public static bool Validate(
        object sender,
        X509Certificate cert,
        X509Chain chain,
        SslPolicyErrors errors)
    {
        return true;
    }
}
"@

function Set-ConnectionDetails {
    param(
        [string]$serverUrl,
		[string]$username,
		[string]$password,
		[bool]$certCheck = $true
    )

	if($certCheck -eq $false){
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()
	}
	
	# Build x-meshauth header
	$global:authHeader = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username)) + "," +
				  [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($password))

    [System.Uri]$global:serverUrl = $serverUrl
}
