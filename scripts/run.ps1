[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][String]$Secret,
    [Parameter(Mandatory = $false)][String]$TenantId,
    [Parameter(Mandatory = $false)][String]$ClientID,
    [Parameter(Mandatory = $true)][String]$ProjectName,
    [Parameter(Mandatory = $true)][String]$Premium,
    [Parameter(Mandatory = $true)][String]$Action,
    [Parameter(Mandatory = $false)][String]$WorkspaceName,
    [Parameter(Mandatory = $false)][String]$UserEmail
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

Function Environment-Setup{
    [parameter(Mandatory = $true)]$ProjectName
    [parameter(Mandatory = $true)]$Premium
    
    if($Premium){
        Write-Host "PREMIUM CONFIGURATION CHOSEN" -Color Magenta
    }else{
        Write-Host "NO PREMIUM CONFIGURATION CHOSEN" -Color Magenta
    }
}

Function CI-Build {
    Param(
        [parameter(Mandatory = $true)]$WorkspaceName,
        [parameter(Mandatory = $true)]$UserEmail
    )
    #Get WorkSpace
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like $WorkspaceName }
    #Check if exists
    if ($workspace) {
        Write-Host "Workspace: $WorkspaceName already exists"
    }
    else {
        Write-Host "Trying to create workspace: $WorkspaceName"
        New-PowerBIWorkspace -Name $WorkspaceName
        Write-Host "Workspace: $WorkspaceName created!"
    }

    #Publish changed Pbix Files
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like $WorkspaceName }
    foreach ($pbix_file in $pbix_files) {
        $report = $null
        $dataset = $null
      
          Write-Information "Processing  $($pbix_file.FullName) ... "
      
          Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
          New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"
    }

    #Adding User As Admin
    Write-Host "Adding user to a Workspace"

    $ApiUrl = "groups/" + $workspace.Id + "/users"
    $WorkspaceUsers = (Invoke-PowerBIRestMethod -Url $ApiUrl -Method Get) | ConvertFrom-Json
    $UserObject = $WorkspaceUsers.value | Where-Object { $_.emailAddress -like $UserEmail }
    if($UserObject){
        Write-Output "User Already Exists"
    }else{
        Add-PowerBIWorkspaceUser -Id $workspace.Id -UserEmailAddress $UserEmail -AccessRight Admin
    }
        
    
}
#ACTIONS-------------------------------------------------------------------------------------------------------------------
if ($Action -eq "Environment-Setup") {
    Write-Host "Environment-Setu Started..."  -Color DarkCyan
    Environment-Setup -ProjectName $ProjectName -Premium $Premium
}
if ($Action -eq "CI-Build") {
    Write-Host "CI-Started..."  -Color DarkCyan
    CI-Build -WorkspaceName $WorkspaceName -UserEmail $UserEmail
}