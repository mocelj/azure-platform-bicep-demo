# Platform setup: native Bicep, Policy and scoped RBAC

The repository is prepared for local compilation and CI. Azure setup is a
separate step: no resources, identities, federations, role assignments or policy
assignments have been created for this demo. Review the scopes and costs below
before approving that step. Application release and private-URL testing are
outside the agreed scope.

Local validation on 2026-09-24: pinned Bicep **0.47.16** restored and compiled
`main.bicep`, `shared.bicep` and `demo.bicepparam` with **zero warnings/errors**.
Source and compiled-template checks verified the output contract, scope,
guardrail parameters, identity/network settings and dependency ordering.
Compiled artifacts stayed outside this repository.

## Minimal platform boundary

`platform-setup\main.bicep` is the subscription-scope bootstrap entrypoint. Its
only first-party composition is `shared.bicep`; all Azure resources are inside
official, exact-version AVM modules. Telemetry is disabled on every AVM call.
The default names create exactly two resource groups:

| Future scope | Owned resources |
| --- | --- |
| `rg-platform-bicep-demo-shared` | VNet, two subnets, integration NSG, NAT gateway/outbound public IP, private DNS zone/link, Log Analytics, one deployment UAMI and its two federations |
| `rg-platform-bicep-demo-app` | The app-scoped built-in policy assignment and deployment-identity Contributor grant; application resources are deployed later by the separate developer entrypoint |

No Web App, App Service Plan or private endpoint is provisioned by bootstrap.
It does not create a VM, VPN, runner, registry, storage account or Terraform
backend. `namePrefix` and the two resource-group names are platform-owned naming
inputs, not an invitation to adopt an existing customer foundation. Use
lower-case letters, digits and hyphens for the prefix. The groups must differ.
Regional resources are constrained to `swedencentral`; Azure private DNS is a
global resource. Tags are fixed to `purpose=platform-native-bicep-demo` and
`environment=demo`; the policy uses equivalent metadata because its AVM has no
tag input. Exact module pins and API details are in
[`platform-setup/dependencies.json`](../platform-setup/dependencies.json).

### Networking and explicit demo exceptions

The new VNet uses `10.62.0.0/16` and only these subnets:

| Subnet | Prefix | Configuration |
| --- | --- | --- |
| `snet-private-endpoints` | `10.62.1.0/24` | Nondelegated, PE network policies disabled; reserved for later inbound private endpoints |
| `snet-web-app` | `10.62.2.0/24` | `Microsoft.Web/serverFarms` delegation, NAT, explicit default outbound access disabled, integration NSG |

Web App VNet integration is **outbound**, not private inbound access. Its NSG
denies unsolicited inbound traffic; stateful responses to allowed outbound
traffic remain possible. Default outbound NSG rules remain in place. The
separate PE subnet has network policies disabled, so this setup does not claim
NSG-based filtering of PE traffic. The future app must use a private endpoint
and route all outbound traffic through integration.

One Standard/Regional static IPv4 public IP attaches only to a Standard NAT
gateway. Both use the same explicitly selected logical zone (default `1`).
NAT enables outbound connections and return traffic, not inbound public app
access. It is **not a firewall**, inspection system or destination allowlist.
Live zone/SKU capacity, quota and policy compatibility are not proven.

`privatelink.azurewebsites.net` links only to this VNet with registration off.
The future site PE DNS-zone group must supply app **and SCM** records. No
client routing, peering, resolver, VPN or private runner is included. ARM-based
infrastructure deployment does not require a private runner; reaching a private
application endpoint later does require separately approved private connectivity
and DNS. This demo does not create or test that connectivity.

Log Analytics has 30-day retention, local authentication disabled and public
ingestion/query enabled. This is an explicit **Azure Monitor public-connectivity
exception**; no AMPLS or workspace shared-key grants are configured. Workloads
must use managed-identity/Entra access and Azure Monitor diagnostic settings,
not workspace shared keys. Microsoft-managed encryption is used; no CMK claim.
NAT and public Monitor access are demo allowances, not production controls.

## Identity ownership and least privilege

The platform creates **one UAMI in the shared group**, outside the app group's
Contributor scope. It has exactly two GitHub environment subjects by default:

- `repo:mocelj/azure-platform-bicep-demo:environment:demo-plan`
- `repo:mocelj/azure-platform-bicep-demo:environment:demo-apply`

The issuer is `https://token.actions.githubusercontent.com`; the audience is
`api://AzureADTokenExchange`. There are no branch, pull-request or wildcard
subjects. `repository` is an exact platform-selected `owner/repository`; changing
it changes a trust boundary and needs review. Protect both GitHub environments
and trusted workflow source before any federation is activated. A workflow from
a fork must never receive an approved environment token.

