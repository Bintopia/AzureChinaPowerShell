#Created By MSFT leizhang (leizha@microsoft.com) on Feb 18th, 2020

#refer to https://docs.microsoft.com/en-us/powershell/azure/using-psjobs?view=azps-3.5.0

#Read CSV file
#This CSV file MUST HAVE following Column
#SubscriptionId	VMName	ComputerName	Location	VMSize	OS	Publisher	Offer	SKUs	Version	VMUsername	VMPassword	VMRG	DiagStorageAccountName	VirtualNetworkName	VNetRG	SubnetName	OSDiskSKU	OSDiskSizeInGB	DataDiskSKU	DataDiskSizeInGB	VMAvailabilitySetName

#Please create one Azure resouce Group (including Vitual Network and one subnet) before running this powershell script
#This powershell script will create VM in one resource group and seperate for Virtual network resource group

#You can also create storage account and availability set in another resource group to reduce time

#Please modify CSV path first
$csvpath = "C:\importvm.csv"


#Start to Process CSV File
$p = Import-Csv -Path $csvpath

#Login to Azure China
Add-AzAccount -Environment AzureChinaCloud

#For Analysis
$startVMTime = Get-Date
$startTotalTime = $startVMTime

$jobs = @()
foreach ($rows in $p)
{
        try
        {
            $SubscriptionId = $rows.SubscriptionId.Trim()
            $vmName = $rows.VMName.Trim()
            $computerName = $rows.ComputerName.Trim()
		    $location = $rows.Location.Trim()
		    $vmSize = $rows.VMSize.Trim()
		    $os = $rows.OS.Trim()

		    $publisher = $rows.Publisher.Trim()
		    $offer = $rows.Offer.Trim()
		    $skus = $rows.SKUs.Trim()
		    $version = $rows.Version.Trim()
		    $VMUserName = $rows.VMUsername.Trim()
		    $VMPassword = $rows.VMPassword.Trim()
		
		    $vmRG = $rows.VMRG.Trim()
		    $diagStorageAccountName = $rows.DiagStorageAccountName.Trim()
		    $vNetName = $rows.VirtualNetworkName.Trim()
		    $vNetRG = $rows.VNetRG.Trim()
		    $subnetName = $rows.SubnetName.Trim()
			
		    $osDiskSKU = $rows.OSDiskSKU.Trim()
		    $osDiskSizeInGB = $rows.OSDiskSizeInGB.Trim()
		    $dataDiskSKU = $rows.DataDiskSKU.Trim()
		    $dataDiskSizeInGB = $rows.DataDiskSizeInGB.Trim()
		    $vmAvailabilitySetName = $rows.VMAvailabilitySetName.Trim()
            
            #select the subscription Id
            Select-AzSubscription -SubscriptionId $SubscriptionId

		    #VM ResourceGroup
		    $rg = Get-AzResourceGroup -Name $vmRG -Location $location
            
            #Check if VM Resource Group is exist
            if($rg -eq $null)
            {
               New-AzResourceGroup -Name $vmRG -Location $location
               $rg = Get-AzResourceGroup -Name $vmRG -Location $location
            }
		   
		    #Virtual Network ResourceGroup
		    $vnet = Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $vNetRG
		
		    #AvailabilitySet
		    $as = Get-AzAvailabilitySet -ResourceGroupName $rg.ResourceGroupName -Name $vmAvailabilitySetName

            #Check if Availability Set is exist
            if($as -eq $null)
            {
                New-AzAvailabilitySet -ResourceGroupName $rg.ResourceGroupName -Name $vmAvailabilitySetName -Location $location -SKU Aligned -PlatformFaultDomainCount 2
                $as = Get-AzAvailabilitySet -ResourceGroupName $rg.ResourceGroupName -Name $vmAvailabilitySetName
            }          
		    
            #Check if VM Diag Storage account is exist
            $vmdiagStorage= Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -Name $diagStorageAccountName
            if($vmdiagStorage -eq $null)
            { 
                New-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -Name $diagStorageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2 -AccessTier Hot
                $vmdiagStorage= Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -Name $diagStorageAccountName
            }

		    #Create NIC
            $nicname = $vmName + "-nic01"

            #Get subnet by name
            $subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet 

		    $nic1 = New-AzNetworkInterface -Name $nicname -ResourceGroupName $rg.ResourceGroupName -Location $location -SubnetId $subnet.Id
		    $nic = get-Aznetworkinterface -name $nicname -resourcegroupname $rg.resourcegroupname
		    $nic.IpConfigurations[0].privateipallocationmethod = "static"
		    $nic1 = Set-AzNetworkInterface -NetworkInterface $nic
		    $nic1 = Get-Aznetworkinterface -name $nicname -resourcegroupname $rg.resourcegroupname
		
		    #Get VM Image
		    #$vmimage = Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $skus -Version $version
		    $vmimages = Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $skus | Sort-Object Version -Descending
		    $vmimage = $vmimages[0]
            
		    #Create Azure RM VM
		    $vm = New-AzVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $as.Id
		    $vm = Set-AzVMBootDiagnostic -VM $vm -ResourceGroupName $rg.ResourceGroupName -StorageAccountName $diagStorageAccountName -Enable
		
            #Username and Password
            $securePassword = ConvertTo-SecureString -String $VMPassword -AsPlainText -Force
		    $cred = New-Object System.Management.Automation.PSCredential($VMUserName, $securePassword)
		
		    if($os.ToLower() -eq 'linux')
            {
			    $vm = Set-AzVMOperatingSystem -Linux -VM $vm -Credential $cred -ComputerName $computerName

                #minimal Disk size for Linux is 30GB
                $osDiskSizeInGB = [INT]$osDiskSizeInGB
                if($osDiskSizeInGB -lt 30)
                {
                    $osDiskSizeInGB = 30
                }
		    }
		    elseif($os.ToLower() -eq "windows")
		    {
                #computer name max length is 15
                if($computerName.Length > 15)
                {
                    $computerName = $computerName.Substring(0,15)
                }
			    $vm = Set-AzVMOperatingSystem -Windows -VM $vm -Credential $cred -ComputerName $computerName

                #minimal Disk size for Linux is 127GB
                $osDiskSizeInGB = [INT]$osDiskSizeInGB
                if($osDiskSizeInGB -lt 127)
                {
                    $osDiskSizeInGB = 127
                }
		    }
            else
            {
                Throw "Found error in setting OS version."
            }
       	    $vm = Set-AzVMSourceImage -VM $vm -PublisherName $vmimage.PublisherName -Offer $vmimage.Offer -Skus $vmimage.Skus -Version $vmimage.Version
		
		    #OS Disk
		    $vm = Set-AzVMOSDisk -StorageAccountType $osDiskSKU -DiskSizeInGB $osDiskSizeInGB -VM $vm -CreateOption FromImage
		    $vm = Add-AzVMNetworkInterface -VM $vm -id $nic1.Id
		    
		    #$jobs += New-AzVM -ResourceGroupName $rg.resourcegroupname -Location $location -VM $vm -AsJob
		    New-AzVM -ResourceGroupName $rg.resourcegroupname -Location $location -VM $vm -AsJob

		
            write-host "Start creating "$vmName
        }
        catch [Exception] 
        {
              write-host $_.Exception.Message;
        }
        Finally
        {

        }       
}

