@description('Azure region for the VM and NIC.')
param location string

@description('Consistent suffix for resource names.')
param nameSuffix string

@description('Private subnet for the jump box.')
param subnetId string

@description('Local Windows administrator.')
param adminUsername string

@description('Local Windows administrator password.')
@secure()
@minLength(12)
@maxLength(123)
param adminPassword string

@description('VM size with sufficient regional family quota.')
param vmSize string

@description('Resource tags.')
param tags object

resource nic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: 'nic-jumpbox-${nameSuffix}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'private-ip'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-jumpbox-${nameSuffix}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2025-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

output name string = vm.name
output id string = vm.id
output principalId string = vm.identity.principalId
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
