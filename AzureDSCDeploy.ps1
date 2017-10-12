#region Login

    Add-AzureRmAccount
    $Subscription = 'LastWordInNerd'
    $Sub = Get-AzureRmSubscription -SubscriptionName $Subscription
    Set-AzureRmContext -SubscriptionName $Sub.Name

#endregion

#region GetAutomationAccount

    $AutoResGrp = Get-AzureRmResourceGroup -Name 'mms-eus'
    $AutoAcct = Get-AzureRmAutomationAccount -ResourceGroupName $AutoResGrp.ResourceGroupName

#endregion

#region compress modules

    Set-Location C:\Scripts\Presentations\AzureDSCCompositeTest\
    $Modules = Get-ChildItem -Directory
    
    ForEach ($Mod in $Modules){

        Compress-Archive -Path $Mod.PSPath -DestinationPath ((Get-Location).Path + '\' + $Mod.Name + '.zip') -Force

    }


#endregion

#region Access blob container

    $StorAcct = Get-AzureRmStorageAccount -ResourceGroupName $AutoAcct.ResourceGroupName -Name 'modulestor'

    Add-AzureAccount
    $AzureSubscription = ((Get-AzureSubscription).where({$PSItem.SubscriptionName -eq $Sub.Name})) 
    Select-AzureSubscription -SubscriptionName $AzureSubscription.SubscriptionName -Current
    $StorKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $StorAcct[0].ResourceGroupName -Name $StorAcct[0].StorageAccountName).where({$PSItem.KeyName -eq 'key1'})
    $StorContext = New-AzureStorageContext -StorageAccountName $StorAcct[0].StorageAccountName -StorageAccountKey $StorKey.Value
    $Container = Get-AzureStorageContainer -Name 'modules' -Context $StorContext

#endregion

#region upload zip files

    $ModulesToUpload = Get-ChildItem -Filter "*.zip"

    ForEach ($Mod in $ModulesToUpload){

            $Blob = Set-AzureStorageBlobContent -Context $StorContext -Container $Container.Name -File $Mod.FullName -Force
            
            New-AzureRmAutomationModule -ResourceGroupName $AutoAcct.ResourceGroupName -AutomationAccountName $AutoAcct.AutomationAccountName -Name ($Mod.Name).Replace('.zip','') -ContentLink $Blob.ICloudBlob.Uri.AbsoluteUri

    }

#endregion

#region Import Configuration

    $Config = Import-AzureRmAutomationDscConfiguration -SourcePath (Get-Item C:\Scripts\Presentations\AzureAutomationDSC\TestConfig.ps1).FullName -AutomationAccountName $AutoAcct.AutomationAccountName -ResourceGroupName $AutoAcct.ResourceGroupName -Description DemoConfiguration -Published -Force

#endregion

#region Add Parameters and ConfigData

    $Parameters = @{
        
                'DomainName' = 'lwinerd.local'
                'ResourceGroupName' = $AutoAcct.ResourceGroupName
                'AutomationAccountName' = $AutoAcct.AutomationAccountName
                'AdminName' = 'lwinadmin'
        
    }

    $ConfigData = 
    @{
        AllNodes = 
        @(
            @{
                NodeName = "*"
                PSDscAllowPlainTextPassword = $true
            },


            @{
                NodeName     = "webServer"
                Role         = "WebServer"
            }
            
            @{
                NodeName = "domainController"
                Role = "domaincontroller"
            }

        )
    }

#endregion

#region Compile the config and monitor

    $DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AutoAcct.AutomationAccountName -ConfigurationName $Config.Name -ConfigurationData $ConfigData -Parameters $Parameters -ResourceGroupName $AutoAcct.ResourceGroupName

    Get-AzureRmAutomationDscCompilationJob -Id $DSCComp.Id -ResourceGroupName $AutoAcct.ResourceGroupName -AutomationAccountName $AutoAcct.AutomationAccountName

#endregion

#region Select target VM

    $ArmVmRsg = Get-AzureRmResourceGroup -Name 'ugmichigan'
    $ArmVm = Get-Azurermvm -ResourceGroupName $ArmVmRsg.ResourceGroupName -Name 'azdsctgt02'

#endregion


#region Add PowerShell DSC Extension

    #Latest Extension - https://blogs.msdn.microsoft.com/powershell/2014/11/20/release-history-for-the-azure-dsc-extension/
    #Check for extension
    
        Get-AzureRmVMDscExtension -ResourceGroupName $ArmVmRsg.ResourceGroupName -VMName $ArmVm.Name -Verbose
        
    $DSCLCMConfig = @{
        
            'ConfigurationMode' = 'ApplyAndAutocorrect'
            'RebootNodeIfNeeded' = $true
            'ActionAfterReboot' = 'ContinueConfiguration'
        
        }

        Register-AzureRmAutomationDscNode -AzureVMName $ArmVm.Name -AzureVMResourceGroup $ArmVm.ResourceGroupName -AzureVMLocation $ArmVm.Location -AutomationAccountName $AutoAcct.AutomationAccountName -ResourceGroupName $AutoAcct.ResourceGroupName @DSCLCMConfig
        

#endregion

#region Assign Configuration

    $Configuration = Get-AzureRmAutomationDscNodeConfiguration -AutomationAccountName $AutoAcct.AutomationAccountName -ResourceGroupName $AutoAcct.ResourceGroupName -Name 'cmdpconfig.localhost'

    $TargetNode = Get-AzureRmAutomationDscNode -Name $ArmVm.Name -ResourceGroupName $AutoAcct.ResourceGroupName -AutomationAccountName $AutoAcct.AutomationAccountName
    Set-AzureRmAutomationDscNode -Id $TargetNode.Id -NodeConfigurationName $Configuration.Name -AutomationAccountName $AutoAcct.AutomationAccountName -ResourceGroupName $AutoAcct.ResourceGroupName -Verbose -Force
    
#endregion

#region Get Node Status

    Get-AzureRmAutomationDscNodeReport -NodeId $TargetNode.Id -ResourceGroupName $AutoAcct.ResourceGroupName -AutomationAccountName $AutoAcct.AutomationAccountName -Latest

#endregion

#region Enroll On-Prem

    code 'C:\Windows\System32\DscMetaConfigs\localhost.meta.mof'


#endregion