# Security and Data Residency

## Part A — Security controls

### Secrets and configuration

- No credential of any kind exists in source control, tfvars, or CI
  variables. `APP_KEY` and the database password are generated inside
  Terraform and live only in Secret Manager (region-pinned replication) and
  in the access-controlled, versioned state bucket.
- The runtime identity can read exactly its two secrets (secret-level
  `secretAccessor` grants); nothing is granted project-wide to the runtime.
- Secret rotation: add a new secret version, redeploy (revisions read
  `latest` at boot). Database password rotation is a Terraform change
  (`random_password` keeper) plus a rolling deploy.

### IAM

- **No service account keys exist.** CI authenticates through OIDC
  workload identity federation, restricted by attribute condition to this
  single repository. Tokens are short-lived and scoped.
- Three-identity model (runtime / deployer / operator) with least privilege
  per identity — detailed in `docs/architecture/architecture.md`.
- The deployer's grants are project-level but the project contains only
  this workload; the project is the blast-radius boundary. In an org
  setting these become per-resource grants plus org-level guardrails
  (e.g. disable service account key creation, restrict resource locations).

### Network

- Databases have no public IP and are unreachable from the internet by
  construction; only private-VPC egress from the service reaches them.
- Per-environment VPCs with non-overlapping CIDRs; explicit deny-all
  ingress firewall; TLS terminated at the managed HTTPS front end with
  platform certificates.
- The API itself is public and unauthenticated **by assessment design**
  (the supplied app has no auth layer and feature work is out of scope).
  In production this would sit behind authentication at the app layer and
  a WAF/rate-limiting layer (Cloud Armor / Huawei WAF) at the edge.

### Supply chain and pipeline

- Images are built once in CI, vulnerability-scanned (Trivy, fails on
  fixable CRITICAL/HIGH), pushed to a private registry, and promoted by
  digest/tag — staging and production run the same artifact.
- Migrations run under the runtime identity, not the deployer's.
- `terraform fmt`/`validate`/`plan` run in CI with read-only cloud access;
  applies are operator-performed from reviewed code.

### Auditability

- All control-plane actions (deploys, IAM changes, secret access) are
  captured in cloud audit logs; application logs go to stderr and are
  centrally retained. Backups and state are versioned.

## Part B — Data residency

### The regulatory driver

