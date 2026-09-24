# Security and scope

The PR workflow has no Azure credentials. Azure jobs run only from protected
main in this repository, use environment-bound Entra federation, and remain
disabled until separately approved setup is complete.

The deployment identity is not a platform administrator. It has app-group
Contributor and the shared-resource access documented in the platform guide.
Contributor includes deletion rights; use this only in the dedicated demo
scopes. Do not give the app identity policy administration or access to its
own federation configuration.

The policy fixture is intentionally noncompliant and is for Azure validation
only. Never run a deployment command against it. The CI helpers reject
unexpected policy errors and destructive or incomplete what-if results.

Use private reporting for issues involving access, credentials or customer
data. Do not place tokens, real parameter files, raw plans or sensitive logs
in public issues, artifacts or commits. The repository contains illustrative
values, not customer configuration.

This demo is not a production FSI control set. NAT does not filter destinations,
Azure Monitor uses public endpoints, and a solo maintainer is not independent
separation of duties.
