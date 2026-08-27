#!/usr/bin/env python3
"""Architecture diagram (diagram-as-code).

Regenerate with:
    pip install diagrams && brew install graphviz   # or apt-get install graphviz
    python docs/architecture/diagram.py
Outputs docs/architecture/architecture.png
"""

import os

from diagrams import Cluster, Diagram, Edge
from diagrams.gcp.compute import Run
from diagrams.gcp.database import SQL
from diagrams.gcp.devtools import ContainerRegistry
from diagrams.gcp.network import FirewallRules, LoadBalancing
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
    "nodesep": "0.55",
    "ranksep": "0.9",
}

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

    with Cluster("Google Cloud — project cashonrails-assess (africa-south1)"):
        with Cluster("Shared services"):
            registry = ContainerRegistry("Artifact Registry\ncontainer images")
            state = GCS("GCS (versioned)\nTerraform state")
            wif = Iam("Workload Identity\nFederation (OIDC)")

        with Cluster("Per environment — staging & production (identical stacks)"):
            ingress = LoadBalancing("Managed HTTPS\ningress + TLS")
            api = Run("Cloud Run service\nLaravel API container")
            migrate = Run("Cloud Run job\nphp artisan migrate")
            secrets = SecretManager("Secret Manager\nAPP_KEY, DB password")

            with Cluster("Private VPC (deny-all ingress)"):
                fw = FirewallRules("VPC firewall")
                db = SQL("Cloud SQL MySQL 8\nprivate IP only\nbackups + PITR")

            with Cluster("Observability"):
                mon = Monitoring("Uptime, 5xx,\ndisk alerts")
                logs = Logging("Structured logs\n(stderr)")

    # Traffic path
    clients >> Edge(label="HTTPS", minlen="2") >> ingress >> api
    api >> Edge(label="private egress\nonly") >> db
    migrate >> Edge(style="dashed") >> db

    # Secrets at boot
    secrets >> Edge(style="dashed", label="env at boot") >> api
    secrets >> Edge(style="dashed") >> migrate

    # CI/CD path — keyless
    gh >> Edge(label="OIDC token\nexchange") >> wif
    gh >> Edge(label="build, scan,\npush") >> registry
    gh >> Edge(label="migrate, deploy,\nsmoke test") >> api
    gh >> Edge(style="dashed", label="terraform\nplan/apply") >> state

    # Observability
    mon >> Edge(style="dotted", label="uptime probe") >> ingress
    api >> Edge(style="dotted") >> logs