| Role | Exact future scope | Purpose and limitation |
| --- | --- | --- |
| Contributor | App RG only | App infrastructure and ARM what-if. Also allows app-resource deletion; the plan phase is not read-only. |
| Reader | Shared RG only | Read existing foundation metadata; cannot edit the UAMI/federations, workspace, NAT or NSG. |
| Network Contributor | Each of the two dedicated subnets | Subnet joins and integration. This also permits subnet modification, so trusted code/review are required. |
| Private DNS Zone Contributor | The one private DNS zone | PE DNS-zone groups/records. This role can modify records in that zone. |

No subscription Owner/Contributor, Policy Contributor, User Access Administrator,
RBAC Administrator or role-assignment administration is granted to the app
identity. App RG Contributor does not allow editing the policy assignment or
creating workload role grants. Shared-group Reader plus the narrow network/DNS
grants do not allow updating the shared UAMI or adding a federation.

Both environments use the **same identity and privileges** for simplicity.
Environment approval is not separation of Azure principals or independent
separation of duties. Bootstrap requires a separately authorized platform
operator with resource-group/provisioning, scoped role-assignment and policy-
assignment rights. This repository does not grant that operator access.

## Built-in Deny, not a custom or subscription policy

The assignment is scoped only to the dedicated app RG and uses:

- Definition `/providers/Microsoft.Authorization/policyDefinitions/1b5ef780-c53c-4a64-87f3-bb9c8c8094ba`
- Definition version `1.2.0`
- `parameters.effect.value = Deny`, `enforcementMode = Default`
- `managedIdentities = {}` to override the AVM's default system identity
- No role definition IDs, exclusions, exemptions, overrides or custom policy

This is the general **App Service apps should disable public network access**
built-in, not the similarly named Mission policy. Its rule targets
`Microsoft.Web/sites` outside an App Service Environment when
`publicNetworkAccess` is absent or not `Disabled`. It does not prove that private
endpoints, TLS, outbound routing, DNS or application health are correct, and it
is not a subscription-wide restriction on other resource types. It does not
remediate existing resources. Review the pinned definition at connected preflight.

The dependency graph has no circular dependency: create both groups; create
shared resources/identity; install the policy in the app group; then grant app
Contributor after the policy deployment completes. Policy/RBAC propagation must
still be verified before later app operations. Completing an ARM assignment is
not evidence that enforcement has propagated.

This is a focused guardrail demo, not tamper-proof containment. Contributor has
destructive rights over the dedicated app group/resources; scope lifetime and
the effect of deleting a group require platform governance. It cannot recreate
an arbitrary subscription resource group without additional rights. Do not
claim the Deny assignment substitutes for trusted deployment workflows.

## Local compilation only

Use the existing verified standalone Bicep **0.47.16**; do not use Azure CLI's
automatic Bicep installation. From this repository root:

```powershell
.\scripts\Get-Bicep.ps1
$bicep = Join-Path (Get-Location) $(if ($IsWindows) { '.tools\bicep.exe' } else { '.tools/bicep' })
$output = Join-Path $env:TEMP 'platform-native-bicep-demo-build'
New-Item -ItemType Directory -Force $output | Out-Null
& $bicep --version
& $bicep restore '.\platform-setup\main.bicep'
if ($LASTEXITCODE -ne 0) { throw 'Bicep restore failed' }
& $bicep build '.\platform-setup\main.bicep' --no-restore --outfile (Join-Path $output 'main.json')
if ($LASTEXITCODE -ne 0) { throw 'Bicep build failed' }
& $bicep build '.\platform-setup\shared.bicep' --no-restore --outfile (Join-Path $output 'shared.json')
if ($LASTEXITCODE -ne 0) { throw 'Shared composition build failed' }
& $bicep build-params '.\platform-setup\demo.bicepparam' --no-restore --outfile (Join-Path $output 'parameters.json')
if ($LASTEXITCODE -ne 0) { throw 'Parameter compilation failed' }
```

Compiled JSON is a local build artifact, not checked-in source. Restore downloads
public pinned modules but performs no Azure deployment. The fixture contains no
subscription/tenant IDs, customer data, credentials or runtime secrets.

## Future connected operations: separate approval required

**None of the following commands were run in Phase 1.** The platform operator
must select/confirm the subscription and identity, review names/IP overlaps,
permissions, registrations and costs, and obtain authorization first. Do not
automatically register providers or create permissions to make preflight pass.
Compilation cannot prove region availability or enforcement.

After local compilation and explicit approval for connected what-if:

