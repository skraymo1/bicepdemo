param()

$ErrorActionPreference = 'Stop'
$templateFile = [System.IO.Path]::GetTempFileName()

function Assert-True($Condition, [string]$Label) {
    if (-not $Condition) {
        throw "FAILED: $Label"
    }
    Write-Output "PASS: $Label"
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    az bicep build --file .\infra\main.bicep --outfile $templateFile --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw 'Bicep compilation failed.'
    }

    $template = Get-Content $templateFile -Raw | ConvertFrom-Json
    $parameters = Get-Content .\infra\main.parameters.json -Raw | ConvertFrom-Json
    $network = ($template.resources | Where-Object name -eq 'network').properties.template
    $jumpbox = ($template.resources | Where-Object name -eq 'jumpbox').properties.template
    $services = ($template.resources | Where-Object name -eq 'services').properties.template
    $vm = $jumpbox.resources | Where-Object type -eq 'Microsoft.Compute/virtualMachines'
    $nic = $jumpbox.resources | Where-Object type -eq 'Microsoft.Network/networkInterfaces'
    $storage = $services.resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts'
    $foundry = $services.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts'
    $vnet = $network.resources | Where-Object type -eq 'Microsoft.Network/virtualNetworks'
    $bastion = $network.resources | Where-Object type -eq 'Microsoft.Network/bastionHosts'
    $roles = @($services.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')

    Assert-True ($null -eq $template.parameters.location.PSObject.Properties['defaultValue'] -and $template.parameters.location.minLength -eq 1) 'Location is required so azd collects deployment metadata region'
    Assert-True ($template.'$schema' -like '*subscriptionDeploymentTemplate.json*') 'Subscription-scoped entry point for azd'
    Assert-True ($parameters.parameters.environmentName.value -eq '${AZURE_ENV_NAME}' -and $parameters.parameters.location.value -eq '${AZURE_LOCATION}') 'azd environment parameter bindings'
    Assert-True ($null -ne $template.outputs.AZURE_RESOURCE_GROUP -and $null -ne $template.outputs.JUMPBOX_ID) 'azd environment outputs'
    Assert-True (@($template.resources | Where-Object type -eq 'Microsoft.Resources/resourceGroups').Count -eq 1) 'Resource group created by Bicep'
    Assert-True ($template.parameters.vmSize.defaultValue -eq 'Standard_D2as_v7') 'Checked VM size default'
    Assert-True ($null -eq $template.parameters.PSObject.Properties['sshPublicKey']) 'No SSH key required'
    Assert-True ($template.parameters.adminPassword.type -eq 'secureString' -and $null -eq $template.parameters.adminPassword.PSObject.Properties['defaultValue']) 'azd must collect a secure Windows password'
    Assert-True ($template.parameters.adminPassword.minLength -eq 12 -and $jumpbox.parameters.adminPassword.type -eq 'secureString') 'Password constraints and secure module parameter'
    Assert-True ($parameters.parameters.principalId.value -eq '${AZURE_PRINCIPAL_ID}') 'azd deployment identity binding'
    Assert-True ($template.parameters.prefix.maxLength -eq 9) 'Generated storage name fits 24 characters'
    Assert-True ($vm.properties.storageProfile.imageReference.publisher -eq 'MicrosoftWindowsServer' -and $vm.properties.storageProfile.imageReference.sku -eq '2025-datacenter-azure-edition') 'Windows Server 2025 desktop image'
    Assert-True ($vm.properties.osProfile.adminPassword -eq "[parameters('adminPassword')]" -and $vm.properties.osProfile.windowsConfiguration.enableAutomaticUpdates -eq $true) 'Windows authentication and updates configured'
    Assert-True ($vm.properties.osProfile.PSObject.Properties.Name -notcontains 'linuxConfiguration') 'Linux SSH configuration removed'
    Assert-True ($vm.identity.type -eq 'SystemAssigned') 'Jump box has managed identity'
    Assert-True ($vm.properties.securityProfile.uefiSettings.secureBootEnabled -and $vm.properties.securityProfile.uefiSettings.vTpmEnabled) 'Trusted Launch protections enabled'
    Assert-True ($nic.properties.ipConfigurations[0].properties.PSObject.Properties.Name -notcontains 'publicIPAddress') 'No VM public IP'
    Assert-True ($storage.properties.publicNetworkAccess -eq 'Disabled' -and $storage.properties.allowSharedKeyAccess -eq $false -and $storage.properties.allowBlobPublicAccess -eq $false) 'Storage public access and shared keys disabled'
    Assert-True ($foundry.properties.publicNetworkAccess -eq 'Disabled' -and $foundry.properties.disableLocalAuth -eq $true -and $foundry.properties.allowProjectManagement -eq $true) 'Foundry private, keyless, project-capable'
    Assert-True ($bastion.sku.name -eq 'Standard' -and $bastion.properties.enableTunneling -eq $true) 'Bastion native tunneling enabled'
    Assert-True ($vnet.properties.subnets.Count -eq 3) 'Three separate subnets'
    $bastionPrefixExpression = "[variables('bastionPrefix')]"
    Assert-True ($network.variables.bastionPrefix -eq '10.42.0.0/26' -and ($vnet.properties.subnets | Where-Object name -eq 'AzureBastionSubnet').properties.addressPrefix -eq $bastionPrefixExpression) 'Bastion subnet meets minimum size'

    $jumpSubnet = $vnet.properties.subnets | Where-Object name -eq 'snet-jumpbox'
    Assert-True ($jumpSubnet.properties.defaultOutboundAccess -eq $false -and $null -ne $jumpSubnet.properties.natGateway.id) 'Explicit NAT egress only'
    $jumpNsg = $network.resources | Where-Object { $_.type -eq 'Microsoft.Network/networkSecurityGroups' -and $_.name -like '*nsg-jumpbox*' }
    $rdpRule = ($jumpNsg.properties.securityRules | Where-Object name -eq 'AllowRdpFromBastion').properties
    Assert-True ($rdpRule.sourceAddressPrefix -eq $bastionPrefixExpression -and $rdpRule.destinationPortRange -eq '3389') 'RDP restricted to Bastion subnet'
    Assert-True (@($jumpNsg.properties.securityRules | Where-Object { $_.properties.access -eq 'Allow' -and $_.properties.destinationPortRange -eq '22' }).Count -eq 0) 'No SSH allowance on jump box'
    Assert-True (($jumpNsg.properties.securityRules | Where-Object name -eq 'DenyOtherInbound').properties.access -eq 'Deny') 'Other ingress denied'
    Assert-True ($roles.Count -eq 3 -and @($roles | Where-Object { $_.properties.principalType -eq 'ServicePrincipal' }).Count -eq 2) 'Two managed identity roles plus operator Foundry role'
    Assert-True (@($roles | Where-Object { $_.properties.principalId -eq "[parameters('principalId')]" }).Count -eq 1) 'Deploying identity granted Foundry access'

    $blobLink = $template.resources | Where-Object name -eq 'blob-private-link'
    $foundryLink = $template.resources | Where-Object name -eq 'foundry-private-link'
    Assert-True ($blobLink.properties.parameters.groupId.value -eq 'blob' -and $blobLink.properties.parameters.dnsZoneNames.value.Count -eq 1) 'Blob endpoint and DNS'
    Assert-True ($foundryLink.properties.parameters.groupId.value -eq 'account' -and $foundryLink.properties.parameters.dnsZoneNames.value.Count -eq 3) 'Foundry endpoint and three DNS zones'

    Write-Output 'Local template checks passed. No Azure resources deployed.'
}
finally {
    Remove-Item -LiteralPath $templateFile
    Pop-Location
}
