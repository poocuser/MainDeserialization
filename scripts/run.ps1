[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][String]$WorkspaceName,
    [Parameter(Mandatory = $false)][String]$Action,
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


   $tenant_id = "1234b804-8fd3-488c-868a-6a81443bd23d"
   $client_id = "a6b79634-8f18-471e-81e8-cb9b60f87942"
   $client_secret = "pO_7Q~KwPTSYnwzKj_YKdlcFfrZEhvGshbA-J"
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


Function CI-Build {
    Param(
        [parameter(Mandatory = $true)]$WorkspaceName,
        [parameter(Mandatory = $true)]$UserString
    )
    #Get WorkSpace
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like $WorkspaceName }

    if ($workspace) {
        Write-Host "Workspace: $WorkspaceName already exists"
    }
    else {
        Write-Host "Trying to create workspace: $WorkspaceName"

        New-PowerBIWorkspace -Name $WorkspaceName
        
        Write-Host "Workspace: $WorkspaceName created!"
    }
    #Publish changed Pbix
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like $WorkspaceName }
    foreach ($pbix_file in $pbix_files) {
        $report = $null
        $dataset = $null
      
          Write-Information "Processing  $($pbix_file.FullName) ... "
      
          Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
          New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"
    }
    #Adding users
    Write-Host "Adding users to a Workspace"
    $users = $UserString.Split(",")
    foreach ($user in $Users) {
        Add-PowerBIWorkspaceUser -Id $workspace.Id -UserEmailAddress $user -AccessRight Admin
    }
}
#ACTIONS
if ($Action -eq "CI-Build") {
    Write-Host "CI-Started"
    CI-Build -WorkspaceName $WorkspaceName -UserString $UserString
}




#Add-PowerBIWorkspaceUser -Workspace ( Get-PowerBIWorkspace -Name $newWorkspaceName ) -UserEmailAddress poocuser@6ysf6f.onmicrosoft.com -AccessRight Admin