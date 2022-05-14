[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][String]$Username,
    [Parameter(Mandatory = $false)][String]$Username,
    [Parameter(Mandatory = $false)][String]$Username,
    [Parameter(Mandatory = $false)][String]$Username,

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

#$workspace_id = $env:PBI_PREMIUM_WORKSPACE_ID

   $tenant_id = "1234b804-8fd3-488c-868a-6a81443bd23d"
   $client_id = "a6b79634-8f18-471e-81e8-cb9b60f87942"
   $client_secret = "pO_7Q~KwPTSYnwzKj_YKdlcFfrZEhvGshbA-J"
   $login_info = "User ID=app:$client_id@$tenant_id;Password=$client_secret"

 [securestring]$sec_client_secret = ConvertTo-SecureString $client_secret -AsPlainText -Force
 [pscredential]$credential = New-Object System.Management.Automation.PSCredential ($client_id, $sec_client_secret)

 Connect-PowerBIServiceAccount -Credential $credential -ServicePrincipal -TenantId $tenant_id

 $newWorkspaceName = "AmineTest2"

 New-PowerBIWorkspace -Name $newWorkspaceName


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

foreach ($pbix_file in $pbix_files) {
  $report = $null
  $dataset = $null

    Write-Information "Processing  $($pbix_file.FullName) ... "

    $temp_name = "$($pbix_file.BaseName)-$(Get-Date -Format 'yyyyMMddTHHmmss')"
    Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)/$temp_name ... "
    #$report = New-PowerBIReport -Path $pbix_file.FullName -Name $temp_name -WorkspaceId $workspace.Id
    New-PowerBIReport -Path $pbix_file.FullName -Name 'Report' -Workspace ( Get-PowerBIWorkspace -Name $newWorkspaceName )
}

Add-PowerBIWorkspaceUser -Workspace ( Get-PowerBIWorkspace -Name $newWorkspaceName ) -UserEmailAddress poocuser@6ysf6f.onmicrosoft.com -AccessRight Admin