#Thread sleep 10 seconds, do not need all the VM provision complete
Start-Sleep -Seconds 10
#$jobs | Wait-Job | Remove-Job -Force



$endVMTime = Get-Date
$vmTimeSpan = NEW-TIMESPAN -Start $startVMTime -End $endVMTime
$vmTimeSeconds = [INT]$vmTimeSpan.TotalSeconds

Write-Host "VM Create completed!"
Write-Host "Start to Attach Data Disk"

#Start to Attach Data Disk
#Due to Create Azure VM in Parallell,we cannot attached data disk immediately due to VM is under creating
$jobs = @()
foreach ($rows in $p)
{
        try
        {
            $SubscriptionId = $rows.SubscriptionId.Trim()
            $vmName = $rows.VMName.Trim()
            $vmRG = $rows.VMRG.Trim()
            $location = $rows.Location.Trim()

		    $dataDiskSKU = $rows.DataDiskSKU.Trim()
		    $dataDiskSizeInGB = $rows.DataDiskSizeInGB.Trim()
            
            #select the subscription Id
            Select-AzSubscription -SubscriptionId $SubscriptionId

		    #VM ResourceGroup
		    $rg = Get-AzResourceGroup -Name $vmRG -Location $location
		
		    #Data Disk
		    $datadiskname = $vmName + "-DataDisk01"

            #maximium Data Disk is 32TB
            $dataDiskSizeInGB = [INT]$dataDiskSizeInGB
            if($dataDiskSizeInGB -gt 32767)
            {
                $dataDiskSizeInGB = 32767
            }

		    $diskconfig = New-AzDiskConfig -location $location -createoption empty -DiskSizeGB $dataDiskSizeInGB -SkuName $dataDiskSKU
		    $datadisk = new-Azdisk -resourcegroupname $rg.resourcegroupname -diskname $datadiskname -disk $diskconfig
		    $disk = Get-AzDisk -ResourceGroupName $rg.resourcegroupname -DiskName $datadisk.name
		
		    $vm = Get-AzVM -Name $vmName -ResourceGroupName $rg.resourcegroupname
		    $vm = Add-AzVMDataDisk -CreateOption Attach -Lun 0 -VM $vm -ManagedDiskId $disk.Id
            #$jobs += Update-AzVM -VM $vm -ResourceGroupName $rg.resourcegroupname -AsJob

            Update-AzVM -VM $vm -ResourceGroupName $rg.resourcegroupname -AsJob
            
            write-host "Start attach Data Disk for VM "$vmName
        }
        catch [Exception] 
        {
              write-host $_.Exception.Message;
        }
        Finally
        {

        }
}

#$jobs | Wait-Job | Remove-Job -Force

$endTotalTime = Get-Date
$totalTimeSpan = NEW-TIMESPAN -Start $startTotalTime -End $endTotalTime
$totalTimeSeconds = [INT]$totalTimeSpan.TotalSeconds

write-host "Attach Disk complete"      
write-host "Create VM Cost " $vmTimeSeconds " seconds, total cost " $totalTimeSeconds " seconds"

