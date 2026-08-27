# CashOnRails Assessment — Application + Infrastructure

This fork contains the complete DevOps/Platform assessment solution
alongside the supplied Laravel API: Terraform-provisioned infrastructure,
a CI/CD pipeline with gated promotion, security/residency documentation,
and production runbooks.

| Deliverable | Location |
| --- | --- |
| Terraform (modules + 3 environment roots) | [`terraform/`](terraform/) |
| CI/CD (test/build/scan/deploy, terraform checks, rollback) | [`.github/workflows/`](.github/workflows/) |
| Architecture + diagram + trade-offs | [`docs/architecture/architecture.md`](docs/architecture/architecture.md) |
| Platform design (paved road, new-team scenario) | [`docs/platform-design/platform-design.md`](docs/platform-design/platform-design.md) |
| Security + data residency (CBN) | [`docs/security-data-residency/security-data-residency.md`](docs/security-data-residency/security-data-residency.md) |
| Runbooks, RPO/RTO, incident procedures | [`docs/operations/runbooks.md`](docs/operations/runbooks.md) |
| Original application README | below, unchanged, under "Application" |

## Solution at a glance

- **Compute**: the supplied container, unchanged in behaviour, on a
  serverless container platform (Cloud Run) — managed TLS/load balancing,
  revision-based deploys, probe-gated traffic, autoscaling
  (scale-to-zero staging, warm minimum in prod).
- **Persistence**: SQLite retained for dev/CI, replaced in deployed
  environments by managed MySQL 8 with private-IP-only networking,
  automated backups and point-in-time recovery. Justification in the
  architecture doc.
- **Environments**: `staging` and `prod` are fully separate stacks
  (separate VPCs, databases, services, alerts, state), sharing only the
  container registry and CI identity.
- **CI/CD**: test → image build → vulnerability scan (fails on fixable
  CRITICAL/HIGH) → push → migrate + deploy staging → smoke test →
  **manual approval** → migrate + deploy production → smoke test. One-click
  rollback workflow shifts traffic to a previous revision in seconds.
- **Security**: no keys (OIDC federation for CI), generated secrets that
  never touch git or CI variables, least-privilege runtime identity,
  private database, closed-by-default VPC.
- **Observability**: external uptime checks, 5xx and database alerts to a
  notification channel; structured logs on stderr into centralised logging.

### Cloud platform note (read first)

The brief targets **Huawei Cloud**. Within the 48h I actually had, the
account available for real provisioning was Google Cloud, so this solution
is **built and verified on GCP** using only primitives with direct Huawei
equivalents, and every document reasons Huawei-first where the platforms
differ. The full service mapping (CCI/CCE, RDS, SWR, OBS, CSMS, ELB,
Cloud Eye/LTS, IAM agencies) is in the architecture doc; the residency doc
covers Huawei's Lagos local cloud region specifically. The judgement,
module boundaries, pipeline design, and controls are the assessment
deliverable; the provider binding is one module-internal layer.

## Repository structure

```
terraform/
├── modules/
│   ├── network/        VPC, subnet, private-services access, closed firewall
│   ├── database/       Private MySQL, generated credentials → Secret Manager
│   ├── service/        Container service + migrate job + runtime identity
│   ├── observability/  Uptime check + alert policies + notification channel
│   └── stack/          One environment = network + database + service + observability
└── envs/
    ├── shared/         Container registry, CI OIDC federation, deployer SA
    ├── staging/        Thin root: stack module + staging variables
    └── prod/           Thin root: stack module + prod variables
.github/workflows/
├── ci.yml              Supplied app CI (tests, style, docker build) — unchanged
├── terraform.yml       fmt-check, validate, plan (all roots) on terraform changes
├── deploy.yml          test → build/scan/push → staging → smoke → approval → prod
└── rollback.yml        Manual traffic rollback per environment
docs/                   architecture / platform-design / security-data-residency / operations
```

## Prerequisites

- Terraform ≥ 1.9, gcloud CLI authenticated as an operator with project
  owner on the target project, GitHub repository with Actions enabled.
- One-time bootstrap (the only manual provisioning, per the brief's
  bootstrapping allowance):
  1. Create project + link billing.
  2. Enable APIs (run, sqladmin, compute, artifactregistry, secretmanager,
     servicenetworking, iam, iamcredentials, sts, monitoring, logging,
     cloudbuild).
  3. Create the versioned Terraform state bucket
     (`cashonrails-assess-tfstate`, uniform access, public-access
     prevention).
  4. Build the initial bootstrap image (`gcloud builds submit --tag
     <registry>/api:bootstrap .`) — needed once because the service
     resource requires an existing image; CI owns all subsequent images.

## Initialise and deploy

