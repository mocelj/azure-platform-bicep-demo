# Meeting walkthrough

Use this demo before the configuration-only catalog and portal examples.
The application team works with ordinary Bicep files; the platform provides
the module and the Azure guardrails.

## Before the meeting

Complete the [platform setup review](platform-setup.md) and obtain separate
approval before provisioning anything. Rehearse the small/B1 baseline,
medium/B2 change and validation-only policy test. These live steps are not
part of the initial repository publication.

Keep these views ready:

- `infra/main.bicep` and `infra/demo.bicepparam`.
- The referenced Web App wrapper in the catalog.
- A parameter-change PR and its checks.
- The deployment workflow and its approval step.
- The demo resource group and policy assignment in Azure Portal.

If Azure is not configured, show compilation and the intended workflow, but
describe the Azure deployment and denial as pending rather than successful.

## 1. Show the module reference

Open `infra/main.bicep`.

> The application team references a platform-owned composition. The catalog
> commit is pinned, and the implementation uses Azure Verified Modules.
> We are not maintaining our own App Service resource implementation.

Open `platform.ref` and the corresponding catalog wrapper. Show the fixed
private-access settings and the small/B1, medium/B2 mapping.

## 2. Make the application change

Create a branch and change only the profile in `infra/demo.bicepparam`:

```diff
-param size = 'small'
+param size = 'medium'
```

Run:

```powershell
.\scripts\Test.ps1
```

Open a PR. Its checks compile the caller, the referenced module and parameters
without an Azure identity.

> This is a normal application-repository change. The developer works in Bicep,
> while the platform supplies networking and monitoring bindings.

## 3. Review and deploy the merged change

After the live setup is approved and enabled, merging an infrastructure change
starts the deployment workflow. The plan job uses the `demo-plan` environment.
Inspect its source revision, requested profile and sanitized what-if summary.

The apply job waits for `demo-apply` approval. It checks the same source and
parameters and repeats what-if. Drift or incomplete results block apply.
Approve only after reviewing the change.

Show the result in Azure Portal:

- App Service plan tier changed to B2.
- Public network access remains Disabled.
- The private endpoint connection is approved.
- VNet integration references the dedicated integration subnet.
- Managed identity and diagnostic settings remain configured.

These are control-plane checks, not an application-health demonstration. Do not
open the site expecting a deployed application: no application package is
included, and the endpoint is private.

## 4. Demonstrate policy enforcement

Open `scenarios/policy-denial/main.bicep`. It uses the official site AVM but
sets public network access to Enabled.

> A module reference makes the standard configuration easy to use. A developer
> could still write a different valid configuration. Azure Policy provides
> the independent enforcement.

Run **Demonstrate Azure Policy denial** from protected main. This workflow:

1. Checks the expected versioned assignment and Deny configuration.
2. Confirms the existing Web App is private.
3. Calls Azure deployment **validation**, not deployment.
4. Requires `RequestDisallowedByPolicy` from the expected definition and
   assignment.
5. Checks that resource inventory and the existing public-access setting
   remain unchanged.

A passing policy test means Azure rejected the proposed configuration. It does
not mean the noncompliant resource was deployed. A successful Azure validation,
an authorization error, or a different policy failure must fail this test.
Never manually deploy the negative fixture.

## 5. Compare with the more controlled model

> This is already a golden path: a reusable module, normal PR workflow,
> scoped permissions and Azure enforcement. The next layer can hide Bicep
> behind a smaller configuration interface or a portal if that suits the teams.

The configuration-only demo executes only catalog-owned infrastructure.
This native demo gives the app workflow deployment rights within its assigned
scope and relies on repository governance, RBAC and Azure Policy. They are
different operating models, not mandatory successive security levels.

## Reset and cleanup

A return from medium to small should also use a reviewed PR and deployment.
Check actual SKU support and cost implications before making that change.

Cloud cleanup is a separate operator action. Review the isolated resource
inventory and remove app resources before the shared foundation. Confirm
network/DNS references, policy assignments and federations are no longer needed.
Do not delete any group automatically or include the existing Template Spec
preview or other demos in cleanup.
