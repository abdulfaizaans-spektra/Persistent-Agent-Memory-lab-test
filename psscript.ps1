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
            'AZURE_USERNAME'        = $UserName
            'AZURE_PASSWORD'        = $Password
            'AZURE_TENANT_ID'       = $TenantId
            'AZURE_SUBSCRIPTION_ID' = $SubscriptionId
            'ODL_ID'                = $LabId
            'DEPLOYMENT_ID'         = $DeploymentId
            'AzureUserName'         = $UserName
            'AzurePassword'         = $Password
            'AzureTenantID'         = $TenantId
            'AzureSubscriptionID'   = $SubscriptionId
            'ODLID'                 = $LabId
            'DeploymentID'          = $DeploymentId
        }

        foreach ($fileName in @('AzureCreds.txt', 'AzureCreds.ps1')) {

            $source = Join-Path $labFiles $fileName

            $webRequestParams = @{
                Uri             = $commonUri + $fileName
                OutFile         = $source
                UseBasicParsing = $true
            }

            Invoke-WebRequest @webRequestParams

            $text = Get-Content -Path $source -Raw

            foreach ($key in $values.Keys) {
                $value = [string]$values[$key]

                $text = $text.Replace("<$key>", $value)
                $text = $text.Replace("{{$key}}", $value)
                $text = $text.Replace("__$key__", $value)
            }

            Set-Content -Path $source -Value $text -Encoding UTF8

            Copy-Item -Path $source -Destination $desktop -Force
        }
    }

    $credentialFileParams = @{
        UserName       = $AzureUserName
        Password       = $AzurePassword
        TenantId       = $AzureTenantID
        SubscriptionId = $AzureSubscriptionID
        LabId          = $ODLID
        DeploymentId   = $DeploymentID
    }

    CreateCredFile @credentialFileParams

    # VM Shadow connects with this instructor account.
    # Only an explicit false/0 disables account creation.

    $shadowEnabled = (
        $InstallCloudLabsShadow -ne 'false' -and
        $InstallCloudLabsShadow -ne 'False' -and
        $InstallCloudLabsShadow -ne '0'
    )

    if ($shadowEnabled -and $trainerUserName -and $trainerUserPassword) {

        $securePassword = ConvertTo-SecureString $trainerUserPassword -AsPlainText -Force

        $existing = Get-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue

        if (-not $existing) {

            $newUserParams = @{
                Name                 = $trainerUserName
                Password             = $securePassword
                PasswordNeverExpires = $true
                AccountNeverExpires  = $true
                Description          = 'CloudLabs instructor VM Shadow account'
            }

            New-LocalUser @newUserParams | Out-Null
        }
        else {

            $updateUserParams = @{
                Name                 = $trainerUserName
                Password             = $securePassword
                PasswordNeverExpires = $true
            }

            Set-LocalUser @updateUserParams
        }

        $groupParams = @{
            Group                 = 'Remote Desktop Users'
            Member                = $trainerUserName
            ErrorAction           = 'SilentlyContinue'
        }

        Add-LocalGroupMember @groupParams
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
