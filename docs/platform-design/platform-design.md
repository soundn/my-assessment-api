# Platform Design — from one service to a paved road

The Part 1 solution is deliberately structured so that almost none of it is
specific to *this* Laravel API. This document explains how it becomes an
internal platform for Cashonrails' stacks (PHP/Laravel, Go, Java/Spring
Boot, Node.js/Next.js, TypeScript).

## What is already reusable

| Layer | Artifact | Service-specific? |
| --- | --- | --- |
| Terraform `modules/network` | VPC, subnet, private services access, closed firewall | No |
| Terraform `modules/database` | Private MySQL + generated credentials in Secret Manager | No (engine/tier are variables) |
| Terraform `modules/service` | Container service + migration job + runtime identity + secret wiring | Almost none — image, env map, probe paths are variables |
| Terraform `modules/observability` | Uptime, 5xx, DB alerts | No |
| Terraform `modules/stack` | One environment = one module call | The per-service composition point |
| Deploy workflow | test → build → scan → push → staging → smoke → approval → prod | Only the test job and service names |
| Rollback workflow | traffic shift to previous revision | No |
| Runbooks | investigation and recovery procedures | Mostly no |

The platform contract with every service team is what this app already
satisfies:

1. Ship a container listening on `$PORT` (8080), logging JSON to stderr.
2. Expose `GET /health` (liveness) and `GET /ready` (dependency check).
3. Read all configuration from environment variables; secrets arrive as env
   vars sourced from the secret store.
4. Ship migrations as an idempotent one-shot command runnable in a job
   (`php artisan migrate --force`, `migrate` binary, Flyway, etc.).
5. Run stateless — state lives in the database/queue/cache, not on disk.

This contract is **stack-agnostic**: FrankenPHP, a Go binary, Spring Boot,
and Next.js standalone all satisfy it without platform changes.

## The platform engineering question

> A new team joins tomorrow with a Go payment service. How much of your
> existing solution can they reuse, and what do they need to provide?

**They provide four things:**

1. A `Dockerfile` for their service (Go: a ~10-line multi-stage scratch
   build).
2. `/health` and `/ready` endpoints (a few lines of Go).
3. A `stack` module instantiation per environment — copy
   `terraform/envs/staging`, change the service name, CIDRs, and env map:
   ~30 lines of tfvars-level configuration, no new modules.
4. The test job of the deploy workflow swapped from `php artisan test` to
   `go test ./...`, plus their service names in the deploy steps.

**They reuse everything else**: networking pattern, database provisioning
with secret handling, CI/CD skeleton with image scanning and the
staging-gate-production promotion, OIDC deploy identity (add their repo to
the workload identity pool condition), rollback workflow, alert pack, and
runbook structure. Realistic time-to-first-production-deploy: under a day,
most of it their own Dockerfile and probes.

## How I would harden this into a real platform

In priority order, each step compounding the previous:

1. **Publish the modules** — move `terraform/modules/*` to a versioned
   internal module registry (or tagged repo). Teams pin
   `source = "...//stack?ref=v1.2.0"`; the platform team ships fixes by
   releasing versions, teams upgrade on their own schedule. Platform
   versioning = module semver + a documented upgrade path; breaking changes
   get a major bump and a migration note.
2. **Reusable CI** — convert the deploy workflow into a GitHub Actions
   `workflow_call` template with inputs (`service_name`, `test_command`,
   `migrate_args`). A new service's pipeline becomes ~15 lines referencing
   the shared workflow at a pinned tag.
3. **Golden-path template** — a `create-new-service` scaffold (cookiecutter
   or an IDP like Backstage) that generates: Dockerfile for the chosen
   stack, probe stubs, the tfvars files, the 15-line pipeline, an alert
   pack, and a pre-filled runbook. The paved road becomes the default road.
4. **Guardrails as policy, not review comments** — org-level policies
   (resource location restrictions to approved regions, no public IPs on
   databases, no service account key creation, CMEK where mandated) plus
   policy-as-code checks (OPA/conftest or similar) in the Terraform plan
   step, so violations fail CI rather than reach review.
5. **Standardised observability** — the alert pack is already a module;
   add a required structured-log schema (JSON with `service`, `env`,
   `trace_id`) and a per-service dashboard module, so every service lands
   with the same operational surface.
6. **Environment provisioning** — new environments (or per-team sandboxes)
   are new `envs/<name>` roots instantiating `stack` with their own state
   prefix — creating one is a PR, not a ticket. At organisational scale,
   each environment moves to its own project/account for blast-radius and
   billing isolation, which the per-env state layout already anticipates.
7. **Self-service secrets** — teams declare secret *names* in their stack
   call; values are set out-of-band by authorised humans or rotation jobs.
   The platform never accepts secret values through git or CI variables.

## Deployment strategies

The revision model gives every service canary and blue/green semantics for
free: deploy with no traffic, then shift 5% → 50% → 100% (or 0 → 100 for
blue/green) with instant reversal — the rollback workflow is the same
mechanism. The platform default is: staging auto-deploy, production behind
an approval gate, traffic-shifted, with the previous revision retained warm.

## Documentation and runbooks

Each generated service ships with its runbook pre-filled from the template
in `docs/operations/runbooks.md` — investigation sequence, rollback
procedure, restore procedure, and alert meanings, with service-specific
values injected by the scaffold. Platform docs live with the platform
modules; service docs live with the service.
