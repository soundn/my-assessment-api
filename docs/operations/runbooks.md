# Reliability and Production Operations

## Recovery objectives

| Objective | Target | Basis |
| --- | --- | --- |
| RPO (data loss) | ≤ 5 minutes | Daily automated backups + binary-log point-in-time recovery; transaction log retention 7 days |
| RTO (service restore) | ≤ 30 minutes single-component failure; ≤ 2h database rebuild | Stateless compute redeploys in minutes; PITR restore dominates the worst case |

These are assessment assumptions for a payments API: losing minutes of
transaction records is painful but reconcilable against processor records;
losing hours is not. Tighter RPO (~0) requires the HA/failover
configuration (`availability_type = REGIONAL`, one variable) plus
synchronous replication, which doubles database cost — a business decision,
documented rather than defaulted.

## Failure modes and responses

### Service failure (container crashes, wedged instances)

Detected by: liveness probe restarts; uptime alert if user-facing.
The platform restarts failed instances automatically; multiple instances
(prod `min_instances = 1`, autoscaling) keep serving during restarts.
Operator action is only needed if crash-looping — see incident sequence.

### Infrastructure failure (zone/platform degradation)

Compute is regional and rescheduled automatically. The database in
assessment sizing is `ZONAL` — a zone outage means restoring from backup
(RTO ≤ 2h) or flipping to `REGIONAL` HA in production sizing, which fails
over automatically in ~60s with no data loss.

### Database failure

- **Instance down / unreachable**: `/api/v1/ready` starts returning 503;
  new revisions stop receiving traffic; uptime + 5xx alerts fire. Check
  Cloud SQL status and operations; if the instance is unrecoverable,
  restore (below).
- **Data corruption / bad migration data-loss**: point-in-time restore to
  just before the event (see backup restoration).

### Increased traffic

Request-based autoscaling adds instances up to `max_instances` with no
operator action; the database is the fixed-capacity component — watch
connection count and CPU. Mitigations in order: raise `max_instances`
(Terraform variable), scale the DB tier (variable, brief restart), add a
cache layer for read pressure. Sustained 10× growth: managed Redis for
cache/sessions and DB read replicas.

### Failed application deployment

The pipeline is designed so most bad deploys never reach users: tests gate
the build, staging deploys before production, smoke tests gate promotion,
production requires human approval, and a new revision only receives
traffic after its startup probe passes (a container that can't reach the
DB or boot never serves a request).

If a bad revision does go live (logic bug, latency regression):

```
Actions → Rollback → environment: production → run
```

Traffic shifts to the previous revision in seconds (revisions are
immutable and retained). Roll back **before** diagnosing. If the deploy
included a migration, note that migrations are expand/contract by policy:
schema changes must be backward-compatible one release back, so the
previous revision keeps working against the migrated schema.

### Backup restoration

1. Identify target time (last known-good, from logs/alert timeline).
2. Restore the instance to a **new** instance at that timestamp (PITR from
   automated backup + binary logs) — never restore over the primary while
   diagnosing.
3. Verify restored data (row counts, latest transactions).
4. Repoint the service: update `db_host` (Terraform variable → apply, or
   emergency env-var update on the service) and redeploy.
5. Post-incident: reconcile the delta between restore point and incident
   time against external processor records.

Backup restoration is rehearsed, not assumed: the procedure above was
exercised during the assessment (restore-to-new-instance, verify, discard).

### Disaster recovery (region loss)

Assessment scope: single region, accepted and documented. Production path:
infrastructure is fully re-creatable from this repo (`terraform apply` in
a second region + image re-push + backup restore), giving a cold-standby
RTO of hours. Warm standby (cross-region read replica + pre-provisioned
stack) buys minutes-level RTO at roughly double infrastructure cost.
**Residency constraint**: for designated Nigerian payment data, the DR
copy must also remain in-country — the second site is a second Nigerian
facility, not another country's region (see
`docs/security-data-residency/security-data-residency.md`).

## Incident detection and alerting

| Signal | Source | Meaning |
| --- | --- | --- |
| Health uptime alert | 60s external probe on `/api/v1/health` | Service down or unreachable — page |
| Elevated 5xx alert | Request metrics | Users are seeing errors — page |
| SQL disk > 80% | Database metrics | Capacity runway shrinking — act today |
| (extend) latency p95, SQL CPU/memory/connections | Same pipeline | Added per-service as the platform grows |

Alerts notify by email in the assessment (an on-call pager/Slack webhook is
a one-line channel change in the observability module).

## Incident investigation sequence

1. **Scope** — uptime alert alone (total outage) vs 5xx alert (partial)?
   Staging affected too (shared-cause) or prod only (deploy-correlated)?
2. **Recent change?** — check the deploy history (Actions runs / revision
   list). If the incident correlates with a deploy: **roll back first**,
   diagnose second.
3. **Logs** — filter service logs to severity ≥ ERROR around onset;
   Laravel exceptions arrive structured on stderr.
4. **Dependency health** — `/api/v1/ready` 503 = database path: Cloud SQL
   status, connections, CPU, storage; recent maintenance events.
5. **Saturation** — instance count at `max_instances`? DB connections at
   limit? Memory OOM kills in container logs?
6. **Communicate** — one owner drives; post status at detection,
   mitigation, and resolution; timestamp every action for the postmortem.
7. **Afterwards** — blameless postmortem: timeline, root cause, corrective
   actions with owners (each becomes a tracked issue: missing alert, missing
   guardrail, runbook gap).

## Operational cadence

- Weekly: review alert noise (every alert actionable or deleted), backup
  success, disk/cost runway.
- Monthly: restore rehearsal into a scratch instance; dependency and image
  base updates (Trivy gates regressions).
- Quarterly: game-day on one failure mode from this document.
