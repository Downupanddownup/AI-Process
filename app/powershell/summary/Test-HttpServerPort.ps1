#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [int]$Port
)

$props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
$listeners = $props.GetActiveTcpListeners()
$found = $listeners | Where-Object { $_.Port -eq $Port -and $_.Address.ToString() -eq '127.0.0.1' }

if ($found) {
    exit 0
} else {
    exit 1
}