This is not hypothetical for Cashonrails. The CBN circular of 15 June 2026
directs that payment transaction data generated in Nigeria must be stored
and managed on infrastructure **within Nigeria by 1 January 2027** — 
including primary databases, settlement/reconciliation records, audit
trails, **cloud backups and disaster-recovery copies**, with supervisory
and administrative control exercised locally. Sources:
[Mondaq summary](https://www.mondaq.com/nigeria/financial-services/1823206/),
[Capacity](https://capacityglobal.com/news/nigerias-payment-data-must-stay-onshore/),
[Privalex analysis](https://www.privalexadvisory.com/insights/the-cbn-payment-data-localisation-directive-legal-tensions-market-consequences-and-the-road-to-1-january-2027).

Two consequences the brief's "Important" note points at:

1. **Choosing a provider or region does not satisfy residency.** The
   boundary must be drawn per data class, and derived copies (backups, DR,
   logs, state) count.
2. **DR copies cannot leave Nigeria** for designated data — the reflex of
   "replicate cross-region for DR" would itself be a violation.

### Data classification

| Data class | Contains designated data? | Residency treatment |
| --- | --- | --- |
| Application database (customers, transactions) | **Yes** | Inside the boundary: in-country primary |
| Database backups + PITR logs | **Yes** (derived) | Inside: in-country, no cross-border replication |
| DR copies | **Yes** (derived) | Inside: second AZ/site in-country |
| Cache, sessions, queue rows | **Yes** — they are DB tables here and carry customer identifiers | Inside (they live in the same database) |
| Application logs | **Potentially** (emails/names in request logs) | Treat as inside: in-country log storage; scrub PII at the app boundary as defence-in-depth |
| Audit logs | Control-plane metadata, but CBN expects audit trails locally | Inside |
| Monitoring/telemetry (metrics, uptime results) | No payload — aggregates and probe results | Outside is acceptable; document it |
| Secrets and encryption keys | Not customer data, but access-critical; CBN expects local management control | Inside: region-pinned secret replication |
| Container images + artifact metadata | No customer data | Outside is acceptable |
| Terraform state | **Careful: yes-adjacent** — holds connection details and generated credentials | Treat as inside; versioned, access-controlled, in-country bucket |
| CI/CD runner ephemera | Build context only, no customer data | Outside is acceptable (never handles production data) |

### On Huawei Cloud (the target platform)

Huawei Cloud launched Nigeria's first hyperscale local cloud region in
**Lagos (Ikoyi), December 2024** — Tier 3+, 30+ services including
compute, managed databases, storage and security
([Huawei announcement](https://www.huaweicloud.com/intl/en-us/news/20241212084526769.html),
[DCD](https://www.datacenterdynamics.com/en/news/huawei-launches-cloud-region-in-nigeria/)).
The residency architecture is therefore:

- **Data plane in the Lagos region**: RDS for MySQL primary + backups,
  OBS buckets (backups, Terraform state), CSMS secrets, LTS logs.
- **Verified limitation to state clearly**: the Lagos region is young and
  (per public reporting) launched with a single availability zone, and I
  was unable to verify from public documentation which of the 30+ services
  are fully available there versus served from AF-Johannesburg. Before
  committing an architecture I would verify per-service: (a) availability
  in Lagos, (b) where each service stores its data and metadata, and
  (c) where support/administrative access occurs — the CBN directive also
  covers *management* locality.
- **DR inside Nigeria**: with one hyperscale AZ, DR for designated data
  means a second in-country site (second local DC, Huawei Cloud Stack in a
  Nigerian facility, or a licensed local provider) — **not**
  AF-Johannesburg. Non-designated layers (stateless compute, images,
  telemetry) may burst to other regions.

### In this implementation (GCP, honest status)

Google Cloud has **no Nigeria region**; this build uses `africa-south1`
(Johannesburg, South Africa) — the closest African region. Every residency
*mechanism* is demonstrated: all data-holding resources are pinned to one
declared region (database, backups, secrets replication, log storage,
state bucket), nothing replicates cross-region, and the boundary per data
class is documented above. But the region itself is not Nigeria, so this
implementation **demonstrates the controls without satisfying CBN
localisation** — on Huawei Cloud the identical layout lands in the Lagos
local region, which is precisely why the implementation pins regions
everywhere instead of accepting provider defaults.

### Preventing and detecting residency violations

Prevention:

- Organisation-level **resource location restriction** policy (GCP
  `gcp.resourceLocations`; Huawei Cloud equivalent or enforced tag/policy
  checks) limiting resource creation to approved regions — a guardrail
  above engineer intent.
- Terraform as the only provisioning path: region is an explicit variable;
  policy-as-code in the plan step fails CI on any resource outside the
  approved region list, and on unencrypted or publicly-addressable
  data stores.
- No multi-region storage classes anywhere; secret replication is
  `user_managed` and pinned; backups configured without cross-region
  copies.

Detection:

- Periodic asset-inventory sweep (Cloud Asset Inventory / Huawei RMS)
  reporting any resource whose location is outside the approved list, with
  alerting.
- Audit-log alerts on creation of storage/database resources in
  non-approved regions and on changes to the location policy itself.

### Assumptions made

1. "Designated production customer and transaction data" = the application
   database contents and everything derived from them (backups, DR, logs
   carrying customer identifiers).
2. Aggregated telemetry without payloads or identifiers is outside the
   boundary; this is an interpretation to confirm with compliance.
3. The assessment environment itself holds only seeded/synthetic data, so
   building it outside Nigeria is acceptable for evaluation purposes.
