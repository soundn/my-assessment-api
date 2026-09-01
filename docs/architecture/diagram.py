#!/usr/bin/env python3
"""Architecture diagram (diagram-as-code).

Regenerate with:
    pip install diagrams && brew install graphviz   # or apt-get install graphviz
    python docs/architecture/diagram.py
Outputs docs/architecture/architecture.png. The app-page.png thumbnail is a
screenshot of the deployed service's root page.
"""

import os

from diagrams import Cluster, Diagram, Edge
from diagrams.custom import Custom
from diagrams.gcp.compute import Run
from diagrams.gcp.database import SQL
from diagrams.gcp.devtools import ContainerRegistry
from diagrams.gcp.network import LoadBalancing
from diagrams.gcp.operations import Logging, Monitoring
from diagrams.gcp.security import Iam, SecretManager
from diagrams.gcp.storage import GCS
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github

os.chdir(os.path.dirname(os.path.abspath(__file__)))

graph_attr = {
    "fontsize": "20",
    "pad": "0.4",
    "splines": "spline",
    "nodesep": "0.5",
    "ranksep": "0.85",
}


def environment(env_name, service_name, host):
    """One deployed environment: ingress, service, migrate job, secrets, DB."""
    with Cluster(env_name):
        page = Custom(
            f"{host}\n(live)",
            "./app-page.png",
            width="2.9",
            height="1.85",
            imagescale="true",
        )
        ingress = LoadBalancing("Managed HTTPS\ningress + TLS")
        api = Run(f"Cloud Run service\n{service_name}")
        migrate = Run(f"Cloud Run job\n{service_name}-migrate")
        secrets = SecretManager("Secret Manager\nAPP_KEY, DB password")

        with Cluster("Private VPC (deny-all ingress)"):
            db = SQL("Cloud SQL MySQL 8\nprivate IP only\nbackups + PITR")

        ingress >> api
        api >> Edge(label="private\negress only") >> db
        migrate >> Edge(style="dashed") >> db
        secrets >> Edge(style="dashed", label="env at\nboot") >> api
        secrets >> Edge(style="dashed") >> migrate
        api >> Edge(style="dotted", label="serves") >> page

    return ingress, api


with Diagram(
    "CashOnRails Assessment API — Production Architecture",
    filename="architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    clients = Users("API clients")

    with Cluster("GitHub"):
        gh = Github("Repository\n+ Actions CI/CD")

    with Cluster("Google Cloud — project cashonrails-live (africa-south1)"):
        with Cluster("Shared services"):
            wif = Iam("Workload Identity\nFederation (OIDC)")
            registry = ContainerRegistry("Artifact Registry\ncontainer images")
            state = GCS("GCS (versioned)\nTerraform state")

        with Cluster("Observability (per environment)"):
            mon = Monitoring("Uptime, 5xx,\ndisk alerts")
            logs = Logging("Structured logs\n(stderr)")

        stg_ingress, stg_api = environment(
            "Staging", "cor-staging", "cor-staging-…run.app"
        )
        prd_ingress, prd_api = environment(
            "Production", "cor-prod", "cor-prod-…run.app"
        )

    # Client traffic
    clients >> Edge(label="HTTPS") >> stg_ingress
    clients >> Edge(label="HTTPS") >> prd_ingress

    # CI/CD — keyless via OIDC; production only after the human gate
    gh >> Edge(label="OIDC token\nexchange") >> wif
    gh >> Edge(label="build, scan,\npush") >> registry
    gh >> Edge(style="dashed", label="terraform\nplan") >> state
    gh >> Edge(label="1. migrate, deploy,\nsmoke test") >> stg_api
    gh >> Edge(
        color="firebrick",
        style="bold",
        label="2. manual approval →\nmigrate, deploy, smoke test",
    ) >> prd_api

    # Monitoring probes both environments from outside
    mon >> Edge(style="dotted", label="uptime\nprobe") >> stg_ingress
    mon >> Edge(style="dotted", label="uptime\nprobe") >> prd_ingress