```bash
# 1. Shared infrastructure (registry, CI identity)
terraform -chdir=terraform/envs/shared init
terraform -chdir=terraform/envs/shared apply

# 2. Set the two GitHub Actions variables from the shared outputs
#    WIF_PROVIDER  = workload_identity_provider output
#    DEPLOYER_SA   = deployer_service_account output

# 3. Environments (staging shown; prod is identical)
terraform -chdir=terraform/envs/staging init
terraform -chdir=terraform/envs/staging apply

# 4. First migration + verification
gcloud run jobs execute cor-staging-migrate --region africa-south1 --wait
BASE_URL=$(terraform -chdir=terraform/envs/staging output -raw service_url) ./scripts/smoke-test.sh
```

After that, every push to `main` flows through the pipeline; production
deploys pause for approval on the protected `production` environment.

## Destroy

```bash
terraform -chdir=terraform/envs/prod apply -var db_deletion_protection=false   # lift protection first
terraform -chdir=terraform/envs/prod destroy
terraform -chdir=terraform/envs/staging destroy
terraform -chdir=terraform/envs/shared destroy
# then delete the state bucket and project (manual, deliberate)
```

## Application changes made for deployment

Kept to the minimum the brief allows, all deployment-supporting:

1. **`Dockerfile`**: added `pdo_mysql` to the installed PHP extensions (one
   line) so the container can use managed MySQL. No application code
   changed; SQLite still works everywhere it did.
2. **`.github/workflows/`**: added `terraform.yml`, `deploy.yml`,
   `rollback.yml` alongside the supplied `ci.yml` (untouched).
3. **`terraform/` and `docs/`**: new, additive.

## Assumptions

- Designated customer/transaction data = the application database and
  everything derived from it (backups, DR copies, PII-bearing logs) — 
  reasoning and full classification table in the residency doc.
- The API is public and unauthenticated because the supplied app has no
  auth layer and feature work is out of scope; the edge-hardening path
  (WAF, rate limiting, app-layer auth) is documented.
- Assessment traffic is nominal; sizing favours engineering quality over
  spend, with production sizing documented as variables + notes rather
  than provisioned.

## Known limitations and what I would do next in production

- **Single region, zonal database** — production: HA database
  (`availability_type = REGIONAL`, one variable), plus an in-country DR
  site per the residency constraint.
- **Secrets in Terraform state** — generated secrets exist in the
  (access-controlled, versioned) state; next step is write-only/ephemeral
  secret handling so state never holds plaintext.
- **Same project for staging/prod** — cost-driven for the assessment;
  production would use per-environment projects for blast-radius and
  billing isolation (the per-env state/root layout already assumes this).
- **Terraform applies are operator-run** — next step: plan artifacts on PR
  with policy-as-code checks, applies from a locked-down pipeline on merge.
- **Email alerting** — swap channel to the on-call system; add p95
  latency and DB connection alerts; add SLOs with burn-rate alerts.
- **Queue/cache on the database** — move to managed Redis when volume
  justifies a second stateful dependency.

## Cost

Assessment footprint is a few USD/day dominated by the smallest-tier
database instances; staging compute scales to zero. The cost-driver
analysis and what I would reconsider at scale are in the architecture doc.

---

# Application

The original application documentation follows, unchanged.

A small Laravel REST API for a payment transaction lifecycle assessment
workload. It is intentionally simple: SQLite storage, JSON endpoints,
automated tests, and a production-oriented Docker image.

## Requirements

- PHP 8.3 or newer
- Composer
- Docker, optional for container runs

## Local Setup

```bash
composer install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite
php artisan migrate
php artisan db:seed
```

Run the test suite with:

```bash
php artisan test
```

Check code style with:

```bash
./vendor/bin/pint --test
```

## API

All endpoints are prefixed with `/api/v1`.

| Method | Path | Description |
| --- | --- | --- |
| GET | `/health` | Liveness check |
| GET | `/ready` | Database readiness check |
| POST | `/transactions` | Create a transaction |
| GET | `/transactions` | List paginated transactions |
| GET | `/transactions/{id}` | Retrieve a transaction |
| PATCH | `/transactions/{id}/status` | Update transaction status |
| DELETE | `/transactions/{id}` | Delete a transaction |

Amounts are stored as integer minor units to avoid floating-point
inaccuracies. For example, NGN 1,250.00 is represented as `125000`.

Supported statuses are `pending`, `processing`, `successful`, and `failed`.
Status updates use simple lifecycle rules: `pending` may become
`processing`, and `processing` may become `successful` or `failed`.

An OpenAPI 3.1 specification is available in the repo at `openapi.yaml`
and from a running app at `http://localhost:8080/openapi.yaml`; Swagger UI
at `http://localhost:8080/docs`.

## Docker

Build the image:

```bash
docker build -t cashonrails-assessment-api .
```

Run with docker compose:

```bash
docker compose up --build
```

Smoke-test a running instance:

```bash
BASE_URL=http://127.0.0.1:8080 ./scripts/smoke-test.sh
```
