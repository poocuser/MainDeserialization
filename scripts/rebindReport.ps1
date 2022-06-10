[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][String]$Workspace_Id,
    [Parameter(Mandatory = $true)][String]$Report_Id,
    [Parameter(Mandatory = $true)][String]$TargetDataset_Id,
)
# =================================================================================================================================================
# Task execution
# =================================================================================================================================================
# Run parameters, please specify below parameters
$WorkspaceId = $Workspace_Id
$ReportId = $Report_Id
$TargetDatasetId = $TargetDataset_Id

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