```powershell
$subscriptionId = '<approved-subscription-id>'
$deploymentName = 'platform-native-bicep-demo'
az account show --subscription $subscriptionId --query '{subscription:id,tenant:tenantId}' --output json
az deployment sub what-if --subscription $subscriptionId --location swedencentral --name $deploymentName --template-file (Join-Path $output 'main.json') --parameters "@$(Join-Path $output 'parameters.json')"
```

Review that result and obtain **separate deployment approval** before this
future write operation:

```powershell
az deployment sub create --subscription $subscriptionId --location swedencentral --name $deploymentName --template-file (Join-Path $output 'main.json') --parameters "@$(Join-Path $output 'parameters.json')"
```

These commands use compiled JSON and an explicit subscription; neither relies
on automatic Bicep installation. They do not release an application or test a
private URL. Subsequent read-only deployment output retrieval, if authorized:

```powershell
az deployment sub show --subscription $subscriptionId --name $deploymentName --query properties.outputs --output json
```

### Non-secret integration outputs

`main.bicep` exposes exactly these strings:

| Output | Downstream use |
| --- | --- |
| `workloadResourceGroupName` | App deployment scope |
| `deploymentClientId` | Protected GitHub environment OIDC client ID |
| `deploymentPrincipalId` | Scoped RBAC verification |
| `deploymentIdentityResourceId` | Identity ownership verification |
| `logAnalyticsWorkspaceResourceId` | App diagnostics destination |
| `privateEndpointSubnetResourceId` | Inbound PE subnet |
| `integrationSubnetResourceId` | Separate outbound integration subnet |
| `privateDnsZoneResourceId` | App/SCM private DNS-zone group |
| `policyAssignmentResourceId` | Guardrail inspection/enforcement evidence |
| `tenantId` | Protected OIDC environment configuration |

The actual subscription is operator-selected, not a committed ID or an output
secret. Do not commit later environment bindings or raw deployment dumps.

### GitHub environment configuration

After Azure provisioning is separately approved and verified, populate these
secrets in both `demo-plan` and `demo-apply`. The IDs are not credentials, but
using secrets keeps subscription-bearing values masked in public workflow logs.

| GitHub secret | Source |
| --- | --- |
| `AZURE_SUBSCRIPTION_ID` | Confirmed deployment subscription |
| `AZURE_TENANT_ID` | `tenantId` output |
| `AZURE_CLIENT_ID` | `deploymentClientId` output |
| `AZURE_RESOURCE_GROUP` | `workloadResourceGroupName` output |
| `PLATFORM_LOG_ANALYTICS_RESOURCE_ID` | `logAnalyticsWorkspaceResourceId` output |
| `PLATFORM_PRIVATE_ENDPOINT_SUBNET_ID` | `privateEndpointSubnetResourceId` output |
| `PLATFORM_PRIVATE_DNS_ZONE_ID` | `privateDnsZoneResourceId` output |
| `PLATFORM_WEB_INTEGRATION_SUBNET_ID` | `integrationSubnetResourceId` output |
| `PLATFORM_POLICY_ASSIGNMENT_ID` | `policyAssignmentResourceId` output |

Restrict both environments to main. Require review for `demo-apply` and disable
admin bypass. Protect workflow changes and the catalog pin. Only after those
settings and Azure permissions are verified should an operator set the repository
variable `ENABLE_AZURE_DEPLOYMENT` to `true`.

The publisher creates the environments and keeps that variable false in
Phase 1. It does not add the Azure bindings or grant Azure access.

## Later verification and cost/cleanup

After a separately approved bootstrap, verify exactly two groups, resource
ownership, two subnet prefixes/delegation, NAT/PIP matching zone, the NSG, and
the private DNS link. Verify workspace local-auth/public-connectivity settings,
both FIC subjects, all scoped role grants, and **absence** of policy/RBAC-admin
rights for the UAMI. Inspect the exact policy definition version, Deny effect,
app-only scope, Default enforcement and lack of identity/exemptions.

Wait for RBAC and policy propagation. A later approved positive/negative app
infrastructure exercise must collect actual compliant deployment and denial
evidence, without interpreting what-if as proof of enforcement. App deployment,
sample release, DNS reachability, private URL responses and runtime health are
not part of Phase 1. No claim is made that any of them succeeded.

NAT gateway hours/data processing, the Standard public IPv4, private DNS
zone/queries and Log Analytics ingestion/retention can incur charges even
without a sample app. Future App Service plan/PE charges are separate. UAMI,
RG and policy existence does not make the whole demo free.

There is **no automatic cleanup** or scheduled teardown. Later cleanup needs
explicit approval, retention of required evidence, stopped workflows and
verification of exact demo ownership. Remove app resources before shared
network/DNS/identity dependencies; remove only these demo groups under the
platform operator's change process. Never delete customer/shared foundations.
