Param(
    [string]$AzureUserName,
    [string]$AzurePassword,
    [string]$AzureTenantID,
    [string]$AzureSubscriptionID,
    [string]$ODLID,
    [string]$InstallCloudLabsShadow,
    [string]$DeploymentID,
    [string]$vmAdminUsername,
    [string]$vmAdminPassword,
    [string]$trainerUserName,
    [string]$trainerUserPassword
)

$logPath = 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt'
New-Item -Path (Split-Path -Parent $logPath) -ItemType Directory -Force | Out-Null
Start-Transcript -Path $logPath -Append

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ErrorActionPreference = 'Stop'

    function CreateCredFile {
        param(
            [string]$UserName,
            [string]$Password,
            [string]$TenantId,
            [string]$SubscriptionId,
            [string]$LabId,
            [string]$DeploymentId
        )

        $commonUri = 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/'
        $labFiles = 'C:\LabFiles'
        $desktop = 'C:\Users\Public\Desktop'
        New-Item -Path $labFiles -ItemType Directory -Force | Out-Null
        New-Item -Path $desktop -ItemType Directory -Force | Out-Null

        $values = @{
            'AZURE_USERNAME' = $UserName
            'AZURE_PASSWORD' = $Password
            'AZURE_TENANT_ID' = $TenantId
            'AZURE_SUBSCRIPTION_ID' = $SubscriptionId
            'ODL_ID' = $LabId
            'DEPLOYMENT_ID' = $DeploymentId
            'AzureUserName' = $UserName
            'AzurePassword' = $Password
            'AzureTenantID' = $TenantId
            'AzureSubscriptionID' = $SubscriptionId
            'ODLID' = $LabId
            'DeploymentID' = $DeploymentId
        }

        foreach ($fileName in @('AzureCreds.txt', 'AzureCreds.ps1')) {
            $source = Join-Path $labFiles $fileName
            Invoke-WebRequest -Uri ($commonUri + $fileName) -OutFile $source -UseBasicParsing
            $text = Get-Content -Path $source -Raw
            foreach ($key in $values.Keys) {
                $value = [string]$values[$key]
                $text = $text.Replace("<$key>", $value).Replace("{{$key}}", $value).Replace("__$key__", $value)
            }
            Set-Content -Path $source -Value $text -Encoding UTF8
            Copy-Item -Path $source -Destination $desktop -Force
        }
    }

    CreateCredFile -UserName $AzureUserName -Password $AzurePassword -TenantId $AzureTenantID `
        -SubscriptionId $AzureSubscriptionID -LabId $ODLID -DeploymentId $DeploymentID

    # VM Shadow connects with this instructor account. The platform passes the value as a string;
    # only an explicit false disables account creation.
    if ($InstallCloudLabsShadow -ne 'false' -and $InstallCloudLabsShadow -ne 'False' -and
        $InstallCloudLabsShadow -ne '0' -and $trainerUserName -and $trainerUserPassword) {
        $securePassword = ConvertTo-SecureString $trainerUserPassword -AsPlainText -Force
        $existing = Get-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-LocalUser -Name $trainerUserName -Password $securePassword `
                -PasswordNeverExpires -AccountNeverExpires -Description 'CloudLabs instructor VM Shadow account' | Out-Null
        } else {
            Set-LocalUser -Name $trainerUserName -Password $securePassword -PasswordNeverExpires
        }
        Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $trainerUserName -ErrorAction SilentlyContinue
    }

    Write-Output 'Stage 1 minimal portal-first bootstrap completed.'
}
catch {
    Write-Error $_
    throw
}
finally {
    Stop-Transcript
}
