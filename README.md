# Flyte 2 on Amazon EKS — AWS Marketplace

Turnkey, production deployment of **Flyte 2** on Amazon EKS, published to AWS
Marketplace. One CloudFormation stack provisions the full stack and installs
the Flyte backend as an **Amazon EKS add-on**.

```
┌──────────────────────────────────────────────────────────────────┐
│  Artifact B — CloudFormation full-stack product (cloudformation/) │
│                                                                    │
│   VPC ─► EKS cluster ─► managed nodegroup                          │
│    ├─ Aurora Serverless v2 (PostgreSQL, scale-to-zero)             │
│    ├─ S3 bucket (Flyte metadata + user data)                       │
│    ├─ IAM role + AWS::EKS::PodIdentityAssociation ──────► S3        │
│    ├─ Cognito + ALB + ACM + Route 53 (OAuth2 auth, HTTPS)          │
│    └─ Flyte install  ─── resolver picks one of: ───────────────┐   │
│         • AWS::EKS::Addon        (Artifact A, when published)   │   │
│         • helm install fallback  (same chart, unpublished dev)  │   │
└────────────────────────────────────────────────────────────────┼───┘
                                                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  Artifact A — Flyte EKS add-on (addon/)                            │
│   flyte-binary v2 chart + images → Marketplace ECR                 │
│   configurationSchema exposes: database, S3, pod-identity, ingress │
└──────────────────────────────────────────────────────────────────┘
```

## Why two artifacts

An EKS add-on can only deploy **in-cluster** Kubernetes resources — it cannot
provision Aurora, S3, or IAM. So the external AWS resources are provisioned by
CloudFormation, and Flyte itself ships as an add-on that CloudFormation invokes
with the infra outputs (`AWS::EKS::Addon` `ConfigurationValues`).

## Dual-mode install (build once, run before publishing)

The add-on is the end state, but you must be able to validate unpublished
changes immediately. The **resolver** ([scripts/resolve-install.sh](scripts/resolve-install.sh))
decides at deploy time:

| Condition | Install path |
|---|---|
| Required `ADDON_VERSION` is live in the EKS add-on catalog for this account/region | `AWS::EKS::Addon` |
| Not yet published (dev / pre-review) | `helm install` of the **same** pinned chart + **same** rendered values |

Both paths render values from one template ([addon/values/flyte-values.yaml.tpl](addon/values/flyte-values.yaml.tpl))
and one schema ([addon/addon-configuration-schema.json](addon/addon-configuration-schema.json)),
so they stay equivalent.

## Layout

| Path | Purpose |
|---|---|
| [versions.env](versions.env) | Single source of truth for pinned versions |
| [addon/](addon/) | Artifact A — the Flyte EKS add-on package |
| [cloudformation/](cloudformation/) | Artifact B — full-stack template (Phase 2) |
| [scripts/](scripts/) | vendor / render / resolve / build / validate |
| [.buildkite/](.buildkite/) | CI: build + publish add-on, deploy test (Phase 3) |

## Deploying (before Marketplace publish)

```bash
# dev mode (no domain/auth; access via kubectl port-forward)
STAGING_BUCKET=my-cfn-staging AWS_REGION=us-east-1 scripts/deploy.sh flyte-dev

# prod mode (Cognito + ALB + ACM + Route 53)
STAGING_BUCKET=my-cfn-staging AWS_REGION=us-east-1 scripts/deploy.sh flyte-prod \
  DomainName=example.com HostedZoneId=Z123 CognitoDomainPrefix=my-flyte
```

`root.yaml` provisions VPC → EKS → Aurora/S3/IAM, then a CodeBuild-run
[bootstrap](scripts/bootstrap.sh) installs Flyte through the resolver (helm
today, add-on once published). See [MARKETPLACE.md](MARKETPLACE.md).

## Status

- [x] Phase 1 — add-on package: vendoring, values template, config schema, resolver (offline-validated)
- [x] Phase 2 — CloudFormation full-stack (network/eks/data/iam/auth/flyte + bootstrap); cfn-lint + shellcheck clean, **not yet deployed live**
- [ ] Phase 3 — BuildKite pipeline + Marketplace onboarding (Conformitron)
- [ ] Phase 4 — docs + end-to-end smoke harness

See [MARKETPLACE.md](MARKETPLACE.md) for the listing/publishing details.
