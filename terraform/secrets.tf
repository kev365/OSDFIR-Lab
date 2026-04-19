# Pre-seed secrets for the osdfir-infrastructure sub-charts.
#
# Purpose:
#   1. Ensure Helm's lookup() succeeds on first enable of a sub-chart (otherwise
#      the chart's secret.yaml errors with nil on the lookup).
#   2. Force static "admin" credentials across the board so the lab is
#      repeatable across tear-down/redeploy cycles. This is a personal test
#      lab (see README disclaimer) — not for production use. Postgres/Redis/
#      ArangoDB are ClusterIP-only (no external exposure), so static creds
#      there carry no meaningful risk in this context.
#
# Timesketch is intentionally NOT pre-seeded here. Its admin user is created
# post-deploy via `tsctl add_user` from scripts/manage-osdfir-lab.ps1 — that
# is more reliable than relying on the chart's lookup() behavior.
#
# Convention used by the osdfir-infrastructure charts:
#   <tool>-user   = admin USERNAME
#   <tool>-secret = admin PASSWORD
#   postgres-user, redis-user, <tool>-arangodb = backend service passwords

locals {
  admin_password = "admin"
}

# ---------- Yeti secret ----------

resource "kubernetes_secret" "yeti_seed" {
  metadata {
    name      = "${var.helm_release_name}-yeti-secret"
    namespace = kubernetes_namespace.osdfir.metadata[0].name

    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }

    annotations = {
      "meta.helm.sh/release-name"      = var.helm_release_name
      "meta.helm.sh/release-namespace" = var.namespace
    }
  }

  data = {
    "yeti-user"     = local.admin_password
    "yeti-secret"   = local.admin_password
    "yeti-arangodb" = local.admin_password
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }

  depends_on = [kubernetes_namespace.osdfir]
}

# ---------- HashR PostgreSQL secret ----------

resource "kubernetes_secret" "hashr_postgres_seed" {
  metadata {
    name      = "${var.helm_release_name}-hashr-secret"
    namespace = kubernetes_namespace.osdfir.metadata[0].name

    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }

    annotations = {
      "meta.helm.sh/release-name"      = var.helm_release_name
      "meta.helm.sh/release-namespace" = var.namespace
    }
  }

  data = {
    "postgres-user" = local.admin_password
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }

  depends_on = [kubernetes_namespace.osdfir]
}

# OpenRelik's secret is no longer pre-seeded here. The chart generates its own
# backend credentials on install. The admin/admin UI login is created after
# pods are ready by Set-OpenRelikAdmin in scripts/manage-osdfir-lab.ps1 using
# `python admin.py create-user admin --password admin --admin`, mirroring the
# tsctl-based approach used for Timesketch.
