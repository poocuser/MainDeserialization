[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][String]$Secret,
    [Parameter(Mandatory = $true)][String]$TenantId,
    [Parameter(Mandatory = $true)][String]$ClientID,
    [Parameter(Mandatory = $true)][String]$ProjectName,
    [Parameter(Mandatory = $true)][String]$Premium,
    [Parameter(Mandatory = $true)][String]$Action,
    [Parameter(Mandatory = $false)][String]$WorkspaceName,
    [Parameter(Mandatory = $false)][String]$UserEmail,
    [Parameter(Mandatory = $false)][String]$Notify,
    [Parameter(Mandatory = $false)][String]$PowerAutomateEndPoint,
    [Parameter(Mandatory = $false)][String]$WorkspaceWebUrl
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$root_path = (Get-Location).Path
Write-Information "Working Directory: $root_path"

Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser
Import-Module -Name MicrosoftPowerBIMgmt

$indention = "`t"

$git_event_before = $env:GIT_EVENT_BEFORE
$git_event_after = $env:GIT_EVENT_AFTER
$triggered_by = $env:BUILD_REASON + $env:GIT_TRIGGER_NAME
$manual_trigger_path_filter = $env:MANUAL_TRIGGER_PATH_FILTER

$tenant_id = $TenantId
$client_id = $ClientID
$client_secret = $Secret
$dev_var="DEV"
$test_var="TEST"
#$PowerAutomateEndPoint = $env:URL_PowerAutomate_EndPoint
Write-Host "OUTSIIIIIIIIDE FUNCTION:" $PowerAutomateEndPoint
#$login_info = "User ID=app:$client_id@$tenant_id;Password=$client_secret"

[securestring]$sec_client_secret = ConvertTo-SecureString $client_secret -AsPlainText -Force
[pscredential]$credential = New-Object System.Management.Automation.PSCredential ($client_id, $sec_client_secret)
Connect-PowerBIServiceAccount -Credential $credential -ServicePrincipal -TenantId $tenant_id

#Get Modified Pbix Files
if ($triggered_by -like "*CI" -or $triggered_by -eq "push") {
    Write-Information "git diff --name-only $git_event_before $git_event_after --diff-filter=ACM ""*.pbix"""
    $pbix_files = @($(git diff --name-only $git_event_before $git_event_after --diff-filter=ACM "*.pbix"))
    $pbix_files = $pbix_files | ForEach-Object { Join-Path $root_path $_ | Get-Item }
    if ($pbix_files.Count -eq 0) {
      Write-Warning "Something went wrong! Could not find any changed .pbix files using the above 'git diff' command! XD"
      Write-Information "Getting all .pbix files in the repo to be sure to get all changes!!!"
      $pbix_files = Get-ChildItem -Path (Join-Path $root_path $manual_trigger_path_filter) -Recurse -Filter "*.pbix" -File
    }
   }
   elseif ($triggered_by -eq "Manual" -or $triggered_by -eq "workflow_dispatch") {
    $pbix_files = Get-ChildItem -Path (Join-Path $root_path $manual_trigger_path_filter) -Recurse -Filter "*.pbix" -File
   }
   else {
    Write-Error "Invalid Trigger!"
   }
   Write-Information "Changed .pbix files ($($pbix_files.Count)):"
   $pbix_files | ForEach-Object { Write-Information "$indention$($_.FullName)" }
