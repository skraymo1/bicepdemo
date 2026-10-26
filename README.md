# Bicep demo with azd

**`azd up` creates the resource group and deploys everything using Bicep.**
There is no application to build or deploy.

Includes a private Foundry account/project, private blob container, Windows jump
box, Azure Bastion, NAT gateway, and private endpoints/DNS. The VM has no public
IP and uses managed identity for blob access.

## Deploy

Install [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
and Azure CLI with Bicep. You need permission to create resource groups and
resources and assign roles in your subscription (Contributor alone cannot
assign roles).

From this folder in PowerShell:

```powershell
azd auth login
azd up
```

When prompted:

- Choose a new environment name, such as `bicepdemo`.
- Select your subscription and **East US 2**.
- Enter a unique Windows administrator password for `adminPassword` (12-123
  characters, meeting Azure's password complexity rules). No SSH key is needed.

The password is a Bicep `secureString`; it is not included in deployment outputs.
Keep it in your password manager, not in source control.

`azd` remembers the environment and parameter choices locally in `.azure/`
(ignored by Git). Run `azd up` again to update the same environment.
For a preview without provisioning, use `azd provision --preview`.

If an existing environment fails validation with "The 'location' property must
be specified", set azd's deployment location before retrying:

```powershell
azd env set AZURE_LOCATION eastus2
azd up
```

The Bicep location parameter is intentionally required: a template default
does not supply the subscription deployment's metadata location.

**This provisions billable resources.** Bastion Standard and NAT have ongoing
charges even when the VM is stopped. No models or agents are deployed.

If the earlier Linux version is already deployed, use a **new azd environment**
(`azd env new bicepdemo-win`) before `azd up`. An existing VM cannot switch from
Linux to Windows in place. The old environment remains billable until deleted.

## Connect

Open the jump box in Azure Portal and select **Connect > Bastion**, then use
**RDP**, username `azureuser`, and the Windows password you supplied. Bastion
opens the Windows desktop in your browser. The VM has no public IP and permits
RDP only from the Bastion subnet.

View the generated names and endpoints:

```powershell
azd env get-values
```

### Open Foundry

Inside the Windows desktop, open Edge (install it if necessary), go to
**https://ai.azure.com**, and sign in with the same Azure identity used by
`azd auth login`. Select the deployed account and `demo-project`.

The deployment grants that identity **Foundry User** on the project. New role
assignments can take several minutes to propagate. The local Windows login and
the Azure/Foundry login are separate.

A jump box is not a Foundry requirement. It provides a browser inside the VNet
because this demo disables Foundry's public data-plane access. A laptop with
VPN/private network access could be used instead. Bastion connects you to a VM;
it is not itself a desktop or a general-purpose proxy to Foundry.

The VM browser reaches Foundry through private DNS and the account's private
endpoint. Your laptop's browser and Cloud Shell do not gain that network path
just because you opened a Bastion session.

## Try blob access

On the Windows VM, install Azure CLI using Microsoft's
[Windows installation instructions](https://learn.microsoft.com/cli/azure/install-azure-cli-windows).
NAT provides outbound internet access for installation.

Use `STORAGE_ACCOUNT_NAME` from `azd env get-values`:

Run in PowerShell on the VM:

```powershell
$storage = "<storage-account-name>"
Resolve-DnsName "$storage.blob.core.windows.net"
az login --identity --allow-no-subscriptions
"Hello from a private Windows jump box!" | Set-Content "$env:TEMP\hello.txt"
az storage blob upload --account-name $storage --container-name demo `
  --name hello.txt --file "$env:TEMP\hello.txt" --auth-mode login --overwrite
```

DNS should resolve to `10.42.2.x`; the upload uses the VM identity rather than
an account key. New role assignments can take several minutes to propagate.
Run this demo from the VM, not your laptop.

## Customize

`azure.yaml` selects Bicep. `infra\main.parameters.json` maps the azd environment
name and location into `infra\main.bicep`, which creates the resource group and
deploys the modules. Edit the defaults in `main.bicep` for the VM size, resource
prefix, or Windows username. The image is Windows Server 2025 Azure Edition
(Gen2 with Desktop Experience), with Trusted Launch and automatic updates.

East US 2 and `Standard_D2as_v7` were checked against the selected subscription
on October 26, 2026. Available quota and advertised SKU support are not a live
allocation guarantee. The smaller B2s and D2 v5 sizes checked were restricted.

The VNet uses `10.42.0.0/16`: Bastion `/26`, jump box `10.42.1.0/24`, and
endpoints `10.42.2.0/24`. NAT is not an egress firewall. Blob storage is a separate
demo data store, not automatically connected to Foundry. This demo omits
production HA, backups, and centralized monitoring.

Local compilation and configuration checks (no Azure resource changes):

```powershell
.\tests\Validate-Template.ps1
```

## Delete

After verifying the selected environment contains only this disposable demo:

```powershell
azd down
```

Review the deletion prompt. This removes the environment's Azure resources,
including uploaded data and disks. Foundry soft deletion can retain names;
inspect any retained resources before choosing to recover or purge them.
If provisioning times out, inspect the deployment in Azure Portal before
retrying, since it may still be running.
