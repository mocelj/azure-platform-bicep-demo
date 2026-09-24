# Native Bicep golden path

[![Validate Bicep](https://github.com/mocelj/azure-platform-bicep-demo/actions/workflows/validate.yml/badge.svg)](https://github.com/mocelj/azure-platform-bicep-demo/actions/workflows/validate.yml)

This is the application-team side of a simple platform engineering workflow:
reference a platform Bicep module, change its parameters through a pull request,
and deploy within Azure Policy and RBAC boundaries.

The [platform catalog](https://github.com/mocelj/azure-platform-catalog) owns the
Web App composition. This repository checks out a fixed catalog commit and calls
that module directly. There is no custom request service, JSON request format,
module registry or Node/npm infrastructure layer.

**Current scope:** repository preparation and offline validation. Azure execution
is disabled. The foundation, deployment identity and policy code have not been
applied, and a live policy-denial result has not yet been demonstrated.

## What the developer changes

Start with [`infra/demo.bicepparam`](infra/demo.bicepparam):

```bicep
param name = 'ledger-native'
param size = 'small'
```

For the meeting, change `small` to `medium`. The platform wrapper maps those
profiles to one Linux B1 or B2 worker. The application name remains unchanged.
Private ingress, VNet integration, identity, TLS and diagnostics remain in the
platform composition.

[`infra/main.bicep`](infra/main.bicep) references the wrapper through the ignored
`.platform` checkout. [`platform.ref`](platform.ref) pins catalog release v0.1.0
by its full Git commit. No base resource implementation is copied into this repo.
The wrapper in turn uses Microsoft's versioned Azure Verified Modules.

## Validate locally

Use PowerShell 7.4 or later and Git:

```powershell
.\scripts\Get-PlatformSource.ps1
.\scripts\Test.ps1
```

The scripts retrieve the pinned catalog and a checksum-verified Bicep 0.47.16
compiler. They compile the application, parameter files, platform setup and
negative policy fixture. Small logic tests check workflow boundaries, review
hashes and the expected policy-error classification. They do not call Azure.

`infra/validation.bicepparam` contains placeholder IDs for compilation.
`infra/demo.bicepparam` takes real foundation bindings from protected environment
variables when used by an authorized deployment job. Generated files stay in
ignored `out`; the catalog checkout and compiler stay in `.platform` and `.tools`.

## The GitHub workflow

| Stage | Execution |
| --- | --- |
| Pull request | Compile and check on a GitHub-hosted runner, without Azure credentials |
| Merged change | Run what-if using the app's scoped, federated Azure identity |
| Approval | Pause at the protected `demo-apply` environment |
| Apply | Rebuild from the same commit, compare source/input and change hashes, then deploy |
| Policy demonstration | Manually run Azure validation of a fixed negative fixture from protected main |

Cloud jobs use Azure CLI 2.88.0 in an isolated runner-local Python environment.
Python is used to install the official CLI, not as a custom deployment service.
All action references and the Bicep compiler are pinned.

Both plan and apply use the same demo identity, scoped to the app group and
necessary shared resources. The plan job therefore has write-capable permissions,
although its code only runs what-if. Protect the workflow source and environment
branches; approval is not an independent separation of Azure principals.

What-if results containing deletion, ignored changes or unsupported operations
stop the workflow. Public summaries omit raw environment bindings. A change in
source, parameters or Azure state after planning requires a new plan and approval.

## What Azure Policy demonstrates

The platform assigns **App Service apps should disable public network access**,
definition version **1.2.0**, with effect **Deny**, only to the demo app group.

The [negative fixture](scenarios/policy-denial/main.bicep) deliberately calls
the official site AVM directly with public network access enabled. Bicep can
compile it; Azure Policy should reject it. The policy-check workflow uses
`validate`, never `create`, and accepts only the expected policy/assignment
denial. An unrelated permission error is not a successful test.

This illustrates the distinction between a useful module and an enforcement
boundary. Policy constrains the Azure resource outcome; it does not prove which
source module was used. The single policy shown here is not a complete FSI
policy baseline.

## Platform preparation and demo

- [Platform setup, permissions and approval checkpoint](docs/platform-setup.md)
- [Meeting walkthrough and expected results](docs/demo-runbook.md)
- [Security and contribution boundaries](SECURITY.md)

The setup code is included for reproducibility. It requires separately approved
platform-administrator permissions and is not run by the app deployment workflow.
Keep `ENABLE_AZURE_DEPLOYMENT=false` until that setup is approved, provisioned
and verified.

The eventual live demo provisions infrastructure only. It does not upload an
application package, verify a private URL, or create a VM, VPN, private runner,
ACR or Terraform backend. App Service plan, NAT, Private Link and monitoring
can incur charges without application code.

Original demo code is MIT licensed. The referenced AVM modules and tools retain
their upstream licenses. Existing catalog/consumer repositories and the separate
Template Spec preview are not changed by this demo.
