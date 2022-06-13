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
$login_info = "User ID=app:$client_id@$tenant_id;Password=$client_secret"

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
########################################-------------DEPLOY-----------######################################################
# ========================================================================================================================
# Helper function used for Deploying reports across environments
# ========================================================================================================================
Function DeployReports {
    Param(
        [parameter(Mandatory = $true)]$SourceWorkspaceName,
        [parameter(Mandatory = $true)]$TargetWorkspaceName
    )
    $source_workspace_ID = ""
while (!$source_workspace_ID) {
    $source_workspace_name = if (-not($SourceWorkspaceName)) {
        Read-Host -Prompt "Enter the name of the workspace you'd like to copy from" 
    }
    else {
        $SourceWorkspaceName 
    }

    if ($source_workspace_name -eq "My Workspace") {
        $source_workspace_ID = "me"
        break
    }

    $workspace = Get-PowerBIWorkspace -Name $source_workspace_name -ErrorAction SilentlyContinue

    if (!$workspace) {
        Write-Warning "Could not get a workspace with that name. Please try again, making sure to type the exact name of the workspace"  
    }
    else {
        $source_workspace_ID = $workspace.id
    }
}

# STEP 2.2: Get the target workspace
$target_workspace_ID = "" 
while (!$target_workspace_ID) {
    $target_workspace_name = if (-not($TargetWorkspaceName)) {
        Read-Host -Prompt "Enter the name of the workspace you'd like to copy to" 
    }
    else {
        $TargetWorkspaceName 
    }
	
    $target_workspace = Get-PowerBIWorkspace -Name $target_workspace_name -ErrorAction SilentlyContinue

    if (!$target_workspace -and $CreateTargetWorkspaceIfNotExists -eq $true) {
        $target_workspace = New-PowerBIWorkspace -Name $target_workspace_name -ErrorAction SilentlyContinue
    }

    if (!$target_workspace -or $target_workspace.isReadOnly -eq "True") {
        Write-Error "Invalid choice: you must have edit access to the workspace."
        break
    }
    else {
        $target_workspace_ID = $target_workspace.id
    }

    if (!$target_workspace_ID) {
        Write-Warning "Could not get a workspace with that name. Please try again with a different name."  
    } 
}

# ==================================================================
# PART 3: Copying reports and datasets via Export/Import of 
#         reports built on PBIXes (this step creates the datasets)
# ==================================================================
$report_ID_mapping = @{ }      # mapping of old report ID to new report ID
$dataset_ID_mapping = @{ }     # mapping of old model ID to new model ID

# STEP 3.1: Create a temporary folder to export the PBIX files.
$temp_path_root = "$PSScriptRoot\pbi-copy-workspace-temp-storage"
$temp_dir = New-Item -Path $temp_path_root -ItemType Directory -ErrorAction SilentlyContinue

# STEP 3.2: Get the reports from the source workspace
$reports = if ($source_workspace_ID -eq "me") { Get-PowerBIReport } else { Get-PowerBIReport -WorkspaceId $source_workspace_ID }

# STEP 3.3: Export the PBIX files from the source and then import them into the target workspace
Foreach ($report in $reports) {
   
    $report_id = [guid]$report.id
    $dataset_id = [guid]$report.datasetId
    $report_name = $report.name
    $temp_path = "$temp_path_root\$report_name.pbix"

    # Only export if this dataset if it hasn't already been exported already
    if ($dataset_ID_mapping -and $dataset_ID_mapping[$dataset_id]) {
        continue
    }

    Write-Host "== Exporting $report_name with id: $report_id to $temp_path"
    try {
        if ($source_workspace_ID -eq "me") {
            Export-PowerBIReport -Id $report_id -OutFile "$temp_path" -ErrorAction Stop
        }
        else {
            Export-PowerBIReport -Id $report_id -WorkspaceId $source_workspace_ID -OutFile "$temp_path" -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "= This report and dataset cannot be copied, skipping. This is expected for most workspaces."
        continue
    }
     
    try {
        Write-Host "== Importing $report_name to target workspace"

        $new_report = New-PowerBIReport -WorkspaceId $target_workspace_ID -Path $temp_path -Name $report_name -ConflictAction "CreateOrOverwrite"
                
        # Get the report again because the dataset id is not immediately available with New-PowerBIReport
        $new_report = Get-PowerBIReport -WorkspaceId $target_workspace_ID -Id $new_report.id
        if ($new_report) {
            # keep track of the report and dataset IDs
            $report_id_mapping[$report_id] = $new_report.id
            $dataset_id_mapping[$dataset_id] = $new_report.datasetId
        }
    }
    catch [Exception] {
        Write-Error "== Error: failed to import PBIX"

        $exception = Resolve-PowerBIError -Last
        Write-Error "Error Description:" $exception.Message
        continue
    }
}

# STEP 3.4: Copy any remaining reports that have not been copied yet. 
$failure_log = @()  

Foreach ($report in $reports) {
    $report_name = $report.name
    $report_datasetId = [guid]$report.datasetId

    $target_dataset_Id = $dataset_id_mapping[$report_datasetId]
    if ($target_dataset_Id -and !$report_ID_mapping[$report.id]) {
        Write-Host "== Copying report $report_name"
        $report_copy = if ($source_workspace_ID -eq "me") { 
            Copy-PowerBIReport -Report $report -TargetWorkspaceId $target_workspace_ID -TargetDatasetId $target_dataset_Id 
        }
        else {
            Copy-PowerBIReport -Report $report -WorkspaceId $source_workspace_ID -TargetWorkspaceId $target_workspace_ID -TargetDatasetId $target_dataset_Id 
        }

        $report_ID_mapping[$report.id] = $report_copy.id
    }
    else {
        $failure_log += $report
    }
}

# ==================================================================
# PART 4: Copy dashboards and tiles
# ==================================================================

# STEP 4.1 Get all dashboards from the source workspace
# If source is My Workspace, filter out dashboards that I don't own - e.g. those shared with me
$dashboards = "" 
if ($source_workspace_ID -eq "me") {
    $dashboards = Get-PowerBIDashboard
    $dashboards_temp = @()
    Foreach ($dashboard in $dashboards) {
        if ($dashboard.isReadOnly -ne "True") {
            $dashboards_temp += $dashboard
        }
    }
    $dashboards = $dashboards_temp
}
else {
    $dashboards = Get-PowerBIDashboard -WorkspaceId $source_workspace_ID
}

# STEP 4.2 Copy the dashboards and their tiles to the target workspace
Foreach ($dashboard in $dashboards) {
    $dashboard_id = $dashboard.id
    $dashboard_name = $dashboard.Name

    Write-Host "== Cloning dashboard: $dashboard_name"

    # create new dashboard in the target workspace
    $dashboard_copy = New-PowerBIDashboard -Name $dashboard_name -WorkspaceId $target_workspace_ID
    $target_dashboard_id = $dashboard_copy.id

    Write-Host " = Copying the tiles..." 
    $tiles = if ($source_workspace_ID -eq "me") { 
        Get-PowerBITile -DashboardId $dashboard_id 
    }
    else {
        Get-PowerBITile -WorkspaceId $source_workspace_ID -DashboardId $dashboard_id 
    }

    Foreach ($tile in $tiles) {
        try {
            $tile_id = $tile.id
            if ($tile.reportId) {
                $tile_report_Id = [GUID]($tile.reportId)
            }
            else {
                $tile_report_Id = $null
            }

            if (!$tile.datasetId) {
                Write-Warning "= Skipping tile $tile_id, no dataset id..."
                continue
            }
            else {
                $tile_dataset_Id = [GUID]($tile.datasetId)
            }

            if ($tile_report_id) { $tile_target_report_id = $report_id_mapping[$tile_report_id] }
            if ($tile_dataset_id) { $tile_target_dataset_id = $dataset_id_mapping[$tile_dataset_id] }

            # clone the tile only if a) it is not built on a dataset or b) if it is built on a report and/or dataset that we've moved
            if (!$tile_report_id -Or $dataset_id_mapping[$tile_dataset_id]) {
                $tile_copy = if ($source_workspace_ID -eq "me") { 
                    Copy-PowerBITile -DashboardId $dashboard_id -TileId $tile_id -TargetDashboardId $target_dashboard_id -TargetWorkspaceId $target_workspace_ID -TargetReportId $tile_target_report_id -TargetDatasetId $tile_target_dataset_id 
                }
                else {
                    Copy-PowerBITile -WorkspaceId $source_workspace_ID -DashboardId $dashboard_id -TileId $tile_id -TargetDashboardId $target_dashboard_id -TargetWorkspaceId $target_workspace_ID -TargetReportId $tile_target_report_id -TargetDatasetId $tile_target_dataset_id 
                }
                
                Write-Host "." -NoNewLine
            }
            else {
                $failure_log += $tile
            } 
           
        }
        catch [Exception] {
            Write-Error "Error: skipping tile..."
            Write-Error $_.Exception
        }
    }
    Write-Host "Done!"
}

# ==================================================================
# PART 5: Cleanup
# ==================================================================
Write-Host "Cleaning up temporary files"
Remove-Item -path $temp_path_root -Recurse
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
    $workspace = Get-PowerBIWorkspace | Where-Object { $_.Name -like "Embedded" }
    foreach ($pbix_file in $pbix_files) {
      
        $executable = Join-Path $root_path TabularEditor.exe
        $codebase = "$(Join-Path $pbix_file.DirectoryName $pbix_file.BaseName).database.json"
        $targetBim = "$(Join-Path $pbix_file.DirectoryName $pbix_file.BaseName)Model.bim"
        
        Write-Information "codebasecodebasePath  $($codebase) ... "
        Write-Information "targetBim  $($targetBim ) ... "
        Write-Information "pbix_file.BaseName  $($pbix_file.BaseName ) ... "
        Write-Information "pbix_file.DirectoryName  $($pbix_file.DirectoryName ) ... "

        #Build file#
        $buildParams = @(
			"""$codebase"""
			"-B ""$targetBim"""
		)
		Write-Information "$indention $executable $params"
		$p = Start-Process -FilePath $executable -Wait -NoNewWindow -PassThru -ArgumentList $buildParams

		if ($p.ExitCode -ne 0) {
			Write-Error "$indention Failed to build .bim file  $codebase!"
		}
        Test-Path -Path $targetBim -PathType leaf

        #Release file#
        $connection_string = "powerbi://api.powerbi.com/v1.0/myorg/$($workspace.Name);"
        $releaseParams = @(
			"""$targetBim"""
            "-D ""Data Source=$connection_string;$login_info"""
            """$($pbix_file.BaseName)-Release"""
            "-O -C -P -R -M -E -V"
		)
        $p2 = Start-Process -FilePath $executable -Wait -NoNewWindow -PassThru -ArgumentList $releaseParams
        if ($p2.ExitCode -ne 0) {
			Write-Error "$indention Failed to deploy .bim file !"
		}

        #Publish the report
        Write-Information "Processing  $($pbix_file.FullName) ... "
        Write-Information "$indention Uploading $($pbix_file.FullName.Replace($root_path, '')) to $($workspace.Name)... "
        $report = New-PowerBIReport -Path $pbix_file.FullName -Name $pbix_file.BaseName -WorkspaceId $workspace.Id -ConflictAction "CreateOrOverwrite"

        #Get release dataset id
        $dataset = Get-PowerBIDataset -WorkspaceId $workspace.Id | Where-Object { $_.Name -eq "$($pbix_file.BaseName)-Release" }

        #Bind to the merged dataset##
        #$ScriptToRun= $PSScriptRoot + "\rebindReport.ps1"
        #.$ScriptToRun -Workspace_Id $Workspace_Id -Report_Id $Report_Id -TargetDataset_Id $TargetDataset_Id
        #$root_path/scripts/rebindReport.ps1 -Workspace_Id $workspace.Id -Report_Id $report.Id -TargetDataset_Id $dataset.Id
        $WorkspaceId = $workspace.Id 
        $ReportId = $report.Id
        $TargetDatasetId = $dataset.Id
        # Base variables
        $BasePowerBIRestApi = "https://api.powerbi.com/v1.0/myorg/"
# Body to push in the Power BI API call
$body = 
@"
    {
	    datasetId: "$TargetDatasetId"
    }
"@ 

        # Rebind report task
        Write-Host -ForegroundColor White "Rebind report to specified dataset..."
        Try {
            $RebindApiCall = $BasePowerBIRestApi + "groups/" + $WorkspaceId + "/reports/" + $ReportId + "/Rebind"
            Invoke-PowerBIRestMethod -Method POST -Url $RebindApiCall -Body $body -ErrorAction Stop
            # Write message if succeeded
            Write-Host "Report" $ReportId "successfully binded to dataset" $TargetDatasetId -ForegroundColor Green
        }
        Catch{
            # Write message if error
            Write-Host "Unable to rebind report. An error occured" -ForegroundColor Red
        }

        #Remove temp dataset
        $tempDataset = Get-PowerBIDataset -WorkspaceId $workspace.Id | Where-Object { $_.Name -eq "$($pbix_file.BaseName)" }
        if ($tempDataset -ne $null) {
            Write-Information "$indention Removing temporary PowerBI dataset ..."
            Invoke-PowerBIRestMethod -Url "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.Id)/datasets/$($tempDataset.Id)" -Method Delete
        }
    }
        $premiumWorkspace = 'Embedded'
        $ScriptToRun= $PSScriptRoot + "\deploy.ps1"
        #.$ScriptToRun -SourceWorkspaceName $premiumWorkspace -TargetWorkspaceName "$env:PROJECT_NAME-$($dev_var)"

        $scriptParams = @(
            "-SourceWorkspaceName ""Embedded"""
            "-TargetWorkspaceName ""$($env:PROJECT_NAME)-DEV"""
		)
        #some processing
        $ScriptPath = Split-Path $MyInvocation.InvocationName
        $args = @()
        $args += ("-SourceWorkspaceName", "Embedded")
        $args += ("-TargetWorkspaceName", "$env:PROJECT_NAME-$($dev_var)")
        $cmd = "$ScriptPath\deploy.ps1"

        #Invoke-Expression "$ScriptToRun $scriptParams"

        #${{ github.action_path }}/scripts/deploy.ps1 -SourceWorkspaceName "$env:PROJECT_NAME-$($test_var)" -TargetWorkspaceName $env:PROJECT_NAME -Secret $env:PBI_CLIENT_SECRET -TenantId $env:PBI_TENANT_ID -ClientID $env:PBI_CLIENT_ID -Premium $env:PREMIUM

        DeployReports -SourceWorkspaceName $premiumWorkspace -TargetWorkspaceName "$env:PROJECT_NAME-$($dev_var)"
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
