# Pre-seed secrets for sub-charts that use Helm's lookup() function.
#
# When a sub-chart (Yeti, HashR) is enabled for the first time on an existing
# Helm release, the chart's secret.yaml treats it as an "upgrade" and tries to
# look up an existing secret. If that secret doesn't exist yet the lookup
# returns nil and the template fails. Creating the secrets here, before the
# Helm release runs, ensures the lookup always succeeds.
#
# Terraform's lifecycle ignore_changes prevents these from being overwritten
# once the Helm chart takes ownership of the secret values.

# ---------- random credentials ----------

resource "random_password" "yeti_user" {
  length  = 32
  special = false
}

resource "random_password" "yeti_arangodb" {
  length  = 16
  special = false
}

resource "random_password" "yeti_secret" {
  length  = 32
  special = false
}

resource "random_password" "hashr_postgres" {
  length  = 16
  special = false
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
    "yeti-user"     = random_password.yeti_user.result
    "yeti-arangodb" = random_password.yeti_arangodb.result
    "yeti-secret"   = random_password.yeti_secret.result
  }

  lifecycle {
    ignore_changes = [data, metadata[0].labels, metadata[0].annotations]
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
    "postgres-user" = random_password.hashr_postgres.result
  }

  lifecycle {
    ignore_changes = [data, metadata[0].labels, metadata[0].annotations]
  }

  depends_on = [kubernetes_namespace.osdfir]
}
