targetScope = 'subscription'

@description('Environment name provided by azd.')
@minLength(1)
@maxLength(64)
param environmentName string

@description('Azure region. East US 2 was checked for this demo; availability can change.')
@minLength(1)
param location string

@description('Short lowercase letters/digits prefix used in resource names.')
@minLength(3)
@maxLength(9)
param prefix string = 'bicepdemo'

@description('Local Windows administrator account for RDP through Bastion.')
param adminUsername string = 'azureuser'

@description('Windows administrator password. Use a unique password meeting Azure complexity requirements.')
@secure()
@minLength(12)
@maxLength(123)
param adminPassword string

@description('Object ID of the signed-in azd identity, granted access to the Foundry project.')
param principalId string

@description('Jump box size. Check restrictions and family quota before changing.')
param vmSize string = 'Standard_D2as_v7'

@description('Tags applied to resources that support them.')
param tags object = {
  workload: 'private-foundry-demo'
  environment: 'demo'
}

var resourceTags = union(tags, {
  'azd-env-name': environmentName
})

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: resourceTags
}

var nameSuffix = '${prefix}-${uniqueString(rg.id)}'
var storageName = 'st${prefix}${uniqueString(rg.id)}'

module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    location: location
    nameSuffix: nameSuffix
    tags: resourceTags
  }
}

module jumpbox 'modules/jumpbox.bicep' = {
  name: 'jumpbox'
  scope: rg
  params: {
    location: location
    nameSuffix: nameSuffix
    subnetId: network.outputs.jumpboxSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    tags: resourceTags
  }
}

module services 'modules/services.bicep' = {
  name: 'services'
  scope: rg
  params: {
    location: location
    nameSuffix: nameSuffix
    storageName: storageName
    jumpboxPrincipalId: jumpbox.outputs.principalId
    principalId: principalId
    tags: resourceTags
  }
}

module blobPrivateLink 'modules/private-link.bicep' = {
  name: 'blob-private-link'
  scope: rg
  params: {
    location: location
    name: 'pep-blob-${nameSuffix}'
    subnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    targetResourceId: services.outputs.storageId
    groupId: 'blob'
    dnsZoneNames: [
      'privatelink.blob.core.windows.net'
    ]
    tags: resourceTags
  }
}

module foundryPrivateLink 'modules/private-link.bicep' = {
  name: 'foundry-private-link'
  scope: rg
  params: {
    location: location
    name: 'pep-foundry-${nameSuffix}'
    subnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    targetResourceId: services.outputs.foundryId
    groupId: 'account'
    dnsZoneNames: [
      'privatelink.cognitiveservices.azure.com'
      'privatelink.openai.azure.com'
      'privatelink.services.ai.azure.com'
    ]
    tags: resourceTags
  }
}

output AZURE_RESOURCE_GROUP string = rg.name
output STORAGE_ACCOUNT_NAME string = services.outputs.storageAccountName
output BLOB_ENDPOINT string = services.outputs.blobEndpoint
output CONTAINER_NAME string = services.outputs.containerName
output FOUNDRY_ACCOUNT_NAME string = services.outputs.foundryAccountName
output FOUNDRY_PROJECT_ENDPOINT string = services.outputs.projectEndpoint
output JUMPBOX_NAME string = jumpbox.outputs.name
output JUMPBOX_ID string = jumpbox.outputs.id
output JUMPBOX_PRIVATE_IP string = jumpbox.outputs.privateIp
output BASTION_NAME string = network.outputs.bastionName
output ADMIN_USERNAME string = adminUsername
