
<#
.SYNOPSIS
    This runbook will scale up an ARM VM in response to an Azure alert.

.DESCRIPTION
    This runbook will scale up an ARM VM in response to an Azure alert.
    https://docs.microsoft.com/en-us/azure/automation/automation-create-alert-triggered-runbook
    Input is alert data with information needed to identify which VM to scale up.

    DEPENDENCIES
    - The runbook must be called from an Azure alert via a webhook.
    - Latest version of Az module should be added to the automation account
      https://docs.microsoft.com/en-us/azure/automation/automation-update-azure-modules#update-az-modules

    REQUIRED AUTOMATION ASSETS
    - Managed Identity should be enabled and contributor access to the automation account should be given
      https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview
      https://docs.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal?tabs=current
    - If User-Assigned Managed Identity is enabled, variable named "AUTOMATION_VMALERT_USER_ASSIGNED_IDENTITY_ID" should be added with client id

.PARAMETER WebhookData
    Optional (user should not enter anything, but the webhook service will always pass an object)
    This is the data that is sent in the webhook that is triggered from the alert.

.NOTES
    AUTHOR: Azure Compute Team, Azure Automation Team
    LASTEDIT: 2021-10-28
#>

# Output is a status object (IsSuccessStatusCode, ReasonPhrase, RequestId, StatusCode)
[OutputType("PSAzureOperationResponse")]

param
(
    [parameter (Mandatory=$false)]
    [object] $WebhookData
)

$ErrorActionPreference = "stop"