# ========================================================================================================================
# Helper function used for Invoking Power BI API
Function Invoke-PowerBI-API($uri, $method){
 
    $TokenArgs = @{
        Grant_type = 'client_credentials'
        Resource   = 'https://analysis.windows.net/powerbi/api'
        Client_id  = $ClientID
        Client_secret = $Secret
        Scope = "https://analysis.windows.net/powerbi/api/.default"
    }
    $out = Invoke-RestMethod -Uri https://login.microsoftonline.com/$tenant_id/oauth2/token -Body $TokenArgs -Method POST
 
    #Save token
    $tokenaccess = $out.access_token

    #Get group API test
    $header = @{
        'Content-Type'='application/json'
        'Authorization'= "Bearer  $tokenaccess" 
    }

    $ResponseOut = Invoke-RestMethod -Method $method -Uri $uri -Headers $header

    return $ResponseOut.value
}
# ========================================================================================================================
# Helper function used for Refreshing Dataset trought Invoking Power BI API
Function New-DatasetRefresh {
    Param(
        [parameter(Mandatory = $true)][string]$WorkspaceName,
        [parameter(Mandatory = $true)][string]$DataSetName
        #[parameter(Mandatory = $true)]$AccessToken
    )
    $workspace = Get-PowerBIWorkspace -Filter "name eq '$WorkspaceName'"
    #$GroupPath = Get-PowerBIGroupPath -WorkspaceName $WorkspaceName -AccessToken $AccessToken
    #$set = Get-PowerBIDataSet -GroupPath $GroupPath -AccessToken $AccessToken -Name $DatasetName
    #$set = Get-PowerBIDataset -Filter "name eq '$DataSetName'"
    $set = Get-PowerBIDataset -Name $DataSetName
    if ($set) {
        #$url = $powerbiUrl + $GroupPath + "/datasets/$($set.id)/refreshes"
        $url = "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.Id)"+ "/datasets/$($set.id)/refreshes"

        #Invoke-API -Url $url -Method "Post" -ContentType "application/json" -AccessToken $AccessToken
        Invoke-PowerBI-API -uri $url -method "Post"
    }
    else {
        Write-Warning "The dataset: $DataSetName does not exist.."
    }
    
}
# ========================================================================================================================
# Helper function used for Sending Email to Power Automate
# ========================================================================================================================
Function InvokePowerAutomate_Email{
    Param(
        [parameter(Mandatory = $true)]$PowerAutomateEndPoint,
        [parameter(Mandatory = $true)]$Notify,
        [parameter(Mandatory = $true)]$WorkspaceName,
        [parameter(Mandatory = $true)]$WorkspaceWebUrl
    )

    Write-Host "ddddddddddd" $WorkspaceWebUrl

    $header = @{
        "Accept"="application/json"
        "Content-Type"="application/json"
        #"connectapitoken"="97fe6ab5b1a640909551e36a071ce9ed"
    } 
    $postParams = @{
        UserEmail=$Notify;
        WorkspaceName=$WorkspaceName;
        WorkspaceWebUrl=$WorkspaceWebUrl;
    } | ConvertTo-Json

    Write-Host "ccccccccccc"  $postParams

    Invoke-WebRequest -Uri $PowerAutomateEndPoint -Method POST -Body $postParams -Headers $header | ConvertTo-HTML
}
######Environment-Setup
Function Environment-Setup{
    [parameter(Mandatory = $true)]$ProjectName
    [parameter(Mandatory = $true)]$Premium

    # Get the workspace according to workspaceName
    $workspace = Get-PowerBIWorkspace -Filter "name eq '$ProjectName'"
    #Check if exists
    if ($workspace) {
        Write-Host "Environment: $ProjectName already exists"
        return
    }

    if($Premium -eq "true"){
        Write-Host "----------PREMIUM ENVIRONMENT CONFIGURATION CHOSEN----------"
        #Get Capacity ID
        $apiUri = "https://api.powerbi.com/v1.0/myorg/"
        $getCapacityUri = $apiUri + "capacities"
        $capacitiesList = Invoke-PowerBI-API $getCapacityUri "Get"
        $capacityID = $capacitiesList | Where-Object {$_.displayName -eq "embedpbi"}
        $capacityID.id
        #Create workspace
        Write-Host "Trying to create workspace: $ProjectName"
        $workspace = New-PowerBIWorkspace -Name $ProjectName
        #Set Capacity
        Set-PowerBIWorkspace  -Id $workspace.Id -CapacityId $capacityID.id
    }else{
        Write-Host "----------STANDARD ENVIRONMENT CONFIGURATION CHOSEN-----------"
        #Create workspace
        $workspace = New-PowerBIWorkspace -Name $ProjectName
        $test_workspace = New-PowerBIWorkspace -Name "$($ProjectName)-$($test_var)"
        $dev_workspace = New-PowerBIWorkspace -Name "$($ProjectName)-$($dev_var)"
        $workspaces = $workspace,$test_workspace,$dev_workspace

        #Adding User As Admin
        Write-Host "Adding user to a Workspace"
        foreach ($workspace in $workspaces) {
            $ApiUrl = "groups/" + $workspace.Id + "/users"
            $WorkspaceUsers = (Invoke-PowerBIRestMethod -Url $ApiUrl -Method Get) | ConvertFrom-Json
            $UserObject = $WorkspaceUsers.value | Where-Object { $_.emailAddress -like $UserEmail }
            if($UserObject){
                Write-Output "User Already Exists"
            }else{
                Add-PowerBIWorkspaceUser -Id $workspace.Id -UserEmailAddress $UserEmail -AccessRight Admin
            }
        }
    }
}
########CI
Function CI-Build {
    Param(
        [parameter(Mandatory = $true)]$ProjectName,
        [parameter(Mandatory = $false)]$Premium
    )
    #Publish changed Pbix Files
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like "$($ProjectName)-$($dev_var)" }
    foreach ($pbix_file in $pbix_files) {
      
          Write-Information "Processing  $($pbix_file.FullName) ... "
          Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
          New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"
    }
}
########CI###########
Function CiBuild {
    Param(
        [parameter(Mandatory = $true)]$ProjectName,
        [parameter(Mandatory = $false)]$Premium
    )
    #Publish changed Pbix Files
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like "$($ProjectName)-$($dev_var)" }
    foreach ($pbix_file in $pbix_files) {
      
        $executable = Join-Path $root_path TabularEditor.exe
        $codebase = "$(Join-Path $pbix_file.DirectoryName $pbix_file.BaseName).database.json"
        $targetBim = "$(Join-Path $pbix_file.DirectoryName $pbix_file.BaseName)Model.bim"
        
        Write-Information "codebasecodebasePath  $($codebase) ... "
        Write-Information "targetBim  $($targetBim ) ... "
        Write-Information "pbix_file.BaseName  $($pbix_file.BaseName ) ... "
        Write-Information "pbix_file.DirectoryName  $($pbix_file.DirectoryName ) ... "
        #"$(Join-Path $pbix_file.DirectoryName $pbix_file.BaseName)-Model.bim"

        #cmd.exe  $executable $codebase -B $targetBim

        $params = @(
			"""$codebase"""
			"-B ""$targetBim"""
		)

		Write-Information "$indention $executable $params"
		$p = Start-Process -FilePath $executable -Wait -NoNewWindow -PassThru -ArgumentList $params

		if ($p.ExitCode -ne 0) {
			Write-Error "$indention Failed to extract .bim file from !"
		}
        Test-Path -Path $targetBim -PathType leaf

        #Write-Information "Processing  $($pbix_file.FullName) ... "
        #Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
        #New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"
    }
}
########CD
Function CD-Build {
    Param(
        [parameter(Mandatory = $true)]$ProjectName,
        [parameter(Mandatory = $false)]$Premium
    )
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like "$($ProjectName)-$($test_var)" }
    #Publish Pbix Files
    foreach ($pbix_file in $pbix_files) {
        Write-Host "pbix_file...###################" $pbix_file
        Write-Information "Processing  $($pbix_file.FullName) ... "
        Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
        New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"
        #New-DatasetRefresh -WorkspaceName $workspace.Name -DataSetName $pbix_file.BaseName
    }
}
#---------------------------------------------------------ACTIONS--------------------------------------------------------------------------------
######Environment-Setup
if ($Action -eq "Environment-Setup") {
    if ($triggered_by -eq "Manual" -or $triggered_by -eq "workflow_dispatch") {
        Continue
    }else{
        Write-Host "ENVIRONMENT SETUP Started...####################################################################"
        Environment-Setup -ProjectName $ProjectName -Premium $Premium -UserEmail $UserEmail
    }
}
########CI
if ($Action -eq "CI-Build") {
    if ($triggered_by -eq "Manual" -or $triggered_by -eq "workflow_dispatch") {
        Continue
    }else{
        Write-Information "CI-Started...#####################################################################################"
        CI-Build -ProjectName $ProjectName -Premium $Premium
    }
}
########CI#######
if ($Action -eq "CiBuild") {
    if ($triggered_by -eq "Manual" -or $triggered_by -eq "workflow_dispatch") {
        Continue
    }else{
        Write-Information "CI-Started...#####################################################################################"
        CiBuild -ProjectName $ProjectName -Premium $Premium
    }
}
########CD
if ($Action -eq "CD-Build") {
    if ($triggered_by -eq "Manual" -or $triggered_by -eq "workflow_dispatch") {
        Write-Information "CD-Started...#########################################################################################"
        CD-Build -ProjectName $ProjectName -Premium $Premium
    }
}
########DatasetRefresh
if ($Action -eq "Data-Refresh") {
    Write-Information "DATA_REFRESH-Started...##################################################################################"
        New-DatasetRefresh -WorkspaceName $WorkspaceName -DataSetName $DataSetName
}
########Send Email Notification
Write-Information "Begun FUCNTION!!!!!!:"  $PowerAutomateEndPoint
if ($Action -eq "Notification") {
    Write-Information "Sending_Notification-Started...##################################################################################"
    $email_recipient = $Notify
    if($email_recipient){
        Write-Host "A notification will be send to:" $email_recipient
    }else{
        Write-Host "No email Provided!"
        return
    }
    Write-Information "ENDPOINT:" $env:URL_PowerAutomate_EndPoint
    Write-Information "ENDPOINT2:"  $PowerAutomateEndPoint
    if (!$PowerAutomateEndPoint) {
        Write-Host "No Email endpoint Provided!"
        return
    }
    $environment = $env:CHOICE
    $workspaceName = ""
    if ($environment -like "*Test" -or $environment -eq "Test Workspace") {
        $workspaceName = "$($ProjectName)-$($test_var)"
    }else{
        $workspaceName = "$($ProjectName)"
    }
    $getWorkspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like $workspaceName }

    $workspace_weburl = "https://app.powerbi.com/groups/$($getWorkspace.Id)/list"

    Write-Host "LIIIIIIIIIINK:" $workspace_weburl
 
    InvokePowerAutomate_Email -PowerAutomateEndPoint $PowerAutomateEndPoint -Notify $email_recipient -WorkspaceName $workspaceName -WorkspaceWebUrl $workspace_weburl
}