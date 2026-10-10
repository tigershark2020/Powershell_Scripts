# Requires PowerShell 5+ and Hyper-V module
# Run as Administrator

function Send_Pushover_Notification
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$UserKey,       # Your Pushover user key

		[Parameter(Mandatory = $true)]
		[string]$ApiToken,      # Your Pushover API token

		[Parameter(Mandatory = $true)]
		[string]$Pushover_Message,       # Message text

		[Parameter(Mandatory = $true)]
		[string]$Pushover_Title, # Optional title

		[string]$Priority = "0"			 # Priority (-1, 0, 1, 2)
	)

	try {
		# Prepare POST body
		$body = @{
			token    = $ApiToken
			user     = $UserKey
			message  = $Message
			title    = $Title
			priority = $Priority
		}

		# Send request to Pushover API
		$response = Invoke-RestMethod `
			-Uri "https://api.pushover.net/1/messages.json" `
			-Method Post `
			-Body $body `
			-ContentType "application/x-www-form-urlencoded"

		# Check response
		if ($response.status -eq 1) {
			Write-Host "Notification sent successfully!" -ForegroundColor Green
		} else {
			Write-Host "Failed to send notification. Response:" -ForegroundColor Red
			$response | Format-List
		}
	}
	catch {
		Write-Host "Error sending notification: $_" -ForegroundColor Red
	}
}

function Monitor_mDNS_Queries
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$multicastIPStr,		#Multicast IP Str 224.0.0.251

		[Parameter(Mandatory = $true)]
		[int]$port,						#mDNS Port 5353

		[Parameter(Mandatory = $true)]
		[string]$localIP = "",          # Local Network Device IP
		
		[Parameter(Mandatory = $true)]
		[string]$VMName = "",          # Hyper-V VM to start
		
		[Parameter(Mandatory = $true)]
		[string]$MatchName = "",	   # mDNS query name to trigger VM start
	
		[Parameter(Mandatory = $true)]
		[string]$UserKey,       # Your Pushover user key

		[Parameter(Mandatory = $true)]
		[string]$ApiToken,		# Your Pushover API token
	
		[Parameter(Mandatory = $true)]
		[string]$Pushover_Message,       # Message text

		[Parameter(Mandatory = $true)]
		[string]$Pushover_Title, 		 # Title
		
		[Parameter(Mandatory = $true)]
		[int64]$Notify_Delay_Time		 # Notify Delay Time in Seconds
	)
	
	# LAN IP to bind to (change to your actual IP)
	$multicastIP = [System.Net.IPAddress]::Parse($multicastIPStr)

	# Load Hyper-V module if available
	try {
		Import-Module Hyper-V -ErrorAction Stop
	} catch {
		Write-Error "Hyper-V module not found. Install Hyper-V before running."
		exit 1
	}

	# Create UDP listener on port 5353
	$udpClient = New-Object System.Net.Sockets.UdpClient
	$udpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
	$udpClient.Client.Bind((New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse($localIP), $port)))
	$udpClient.JoinMulticastGroup($multicastIP)

	$udpClient.Client.ReceiveTimeout = 0  # No timeout

	Write-Host "Listening for mDNS queries on UDP port 5353..."
	$last_run_epoch = [int64](0)

	while ($true) {
		try {
			# Receive packet
			$remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($localIP), 0)
			$bytes = $udpClient.Receive([ref]$remoteEP)

			# Convert bytes to hex for inspection
			$hex = ($bytes | ForEach-Object { $_.ToString("X2") }) -join " "

			# mDNS packets are DNS format — extract query name
			$queryName = ""
			$pos = 12  # DNS header is 12 bytes
			while ($pos -lt $bytes.Length) {
				$len = $bytes[$pos]
				if ($len -eq 0) { break }
				$pos++
				$queryName += [System.Text.Encoding]::ASCII.GetString($bytes[$pos..($pos+$len-1)]) + "."
				$pos += $len
			}

			Write-Host "Received mDNS query from $($remoteEP.Address): $queryName"

			# Trigger VM start if match found
			if ($queryName.TrimEnd('.') -ieq $MatchName) {
				Write-Host "Match found for '$MatchName'. Starting VM '$VMName'..."
				try {
					$current_epoch = [int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds
					$next_run_epoch = [int64]($last_run_epoch + $Notify_Delay_Time)
					if($current_epoch -gt $next_run_epoch) {
						Start-VM -Name $VMName -ErrorAction Stop
						Write-Host "VM '$VMName' started successfully."
						Send_Pushover_Notification -UserKey $UserKey -ApiToken $ApiToken -Pushover_Message "AirPrint Started, Please Wait" -Pushover_Title "Print Alerts"
						$last_run_epoch = $current_epoch
					}
				}
				catch {
					Write-Error "Failed to start VM: $_"
				}
			}

		} catch {
			Write-Error "Error receiving UDP packet: $_"
		}
	}
}

function Monitor_mDNS_Queries_Main
{
	while ($true) {
		try{
			Monitor_mDNS_Queries -multicastIP "224.0.0.251" -port 5353 -localIP "192.168.1.11" -VMName "" -MatchName "" -UserKey "" -ApiToken "" -Pushover_Message "AirPrint Started, Please Wait" -Pushover_Title "Print Alerts" -Notify_Delay_Time 1800	
		}
		catch{
			
		}
	}
}

Monitor_mDNS_Queries_Main