if ($WebhookData)
{
    # Get the data object from WebhookData
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

    # Get the info needed to identify the VM (depends on the payload schema)
    $schemaId = $WebhookBody.schemaId
    Write-Verbose "schemaId: $schemaId" -Verbose
    if ($schemaId -eq "azureMonitorCommonAlertSchema") {
        # This is the common Metric Alert schema (released March 2019)
        $Essentials = [object] ($WebhookBody.data).essentials
        # Get the first target only as this script doesn''t handle multiple
        $alertTargetIdArray = (($Essentials.alertTargetIds)[0]).Split("/")
        $SubId = ($alertTargetIdArray)[2]
        $ResourceGroupName = ($alertTargetIdArray)[4]
        $ResourceType = ($alertTargetIdArray)[6] + "/" + ($alertTargetIdArray)[7]
        $ResourceName = ($alertTargetIdArray)[-1]
        $status = $Essentials.monitorCondition
    }
    elseif ($schemaId -eq "AzureMonitorMetricAlert") {
        # This is the near-real-time Metric Alert schema
        $AlertContext = [object] ($WebhookBody.data).context
        $SubId = $AlertContext.subscriptionId
        $ResourceGroupName = $AlertContext.resourceGroupName
        $ResourceType = $AlertContext.resourceType
        $ResourceName = $AlertContext.resourceName
        $status = ($WebhookBody.data).status
    }
    elseif ($schemaId -eq "Microsoft.Insights/activityLogs") {
        # This is the Activity Log Alert schema
        $AlertContext = [object] (($WebhookBody.data).context).activityLog
        $SubId = $AlertContext.subscriptionId
        $ResourceGroupName = $AlertContext.resourceGroupName
        $ResourceType = $AlertContext.resourceType
        $ResourceName = (($AlertContext.resourceId).Split("/"))[-1]
        $status = ($WebhookBody.data).status
    }
    elseif ($schemaId -eq $null) {
        # This is the original Metric Alert schema
        $AlertContext = [object] $WebhookBody.context
        $SubId = $AlertContext.subscriptionId
        $ResourceGroupName = $AlertContext.resourceGroupName
        $ResourceType = $AlertContext.resourceType
        $ResourceName = $AlertContext.resourceName
        $status = $WebhookBody.status
    }
    else {
        # Schema not supported
        Write-Error "The alert data schema - $schemaId - is not supported."
    }

    Write-Verbose "status: $status" -Verbose
    if (($status -eq "Activated") -or ($status -eq "Fired"))
    {
        Write-Verbose "resourceType: $ResourceType" -Verbose
        Write-Verbose "resourceName: $ResourceName" -Verbose
        Write-Verbose "resourceGroupName: $ResourceGroupName" -Verbose
        Write-Verbose "subscriptionId: $SubId" -Verbose

        # Determine code path depending on the resourceType
        if ($ResourceType -eq "Microsoft.Compute/virtualMachines")
        {
            # This is an ARM VM
            Write-Verbose "This is an ARM VM." -Verbose 

            # Set constants
            $noResize = "noresize"

            $scaleUp = @{
                # A-Series
                "Basic_A0"         = "Basic_A1"
                "Basic_A1"         = "Basic_A2"
                "Basic_A2"         = "Basic_A3"
                "Basic_A3"         = "Basic_A4"
                "Basic_A4"         = $noResize
                "Standard_A0"      = "Standard_A1"
                "Standard_A1"      = "Standard_A2"
                "Standard_A2"      = "Standard_A3"
                "Standard_A3"      = "Standard_A4"
                "Standard_A4"      = $noResize
                "Standard_A5"      = "Standard_A6"
                "Standard_A6"      = "Standard_A7"
                "Standard_A7"      = $noResize
                "Standard_A8"      = "Standard_A9"
                "Standard_A9"      = $noResize
                "Standard_A10"     = "Standard_A11"
                "Standard_A11"     = $noResize
                "Standard_A1_v2"   = "Standard_A2_v2"
                "Standard_A2_v2"   = "Standard_A4_v2"
                "Standard_A4_v2"   = "Standard_A8_v2"
                "Standard_A8_v2"   = $noResize
                "Standard_A2m_v2"  = "Standard_A4m_v2"
                "Standard_A4m_v2"  = "Standard_A8m_v2"
                "Standard_A8m_v2"  = $noResize

                # B-Series
                "Standard_B1s"     = "Standard_B2s"
                "Standard_B2s"     = $noResize
                "Standard_B1ms"    = "Standard_B2ms"
                "Standard_B2ms"    = "Standard_B4ms"
                "Standard_B4ms"    = "Standard_B8ms"
                "Standard_B8ms"    = $noResize

                # D-Series
                "Standard_D1"      = "Standard_D2"
                "Standard_D2"      = "Standard_D3"
                "Standard_D3"      = "Standard_D4"
                "Standard_D4"      = $noResize
                "Standard_D11"     = "Standard_D12"
                "Standard_D12"     = "Standard_D13"
                "Standard_D13"     = "Standard_D14"
                "Standard_D14"     = $noResize
                "Standard_DS1"     = "Standard_DS2"
                "Standard_DS2"     = "Standard_DS3"
                "Standard_DS3"     = "Standard_DS4"
                "Standard_DS4"     = $noResize
                "Standard_DS11"    = "Standard_DS12"
                "Standard_DS12"    = "Standard_DS13"
                "Standard_DS13"    = "Standard_DS14"
                "Standard_DS14"    = $noResize
                "Standard_D1_v2"   = "Standard_D2_v2"
                "Standard_D2_v2"   = "Standard_D3_v2"
                "Standard_D3_v2"   = "Standard_D4_v2"
                "Standard_D4_v2"   = "Standard_D5_v2"
                "Standard_D5_v2"   = $noResize
                "Standard_D11_v2"  = "Standard_D12_v2"
                "Standard_D12_v2"  = "Standard_D13_v2"
                "Standard_D13_v2"  = "Standard_D14_v2"
                "Standard_D14_v2"  = $noResize
                "Standard_DS1_v2"  = "Standard_DS2_v2"
                "Standard_DS2_v2"  = "Standard_DS3_v2"
                "Standard_DS3_v2"  = "Standard_DS4_v2"
                "Standard_DS4_v2"  = "Standard_DS5_v2"
                "Standard_DS5_v2"  = $noResize
                "Standard_DS11_v2" = "Standard_DS12_v2"
                "Standard_DS12_v2" = "Standard_DS13_v2"
                "Standard_DS13_v2" = "Standard_DS14_v2"
                "Standard_DS14_v2" = $noResize
                "Standard_D2_v3"   = "Standard_D4_v3"
                "Standard_D4_v3"   = "Standard_D8_v3"
                "Standard_D8_v3"   = "Standard_D16_v3"
                "Standard_D16_v3"  = "Standard_D32_v3"
                "Standard_D32_v3"  = "Standard_D64_v3"
                "Standard_D64_v3"  = $noResize
                "Standard_D2s_v3"  = "Standard_D4s_v3"
                "Standard_D4s_v3"  = "Standard_D8s_v3"
                "Standard_D8s_v3"  = "Standard_D16s_v3"
                "Standard_D16s_v3" = "Standard_D32s_v3"
                "Standard_D32s_v3" = "Standard_D64s_v3"
                "Standard_D64s_v3" = $noResize
                "Standard_DC2s"    = "Standard_DC4s"
                "Standard_DC4s"    = $noResize

                # E-Series
                "Standard_E2_v3"   = "Standard_E4_v3"
                "Standard_E4_v3"   = "Standard_E8_v3"
                "Standard_E8_v3"   = "Standard_E16_v3"
                "Standard_E16_v3"  = "Standard_E20_v3"
                "Standard_E20_v3"  = "Standard_E32_v3"
                "Standard_E32_v3"  = "Standard_E64_v3"
                "Standard_E64_v3"  = $noResize
                "Standard_E2s_v3"  = "Standard_E4s_v3"
                "Standard_E4s_v3"  = "Standard_E8s_v3"
                "Standard_E8s_v3"  = "Standard_E16s_v3"
                "Standard_E16s_v3" = "Standard_E20s_v3"
                "Standard_E20s_v3" = "Standard_E32s_v3"
                "Standard_E32s_v3" = "Standard_E64s_v3"
                "Standard_E64s_v3" = $noResize

                # F-Series
                "Standard_F1"      = "Standard_F2"
                "Standard_F2"      = "Standard_F4"
                "Standard_F4"      = "Standard_F8"
                "Standard_F8"      = "Standard_F16"
                "Standard_F16"     = $noResize
                "Standard_F1s"     = "Standard_F2s"
                "Standard_F2s"     = "Standard_F4s"
                "Standard_F4s"     = "Standard_F8s"
                "Standard_F8s"     = "Standard_F16s"
                "Standard_F16s"    = $noResize
                "Standard_F2s_v2"  = "Standard_F4s_v2"
                "Standard_F4s_v2"  = "Standard_F8s_v2"
                "Standard_F8s_v2"  = "Standard_F16s_v2"
                "Standard_F16s_v2" = "Standard_F32s_v2"
                "Standard_F32s_v2" = "Standard_F64s_v2"
                "Standard_F64s_v2" = "Standard_F72s_v2"
                "Standard_F72s_v2" = $noResize

                # G-Series
                "Standard_G1"      = "Standard_G2"
                "Standard_G2"      = "Standard_G3"
                "Standard_G3"      = "Standard_G4"
                "Standard_G4"      = "Standard_G5"
                "Standard_G5"      = $noResize
                "Standard_GS1"     = "Standard_GS2"
                "Standard_GS2"     = "Standard_GS3"
                "Standard_GS3"     = "Standard_GS4"
                "Standard_GS4"     = "Standard_GS5"
                "Standard_GS5"     = $noResize

                # H-Series
                "Standard_H8"      = "Standard_H16"
                "Standard_H16"     = $noResize
                "Standard_H8m"     = "Standard_H16m"
                "Standard_H16m"    = $noResize

                # L-Series
                "Standard_L4s"     = "Standard_L8s"
                "Standard_L8s"     = "Standard_L16s"
                "Standard_L16s"    = "Standard_L32s"
                "Standard_L32s"    = $noResize
                "Standard_L8s_v2"  = "Standard_L16s_v2"
                "Standard_L16s_v2" = "Standard_L32s_v2"
                "Standard_L32s_v2" = "Standard_L64s_v2"
                "Standard_L64s_v2" = "Standard_L80s_v2"
                "Standard_L80s_v2" = $noResize

                # M-Series
                "Standard_M8ms"    = "Standard_M16ms"
                "Standard_M16ms"   = "Standard_M32ms"
                "Standard_M32ms"   = "Standard_M64ms"
                "Standard_M64ms"   = "Standard_M128ms"
                "Standard_M128ms"  = $noResize
                "Standard_M32ls"   = "Standard_M64ls"
                "Standard_M64ls"   = $noResize
                "Standard_M64s"    = "Standard_M128s"
                "Standard_M128s"   = $noResize
                "Standard_M64"     = "Standard_M128"
                "Standard_M128"    = $noResize
                "Standard_M64m"    = "Standard_M128m"
                "Standard_M128m"   = $noResize

                # N-Series
                "Standard_NC6"     = "Standard_NC12"
                "Standard_NC12"    = "Standard_NC24"
                "Standard_NC24"    = $noResize
                "Standard_NC6s_v2" = "Standard_NC12s_v2"
                "Standard_NC12s_v2"= "Standard_NC24s_v2"
                "Standard_NC24s_v2"= $noResize
                "Standard_NC6s_v3" = "Standard_NC12s_v3"
                "Standard_NC12s_v3"= "Standard_NC24s_v3"
                "Standard_NC24s_v3"= $noResize
                "Standard_ND6"     = "Standard_ND12"
                "Standard_ND12"    = "Standard_ND24"
                "Standard_ND24"    = $noResize
                "Standard_NV6"     = "Standard_NV12"
                "Standard_NV12"    = "Standard_NV24"
                "Standard_NV24"    = $noResize
                "Standard_NV6s_v2" = "Standard_NV12s_v2"
                "Standard_NV12s_v2"= "Standard_NV24s_v2"
                "Standard_NV24s_v2"= $noResize
            }

            #Authenticate to Azure with MSI and set subscription
            Write-Verbose "Authenticating to Azure with Managed Identity" -Verbose
            # Ensures you do not inherit an AzContext in your runbook
            Disable-AzContextAutosave -Scope Process

            $ClientId = Get-AutomationVariable -Name "AUTOMATION_VMALERT_USER_ASSIGNED_IDENTITY_ID" -ErrorAction SilentlyContinue
            if($ClientId)
            {
                # Connect to Azure with user-assigned managed identity
                $AzureContext = (Connect-AzAccount -Identity -AccountId $ClientId).context
            }
            else
            {
                # Connect to Azure with system-assigned managed identity
                $AzureContext = (Connect-AzAccount -Identity).context
            }
            $AzureContext = Set-AzContext -Subscription $SubId -DefaultProfile $AzureContext
            Write-Verbose "Subscription to work against: $SubId" -Verbose
        
            # Get the VM
            Write-Verbose "Get the VM: $ResourceName" -Verbose
            $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -VMName $ResourceName -DefaultProfile $AzureContext -ErrorAction Stop
            $currentVMSize = $vm.HardwareProfile.vmSize
            Write-Verbose "Current VM size: $currentVMSize"-Verbose

            $newVMSize = ""
            $newVMSize = $scaleUp[$currentVMSize]

            if($newVMSize -eq $noResize)
            {
                # Write the status to output
                Write-Verbose "The current VM size can''t be scaled up. You''ll need to recreate the specified Virtual Machine with your requested size." -Verbose
            }
            else
            {
                Write-Verbose "Update the VM size to: $newVMSize" -Verbose
                $vm.HardwareProfile.VmSize = $newVMSize

                # This operation provides the runbook output, and is of type PSAzureOperationResponse
                Update-AzVM -VM $vm -ResourceGroupName $ResourceGroupName -DefaultProfile $AzureContext

                # Log the status
                $updatedVm = Get-AzVM -ResourceGroupName $ResourceGroupName -VMName $ResourceName -DefaultProfile $AzureContext
                Write-Verbose ("The VM size has been scaled up from $currentVMSize to " + $updatedVm.HardwareProfile.vmSize) -Verbose
            }
        }
        else {
            # ResourceType not supported
            Write-Error "$ResourceType is not a supported resource type for this runbook."
        }
    }
    else {
        # The alert status was not ''Activated'' or ''Fired'' so no action taken
        Write-Verbose ("No action taken. Alert status: " + $status) -Verbose
    }
}
else {
    # Error
    Write-Error "This runbook is meant to be started from an Azure alert webhook only."
}