@description('Azure region for the private endpoint.')
param location string

@description('Private endpoint resource name.')
param name string

@description('Private endpoint subnet ID.')
param subnetId string

@description('VNet ID linked to the private DNS zones.')
param vnetId string

@description('Resource ID of the service to make privately reachable.')
param targetResourceId string

@description('Private Link subresource, for example blob or account.')
param groupId string

@description('Private DNS zones required by this service.')
param dnsZoneNames array

@description('Resource tags.')
param tags object

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in dnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, i) in dnsZoneNames: {
  parent: zones[i]
  name: 'link-demo-vnet'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource endpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'service'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneName, i) in dnsZoneNames: {
      name: 'zone-${i}'
      properties: {
        privateDnsZoneId: zones[i].id
      }
    }]
  }
}
