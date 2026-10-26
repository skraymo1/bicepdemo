# Recreate this demo

Copy the prompt below into your coding assistant to recreate this project.

```text
Build a straightforward Azure infrastructure demo using Bicep and Azure Developer CLI. The deployment experience should be:

azd auth login
azd up

Generate the files, but do not deploy anything.

Resources:
- One resource group in East US 2.
- A Microsoft Foundry account (AIServices, S0) with a child project named demo-project. Use the current account/project model, not a legacy ML hub. Do not deploy models or agents.
- A StorageV2 account using Standard_LRS with a private blob container named demo.
- A Windows Server 2025 Datacenter Azure Edition VM with Desktop Experience, Gen2, Trusted Launch, Secure Boot, vTPM, managed identity, and managed boot diagnostics.
- Prefer Standard_D2as_v7 (2 vCPUs, 8 GB RAM), but verify current regional availability and subscription restrictions before selecting it.
- Azure Bastion Standard for browser-based RDP. The VM must have no public IP and require no SSH keys.
- A Standard NAT gateway for outbound downloads from the VM.

Networking:
- VNet: 10.42.0.0/16.
- AzureBastionSubnet: 10.42.0.0/26.
- Jump-box subnet: 10.42.1.0/24.
- Private-endpoint subnet: 10.42.2.0/24.
- Allow VM inbound RDP only from the Bastion subnet; deny other inbound traffic.
- Include the required Bastion NSG rules.
- Disable default outbound access on the workload subnet and attach NAT.
- Create private endpoints for blob storage and the Foundry account.
- Configure and link these private DNS zones:
  privatelink.blob.core.windows.net
  privatelink.cognitiveservices.azure.com
  privatelink.openai.azure.com
  privatelink.services.ai.azure.com

Security:
- Disable public data-plane access on Foundry and storage.
- Disable Foundry API-key authentication, storage shared keys, and anonymous blob access.
- Grant the VM identity Storage Blob Data Contributor on the demo container and Foundry User on the project.
- Grant the signed-in azd identity Foundry User on the project using AZURE_PRINCIPAL_ID.
- Prompt for a Windows administrator password through a secure Bicep parameter. Never hardcode or output it.

Project structure:
- azure.yaml with Bicep infrastructure and no application services.
- Subscription-scoped infra\main.bicep that creates the resource group.
- Small modules for networking, VM, services, and reusable private endpoints.
- infra\main.parameters.json using azd environment substitutions.
- Uppercase outputs for resource names, endpoints, VM ID, and resource group.
- Ignore .azure and generated files, but track main.parameters.json.

Important: make location a required, nonempty Bicep parameter mapped to AZURE_LOCATION. A Bicep default does not populate azd's subscription deployment metadata location.

Include local compilation/configuration checks and a concise README covering azd up, Bastion RDP, opening ai.azure.com inside the Windows VM, passwordless blob access using managed identity, costs, and azd down. Explain that Bastion is not a proxy for the laptop's browser, NAT is not a firewall, and the blob account is not automatically connected to Foundry.

Keep this a useful demo, not a production landing zone. No unnecessary services, frameworks, or deployment scripts.
```
