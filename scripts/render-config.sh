#!/usr/bin/env bash
# Render the per-deployment add-on configuration document from simple inputs.
#
# This is the ONE place that maps friendly inputs -> the nested flyte-binary
# configurationValues shape. Its output is consumed identically by BOTH install
# paths (see resolve-install.sh):
#   * add-on path : passed to `aws eks create-addon --configuration-values`
#   * helm path   : passed to `helm install -f`
# so the two paths install byte-equivalent config.
#
# Inputs are environment variables (CloudFormation passes these through, or set
# them by hand for local dev). Output: a YAML document on stdout.
#
# Required:
#   DB_HOST         Aurora writer endpoint
#   S3_BUCKET       provisioned bucket name (used for both metadata + user data)
#   AWS_REGION      region of the bucket/cluster
# Optional:
#   DB_PORT         (default 5432)
#   DB_NAME         (default flyte)
#   DB_USER         (default flyte)
#   DB_PASSWORD_PATH(default /etc/db/secret/password)
#   INGRESS_HOST    if set, enables ALB ingress at this host (prod mode)
set -euo pipefail

: "${DB_HOST:?DB_HOST is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${AWS_REGION:?AWS_REGION is required}"

DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-flyte}"
DB_USER="${DB_USER:-flyte}"
DB_PASSWORD_PATH="${DB_PASSWORD_PATH:-/etc/db/secret/password}"

cat <<YAML
flyte-binary:
  flyte-core-components:
    runs:
      storagePrefix: "s3://${S3_BUCKET}"
  configuration:
    database:
      postgres:
        host: "${DB_HOST}"
        port: ${DB_PORT}
        dbname: "${DB_NAME}"
        username: "${DB_USER}"
        passwordPath: "${DB_PASSWORD_PATH}"
    storage:
      metadataContainer: "${S3_BUCKET}"
      providerConfig:
        s3:
          region: "${AWS_REGION}"
          authType: iam
YAML

if [[ -n "${INGRESS_HOST:-}" ]]; then
cat <<YAML
  ingress:
    create: true
    host: "${INGRESS_HOST}"
YAML
  # ALB ingress annotations (prod mode). Emitted here so the config has exactly
  # one `ingress:` key — helm's YAML->JSON rejects duplicate mapping keys.
  if [[ -n "${CERT_ARN:-}" ]]; then
cat <<YAML
    commonAnnotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: "${CERT_ARN}"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      # flyte-binary v2 serves a gRPC/Connect endpoint on the http port; GET / is
      # 404, so the ALB health check must target the dedicated /healthz (200 OK).
      alb.ingress.kubernetes.io/healthcheck-path: /healthz
      alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
      alb.ingress.kubernetes.io/success-codes: "200"
YAML
  fi
fi
