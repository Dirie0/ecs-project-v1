# ecs-project-v1

Infrastructure-as-code and CI/CD for deploying **[Gatus](https://gatus.io)** (a health/uptime
dashboard) to **AWS ECS Fargate** across `dev`, `staging`, and `prod` environments.

Everything is driven by **Terraform** (for the AWS infrastructure) and **GitHub Actions**
(for building the container image and running the deployments). Authentication to AWS is done
entirely through **GitHub OIDC** — there are no long-lived AWS keys stored in the repo.

---

## Table of contents

- [Architecture at a glance](#architecture-at-a-glance)
- [Architectural decisions](#architectural-decisions)
- [Repository layout](#repository-layout)
- [The application container (`gatus/`)](#the-application-container-gatus)
- [Terraform](#terraform)
  - [Layer 0 — `bootstrap-state`](#layer-0--bootstrap-state)
  - [Layer 1 — `bootstrap`](#layer-1--bootstrap)
    - [Bootstrap modules](#bootstrap-modules)
  - [Layer 2 — `environments/*`](#layer-2--environments)
  - [Reusable modules](#reusable-modules)
- [Tagging & cost allocation](#tagging--cost-allocation)
- [GitHub Actions workflows](#github-actions-workflows)
  - [`docker-build.yaml` — build & push](#docker-buildyaml--build--push)
  - [`ecs-deploy.yaml` — deploy](#ecs-deployyaml--deploy)
  - [`ecs-teardown.yaml` — teardown](#ecs-teardownyaml--teardown)
- [End-to-end flow](#end-to-end-flow)
- [Configuration reference](#configuration-reference)
- [Possible improvements](#possible-improvements)

---

## Architecture at a glance

```
                          GitHub Actions (OIDC, no static keys)
                                        │
        ┌───────────────────────────────┼──────────────────────────────┐
        │ push → main                    │ workflow_dispatch             │
        ▼                                ▼                               ▼
  docker-build.yaml                 ecs-deploy.yaml              ecs-teardown.yaml
  build ARM64 image                 terraform plan/apply          terraform destroy
  scan (Grype) → push ECR           (per environment)             (per environment)

──────────────────────────────────────── AWS ────────────────────────────────────────

     Route 53  ──▶  ACM (DNS-validated cert)
        │
        ▼
   Internet ──▶ ALB (:80 → :443 redirect, :443 → target group)
                        │  (public subnets)
                        ▼
                ECS Fargate service (private subnets, ARM64)
                        │  pulls image from
                        ▼
                     ECR  ◀── image pushed by docker-build.yaml
                        │  logs to
                        ▼
                  CloudWatch Logs (30-day retention)
```

- **Region:** `us-east-1`
- **Project name:** `gatus`
- **Container platform:** ECS Fargate, **ARM64**, container port **8080**
- **Ingress:** Public ALB, HTTP redirected to HTTPS, TLS terminated at the ALB with an ACM certificate
- **Egress:** Tasks run in private subnets and reach the internet via NAT gateways

---

## Architectural decisions

This section explains **why** the project is structured the way it is — the trade-offs behind the
CI/CD model, the IAM boundaries, and the Terraform layout.

### Assumptions this design is built on

The decisions below only make sense given a few explicit assumptions. If your situation differs,
some of the trade-offs should be revisited.

- **The application itself is not actively developed here.** Gatus is a vendored upstream app; within
  this repo we own only the `Dockerfile` and `config.yaml` (see [The application container](#the-application-container-gatus)).
  There is no Go build/test cycle, no feature work, and no app-level release cadence to model in CI.
  The pipeline is therefore optimised for *shipping and operating a fixed application*, not for
  developing one.
- **The multiple environments exist primarily to exercise the *infrastructure*, not divergent app
  versions.** `dev`, `staging`, and `prod` run the *same* container image; what differs between them
  is the Terraform (sizing, domains, CIDRs, state isolation, IAM boundaries). The multi-environment
  layout is a way to develop and validate **Terraform changes** safely on the way to prod — it is not
  a vehicle for running different builds of the app in each stage. Environment promotion is about
  gaining confidence in *infrastructure* changes, with the image held constant.
- **A single AWS account is assumed.** Isolation between environments is enforced with IAM/OIDC
  boundaries and separate state buckets rather than separate accounts. This is a deliberate
  simplification (see [Possible improvements](#possible-improvements) for the multi-account option).

### Trunk-based development — everything ships from `main`

All changes flow through a single long-lived branch (`main`), and a push to `main` is what triggers
the image build (`docker-build.yaml`).

- **Why:** it keeps the mental model simple, avoids long-lived divergent branches, and gives one
  unambiguous source of truth for "what is the latest artifact." Every commit on `main` produces an
  immutable, SHA-tagged image in ECR.
- **Deploys stay a deliberate, manual step.** Building on push does *not* deploy — deployment is a
  separate `workflow_dispatch`. This gives trunk-based development's fast integration **without**
  auto-shipping every commit to production. You choose *which* commit's image goes to *which*
  environment, and *when*.
- **Traceability:** because images are tagged by `github.sha`, any running task can be traced back
  to the exact commit, and the deploy step refuses to run unless that image already exists in ECR.

### A `shared` GitHub environment for the ECR build/push

Image builds run under a dedicated GitHub environment called **`shared`**, which owns the
`AWS_DEPLOY_ECR_ROLE_ARN` (the ECR push role).

- **Why:** the container image is **environment-agnostic** — the *same* artifact is promoted through
  dev → staging → prod. Building it under a per-environment identity would be misleading and would
  force the build to pick an environment it doesn't actually belong to.
- **Least privilege:** the `shared` role can *only* authenticate to ECR and push/pull the repo
  (see the `ecr-deployment-role` module). It has **no** permission to touch VPCs, ECS, IAM, or
  state — so a compromised build pipeline cannot mutate infrastructure.
- The OIDC trust for this role is scoped to `repo:<repo>:environment:shared`, so only jobs running
  in the `shared` environment can assume it.

### Separate deploy identity per environment (deploy *and* teardown share it)

Each environment (`dev`, `staging`, `prod`) has its **own** deploy role, exposed to Actions as the
`AWS_DEPLOY_ROLE_ARN` secret **inside that environment**. Both the deploy and teardown workflows
assume this same per-environment role.

- **Why per environment:** OIDC trust is locked to `repo:<repo>:environment:<env>`, so the prod role
  can *only* be assumed by a job running in the prod GitHub environment. A misconfigured or
  malicious dev run physically cannot obtain prod credentials — the blast radius of any single
  environment is contained to itself, including its own state bucket.
- **Why deploy and teardown share one role:** both operations act on the *same* set of resources in
  the *same* account/environment; `terraform apply` and `terraform destroy` require essentially the
  same permissions. Splitting them would add IAM surface without adding a real security boundary.
  The meaningful guardrail on teardown is instead a **typed confirmation** (`confirm` must equal the
  environment name) plus GitHub environment protection rules.
- This is why `AWS_DEPLOY_ROLE_ARN` is a **secret** (a different ARN in each environment) rather
  than a repo-wide value — the value is intentionally different per environment.

### Dedicated environment directories, *not* Terraform workspaces

`dev`, `staging`, and `prod` are **separate root modules** under `terraform/environments/`, each
with its own backend, rather than a single root selected by `terraform workspace`.

- **Isolated state per environment:** each environment writes to its own bucket
  (`gatus-terraform-state-<env>`). Workspaces would keep all environments as keys inside one bucket
  — a single backend blast radius and easier to accidentally target the wrong workspace.
- **Explicit and greppable:** the environment is visible in the directory path, the backend config,
  and the CI `working-directory`. `terraform plan` in `environments/prod` can only ever mean prod.
  With workspaces the "current" environment is invisible, ambient CLI state (`terraform workspace
  select`) — a common source of "applied to the wrong env" incidents.
- **Divergence is safe:** if one environment later needs to differ (extra resource, different
  sizing), it's a local edit to that directory. Workspaces assume every environment shares
  *identical* configuration, so any drift has to be smuggled in through conditional expressions.
- **Cost of the choice:** the root modules are near-duplicates today. That duplication is
  deliberately accepted in exchange for isolation and clarity, and the shared logic already lives in
  `terraform/modules/*`, so the roots stay thin (just module wiring + backend + variables).

### Layered bootstrap (state → shared → environments)

Terraform is split into three layers applied in order (see [Terraform](#terraform)) to solve the
"where does the state bucket's own state live?" problem: `bootstrap-state` creates the state bucket
using a **local** backend, `bootstrap` provisions shared account-level resources (OIDC, ECR, per-env
state buckets, roles), and only then do the per-environment roots run against their own remote
state. Rarely-changed shared plumbing is thus separated from frequently-changed app infrastructure.

---

## Repository layout

```
.
├── gatus/                     # Vendored Gatus app — we only own the Dockerfile + config.yaml here
│   ├── Dockerfile
│   └── config.yaml
├── terraform/
│   ├── bootstrap-state/       # Layer 0: creates the S3 bucket that stores bootstrap state
│   ├── bootstrap/             # Layer 1: OIDC, ECR, per-env state buckets, deploy roles
│   ├── environments/          # Layer 2: the actual per-environment infrastructure
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── modules/               # Reusable building blocks (vpc, alb, ecs, iam, …)
├── .github/workflows/         # CI/CD pipelines
│   ├── docker-build.yaml
│   ├── ecs-deploy.yaml
│   └── ecs-teardown.yaml
└── screenshots/
```

---

## The application container (`gatus/`)

The `gatus/` directory is an upstream copy of the [Gatus](https://github.com/TwiN/gatus) health
dashboard. **Within this repo we only maintain two files there** — the `Dockerfile` and
`config.yaml`. The Go source code is upstream's and is not documented here.

### `gatus/Dockerfile`

A small, secure, multi-stage build:

| Stage | Base image | What happens |
|-------|-----------|--------------|
| **builder** | `golang:1.26-alpine` | Downloads Go modules, then compiles a fully static binary (`CGO_ENABLED=0`, `GOOS=linux`, `GOARCH=arm64`). |
| **runtime** | `gcr.io/distroless/static-debian13:nonroot` | Copies just the `gatus` binary and `config.yaml`. Runs as the non-root user. |

Key properties:

- **Distroless + non-root** → minimal attack surface (no shell, no package manager in the final image).
- **ARM64** → matches the Fargate `runtime_platform` (`ARM64`) defined in the ECS module.
- Config is baked in at `/config/config.yaml` and pointed to via `ENV GATUS_CONFIG_PATH`.
- **Exposes port `8080`**, which the ALB target group and ECS security group both expect.

### `gatus/config.yaml`

Defines the endpoints Gatus monitors and the conditions each must satisfy (status code, body,
response time, certificate/domain expiration, DNS, ICMP, etc.). This is a starter configuration
using placeholder URLs (`example.org`, `twin.sh`) and should be edited to point at your real
services. All checks currently run on a 1–60 minute interval.

---

## Terraform

Terraform is split into **three layers** that must be applied in order. This solves the classic
"where does the state bucket's state live?" chicken-and-egg problem and separates rarely-changed
shared resources from per-environment infrastructure.

```
bootstrap-state   →   bootstrap   →   environments/{dev,staging,prod}
(local state)         (S3 state)      (S3 state, one bucket per env)
```

Provider: `hashicorp/aws` `6.50.0`, Terraform `~> 1.14.9`.

### Layer 0 — `bootstrap-state`

**Purpose:** create the single S3 bucket that stores the `bootstrap` layer's state.

- Uses a **local backend** (`backend.tf` → `backend "local"`) because no remote bucket exists yet.
- Creates `gatus-bootstrap-state` with **versioning**, **AES256 encryption**, **full public-access
  block**, and `prevent_destroy = true`.

Run this **once, first**, by hand.

### Layer 1 — `bootstrap`

**Purpose:** shared, account-level resources used by every environment. Stores its state in
`gatus-bootstrap-state` (created in Layer 0).

| Module | What it creates |
|--------|-----------------|
| `oidc` | The GitHub Actions **OIDC identity provider** (`token.actions.githubusercontent.com`). |
| `ecr` | The **ECR repository** (`gatus`) with scan-on-push and a lifecycle rule keeping the last 10 images. |
| `state_buckets` | One **Terraform state bucket per environment** (`gatus-terraform-state-{dev,staging,prod}`), versioned + encrypted + private, `prevent_destroy`. |
| `deployment_roles` | One **deploy IAM role per environment**, assumable only via OIDC from `repo:<repo>:environment:<env>`. Grants the app-service permissions (ecs/ecr/elb/acm/ec2/logs/route53), scoped IAM PassRole for the task roles, and access to the relevant state buckets. |
| `ecr_deployment_role` | A dedicated **ECR push role**, assumable via OIDC from `environment:shared`, limited to ECR auth + push/pull on the repo. |

Configured via `bootstrap/terraform.tfvars`:

```hcl
aws_region   = "us-east-1"
project_name = "gatus"
github_repo  = "Dirie0/ecs-project-v1"
environments = ["dev", "staging", "prod"]
```

The role ARNs and repository URL produced here are consumed by the workflows (as GitHub
secrets/vars) and by the environment layer (via remote state).

#### Bootstrap modules

The `bootstrap` root is thin — it just wires together five small, single-responsibility modules
under `bootstrap/modules/`. `main.tf` instantiates them, using `for_each` over
`var.environments` for the two per-environment ones.

| Module | Instantiated | Responsibility |
|--------|--------------|----------------|
| **`oidc`** | once | Creates the single **GitHub Actions OIDC identity provider** (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`). Its ARN is passed into both role modules so they can be assumed from GitHub with no static keys. |
| **`ecr`** | once | The **ECR repository** (named `var.project_name` = `gatus`) with `scan_on_push = true` and a lifecycle rule expiring all but the **last 10 images**. Tag mutability is currently `MUTABLE`. Exports `repository_arn` (consumed by `ecr-deployment-role`). |
| **`s3`** | per environment | One **remote-state bucket per env** (`gatus-terraform-state-<env>`) with **versioning**, **AES256 encryption**, a **full public-access block**, and `prevent_destroy = true`. |
| **`deployment-role`** | per environment | The **per-environment deploy role** (`gatus-<env>-deploy-role`). Trust policy is locked to `repo:<repo>:environment:<env>` via the OIDC `sub` claim, so e.g. the prod role can only be assumed by a job running in the `prod` GitHub environment. Its inline policy has three statements — see below. |
| **`ecr-deployment-role`** | once | The **ECR push role** (`gatus-ecr-push-role`). Trust is scoped to `environment:shared`. Its permissions are a minimal two statements: `ecr:GetAuthorizationToken` on `*` (this action requires `*` — it is not resource-scoped by AWS) and a push/pull set (`BatchCheckLayerAvailability`, `PutImage`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `BatchGetImage`, `DescribeImages`) scoped to **just the `gatus` repository ARN**. |

**Inside the `deployment-role` policy** (`bootstrap/modules/deployment-role/main.tf`) there are three statements:

| Sid | Actions | Resources | Notes |
|-----|---------|-----------|-------|
| `AppServices` | `ecs:*`, `ecr:*`, `elasticloadbalancing:*`, `acm:*`, `ec2:*`, `logs:*`, `route53:*`, `route53domains:*` | `*` | Broad, wildcard service access — the main candidate for tightening (see [Possible improvements](#possible-improvements)). |
| `PassRoleScoped` | `iam:*Role*` management + `iam:PassRole` | **Only** `arn:aws:iam::*:role/<env>-ecs-task-execution-role` and `.../<env>-ecs-task-role` | IAM is deliberately *not* wildcarded — the role can only manage/pass the two ECS task roles for its own environment. |
| `StateBackend` | `s3:GetObject`, `s3:PutObject`, `s3:ListBucket`, `s3:DeleteObject` | This env's state bucket + the shared bootstrap-state bucket | Lets the workflow read/write remote state, and read bootstrap outputs. |

> Note the asymmetry: IAM and S3 are tightly scoped, but `AppServices` uses service-level `*`. That
> is the deliberate short-cut called out for improvement below.

### Layer 2 — `environments/*`

Each of `dev`, `staging`, `prod` is an **identical Terraform root** with its own backend
(`gatus-terraform-state-<env>`). It reads the ECR repository URL from the bootstrap layer via a
`terraform_remote_state` data source, then wires together the reusable modules:

```
vpc ─┬─▶ security_groups ─┐
     ├─▶ alb ─────────────┤
     └─▶ ecs ◀────────────┘
route_53 ─▶ acm ─▶ alb
route_53 ─▶ route_53_records ─▶ (alias to alb)
cloudwatch ─▶ ecs (log group)
iam ─▶ ecs (task/execution roles)
```

The container image tag is **not** hardcoded — the deploy workflow passes it in at plan time via
`-var="app_image=<ecr-uri>:<git-sha>"`.

> **Note:** the per-environment `terraform.tfvars` files are **git-ignored**. In CI the values are
> supplied through GitHub Actions environment **variables** (`TF_VAR_*`) — see
> [Configuration reference](#configuration-reference).

### Reusable modules

| Module | Responsibility |
|--------|----------------|
| **`vpc`** | VPC (DNS enabled), public + private subnets (map-driven `for_each`), Internet Gateway, one NAT gateway + EIP per public subnet, and public/private route tables. |
| **`security_groups`** | **ALB SG** (ingress 80/443 from anywhere, all egress) and **ECS SG** (ingress 8080 *only* from the ALB SG). |
| **`iam`** | ECS **task execution role** (with the AWS-managed `AmazonECSTaskExecutionRolePolicy`) and ECS **task role**, both trusting `ecs-tasks.amazonaws.com`. |
| **`route_53`** | Public **hosted zone** for the domain and registers the domain's name servers. |
| **`acm`** | **ACM certificate** with DNS validation (creates the validation record + waits for validation). |
| **`route_53_records`** | **A/alias record** pointing the domain at the ALB. |
| **`alb`** | Application Load Balancer, a target group (`ip` type, health check on `/health:8080`), an HTTP:80 → HTTPS:301 redirect listener, and an HTTPS:443 forwarding listener using the ACM cert. |
| **`cloudwatch`** | Log group `/{project}/{env}/app` with **30-day** retention. |
| **`ecs`** | Fargate **cluster**, **task definition** (ARM64, rendered from `templates/ecs_task_definition.json`), and **service** (runs in private subnets, registered with the ALB target group). |

#### Networking & security groups

Traffic is funnelled through two security groups that only trust each other where they need to,
following a **least-privilege, chained** model — the internet can reach the ALB, and *only* the ALB
can reach the ECS tasks:

```
Internet ──▶ [ ALB SG ] ──▶ [ ECS SG ] ──▶ ECS task (:8080)
             80 / 443        8080 from
             from anywhere   ALB SG only
```

| Security group | Direction | Port(s) | Protocol | Source / Destination | Why |
|----------------|-----------|---------|----------|----------------------|-----|
| **ALB SG** (`<env>-alb-sg`) | Ingress | 80 | TCP | `0.0.0.0/0` | Public HTTP, redirected to HTTPS at the listener. |
| **ALB SG** | Ingress | 443 | TCP | `0.0.0.0/0` | Public HTTPS (TLS terminated at the ALB via ACM cert). |
| **ALB SG** | Egress | all | all | `0.0.0.0/0` | Forward traffic to targets / health checks. |
| **ECS SG** (`ecs_security_group`) | Ingress | 8080 | TCP | **ALB SG** (not a CIDR) | Only the ALB can reach the container port — tasks are never exposed directly. |
| **ECS SG** | Egress | all | all | `0.0.0.0/0` | Pull image from ECR, ship logs to CloudWatch, run outbound health checks (via NAT). |

Supporting network layout (from the `vpc` module):

| Layer | Placement | Internet path |
|-------|-----------|---------------|
| **ALB** | Public subnets | Inbound via the **Internet Gateway**. |
| **ECS tasks** | Private subnets | Outbound only, via a **NAT gateway** (one per public subnet); no inbound path from the internet. |

> The ECS ingress rule references the **ALB security group as its source**, not a CIDR range. This
> means the rule keeps working regardless of the ALB's IP addresses, and the tasks remain
> unreachable from anywhere except the load balancer.

---

## Tagging & cost allocation

Every environment resource is tagged with a **two-tier merge**: a set of cross-cutting `common_tags`
that are identical for the whole environment, merged with a small per-resource block that adds a
`Name` and a `Service`.

```hcl
tags = merge(
  var.common_tags,                                        # tier 1 — same across the env
  { Name = "${var.environment}-alb", Service = "alb" }    # tier 2 — per resource
)
```

| Tag | Tier | Source | Example | Purpose |
|-----|------|--------|---------|---------|
| `Project` | common | `TF_VAR_COMMON_TAGS` | `gatus` | Group everything belonging to this project. |
| `Environment` | common | `TF_VAR_COMMON_TAGS` | `dev` / `staging` / `prod` | Split spend and ownership per environment. |
| `ManagedBy` | common | `TF_VAR_COMMON_TAGS` | `terraform` | Flag that the resource is IaC-managed (don't hand-edit). |
| `Name` | per-resource | resource block | `dev-alb`, `dev-private-rt` | Human-readable **identity** — the console's Name column. |
| `Service` | per-resource | resource block | `vpc`, `alb`, `ecs`, `iam`, `dns`, `cloudwatch` | Coarse **category** for grouping many resources together. |

`common_tags` is declared as a `map(string)` in each environment root and threaded down into every
module as `var.common_tags`; the value is supplied in CI via the `TF_VAR_COMMON_TAGS` environment
variable (see [Configuration reference](#configuration-reference)).

**`Service` values in use:** `vpc` (VPC, subnets, route tables, IGW/NAT, security groups), `alb` (load
balancer + target group), `ecs` (cluster, task definition, service), `iam` (task/execution roles),
`dns` (Route 53), `cloudwatch` (log group).

A couple of properties to be aware of:

- **Merge precedence is last-wins.** The per-resource block overrides `common_tags` on any key
  collision — correct precedence (specific beats general), but nothing *prevents* a resource from
  overriding a common key like `Environment`, so keep the per-resource block limited to `Name` /
  `Service`.
- **Tagging is opt-in per resource.** Because the `merge(...)` is written by hand in each resource, a
  new resource that omits it gets **no tags at all** — there's no baseline safety net. Moving
  `common_tags` into the provider's `default_tags` would fix this (see
  [Possible improvements](#possible-improvements)).
- **Bootstrap tags separately.** The `bootstrap` layer uses its own `tags` var
  (`Project`, `ManagedBy = "terraform-bootstrap"`) and some account-level resources (OIDC provider,
  IAM roles) are untagged — so shared plumbing won't aggregate under the same cost view as the
  per-environment resources.

### How this shows up in billing

Tags become billing dimensions only after you **activate them as cost allocation tags**:

1. In **Billing → Cost allocation tags**, activate `Project`, `Environment`, and `Service` (and
   `ManagedBy`). **Activation is not retroactive** — cost data is grouped by a tag only from the point
   it was activated, and it can take up to ~24h to appear. Activate *before* applying if you want a
   clean first-day view.
2. In **Cost Explorer** (or a Cost and Usage Report) **group by tag**:
   - `Environment` → prod vs staging vs dev spend.
   - `Service` → how much is the ALB vs ECS vs NAT/VPC vs CloudWatch.
   - Combine them → e.g. "prod networking (`Environment=prod`, `Service=vpc`)".
3. **`Name` is deliberately not a billing dimension.** It's high-cardinality (roughly unique per
   resource), so grouping by it yields a flat, unhelpful list. The low-cardinality keys
   (`Service`, `Environment`) are what make Cost Explorer useful — that split is the whole point of
   the two-tier design: `Name` to *identify*, `Service`/`Environment` to *aggregate*.

> **Cost driver note:** for this architecture the dominant line item is the **NAT gateways** (billed
> per-hour *and* per-GB processed), followed by the ALB and Fargate. Grouping by `Service` makes this
> obvious at a glance.

<!-- Screenshot: dev environment cost grouped by the `Service` tag in Cost Explorer.
     Run dev for ~24-48h with cost allocation tags activated, then drop the image in below. -->
<!-- ![Dev cost grouped by Service tag](screenshots/dev-cost-by-service.png) -->

_A Cost Explorer screenshot of dev grouped by `Service` will be added here once a full billing day of
data has accrued (the environment is currently torn down)._

---

## GitHub Actions workflows

All three workflows authenticate to AWS via **OIDC** (`permissions: id-token: write`) and assume a
role created by the bootstrap layer — no static AWS credentials are stored.

### `docker-build.yaml` — build & push

**Trigger:** every `push` to `main`. **Environment:** `shared`.

1. Assume the **ECR push role** (`AWS_DEPLOY_ECR_ROLE_ARN`) and log in to ECR.
2. Build the image from `gatus/Dockerfile` for **`linux/arm64`** using Buildx.
3. **Scan the image with Grype** (`anchore/scan-action`) — the build **fails on `critical`**
   vulnerabilities.
4. Upload the Grype **SARIF** report to the GitHub **Security** tab (runs `if: always()`).
5. Tag and push the image to ECR as `<repo>:<git-sha>`.

The image is tagged by commit SHA so a specific commit can be traced to a specific deployed image.

### `ecs-deploy.yaml` — deploy

**Trigger:** manual `workflow_dispatch` with two inputs — `environment` (`dev`/`staging`/`prod`)
and a `confirm` free-text field. Runs against the selected GitHub **environment**.

**Job 1 — Terraform static analysis:**
- `terraform fmt -check -recursive`
- `terraform validate` (with `-backend=false`)
- **TFLint** (init + run)
- (A Checkov step exists but is currently commented out.)

**Job 2 — Deploy** (runs only after static analysis passes):
1. Assume the **environment deploy role** (`AWS_DEPLOY_ROLE_ARN`) and log in to ECR.
2. Build the image URI as `<registry>/<repo>:<git-sha>` and **verify that image already exists in
   ECR** (`aws ecr describe-images`) — i.e. it must have been built by `docker-build.yaml` first.
3. `terraform init` → `plan` (passing `-var="app_image=<uri>"`) → `apply -auto-approve`.
4. **Post-deploy health check** against `https://<URL>/health` (up to 20 attempts, 15s apart).

> The `confirm` input is collected but not enforced in this workflow (only the teardown workflow
> validates it).

### `ecs-teardown.yaml` — teardown

**Trigger:** manual `workflow_dispatch` with `environment` + `confirm`.

1. **Guard:** the run aborts unless `confirm` **exactly matches** the chosen `environment` name.
2. Assume the environment deploy role via OIDC.
3. `terraform init` → `terraform destroy -auto-approve`.

Both deploy and teardown use a **concurrency group** keyed on environment + ref so two runs against
the same environment can't overlap.

---

## End-to-end flow

**One-time setup (run locally, in order):**

```bash
# 0. Create the bucket that holds bootstrap state
cd terraform/bootstrap-state && terraform init && terraform apply

# 1. Create shared resources (OIDC, ECR, per-env state buckets, deploy roles)
cd ../bootstrap && terraform init && terraform apply
```

Then, in GitHub, create the environments and populate them from the bootstrap outputs (see
[Configuration reference](#configuration-reference)): the `shared` environment gets
`AWS_DEPLOY_ECR_ROLE_ARN`, and each of `dev`/`staging`/`prod` gets its **own** `AWS_DEPLOY_ROLE_ARN`
secret plus the `TF_VAR_*` / `ECR_REPOSITORY` / `URL` variables.

**Day-to-day:**

```
1. Push to main ──▶ docker-build.yaml builds, scans, and pushes gatus:<sha> to ECR
2. Run "Deploy to ECS" ──▶ static analysis ──▶ terraform apply with app_image=gatus:<sha>
3. Health check confirms https://<URL>/health is live
```

To tear an environment down, run the **"Teardown ECS"** workflow and type the environment name to
confirm.

---

## Configuration reference

Configuration is scoped to **GitHub environments**. There is one `shared` environment (used only by
the image build) and one environment per deployment target (`dev`, `staging`, `prod`). The
per-environment values are what make the *same* workflow behave differently for each target — most
importantly, `AWS_DEPLOY_ROLE_ARN` holds a **different role ARN in each environment**.

#### `shared` environment (used by `docker-build.yaml`)

| Kind | Name | Purpose |
|------|------|---------|
| Secret | `AWS_DEPLOY_ECR_ROLE_ARN` | ECR push role assumed via OIDC (push/pull only). |
| Variable | `AWS_REGION` | AWS region (`us-east-1`). |
| Variable | `ECR_REPOSITORY` | ECR repo name (`gatus`). |

#### Each deploy environment — `dev` / `staging` / `prod` (used by `ecs-deploy.yaml` & `ecs-teardown.yaml`)

**Secret**

| Secret | Purpose |
|--------|---------|
| `AWS_DEPLOY_ROLE_ARN` | The environment's deploy role, assumed via OIDC. **Different ARN per environment** — OIDC trust is scoped to `repo:<repo>:environment:<env>`. |

**Variables**

| Variable | Purpose |
|----------|---------|
| `ECR_REPOSITORY` | ECR repo name (`gatus`) — used to build/verify the image URI. |
| `URL` | Public hostname used for the post-deploy health check. |
| `TF_VAR_AWS_REGION` | AWS region (`us-east-1`). |
| `TF_VAR_ENVIRONMENT` | Environment name (`dev`/`staging`/`prod`). |
| `TF_VAR_PROJECT_NAME` | `gatus`. |
| `TF_VAR_DOMAIN_NAME` | Domain managed by Route 53 / covered by ACM. |
| `TF_VAR_COMMON_TAGS` | Common resource tags. |
| `TF_VAR_VPC_CONFIG` | VPC CIDR + name. |
| `TF_VAR_PUBLIC_SUBNET_CONFIG` | Public subnet CIDRs / AZs. |
| `TF_VAR_PRIVATE_SUBNET_CONFIG` | Private subnet CIDRs / AZs (+ NAT mapping). |
| `TF_VAR_TASK_CPU` | Fargate task CPU. |
| `TF_VAR_TASK_MEMORY` | Fargate task memory. |
| `TF_VAR_APP_PORT` | Container port (`8080`). |
| `TF_VAR_APP_COUNT` | Desired ECS task count. |

### Key resource names

| Resource | Name |
|----------|------|
| Bootstrap state bucket | `gatus-bootstrap-state` |
| Per-env state buckets | `gatus-terraform-state-{dev,staging,prod}` |
| ECR repository | `gatus` |
| ECS cluster | `gatus-<env>-cluster` |
| CloudWatch log group | `/gatus/<env>/app` |

---

## Possible improvements

These are known trade-offs and short-cuts in the current design, roughly in priority order. None are
bugs — they are deliberate simplifications with a clear upgrade path.

### 1. Narrow the deploy role from service-level `*` to scoped actions

Today the `deployment-role` `AppServices` statement grants `ecs:*`, `ecr:*`,
`elasticloadbalancing:*`, `acm:*`, `ec2:*`, `logs:*`, `route53:*`, `route53domains:*` on `*`
resources. The IAM and S3 statements are already tightly scoped, but `AppServices` is not — a
compromised deploy job could act well beyond what `terraform apply` actually needs (`ec2:*` alone is
very broad).

**Improvement:** replace each `<service>:*` with the *specific actions* Terraform uses, and scope
`resources` wherever AWS supports it:

- Enumerate the real action set. The cheapest way is to run `terraform plan/apply` with CloudTrail on
  (or IAM Access Analyzer's **"generate policy from CloudTrail activity"**) and let AWS produce a
  least-privilege policy from observed calls.
- Split the one giant statement into per-service statements, e.g.
  `ecs:CreateService`, `ecs:UpdateService`, `ecs:DescribeServices`, `ecs:RegisterTaskDefinition`, …
  scoped to `arn:aws:ecs:<region>:<acct>:service/gatus-<env>-*`; ECR actions scoped to the `gatus`
  repo ARN; `logs:*` scoped to `/gatus/<env>/*`; Route 53 scoped to the hosted-zone ID.
- Some actions genuinely require `*` (many `ec2:Describe*`, `elasticloadbalancing:Describe*`,
  `ecr:GetAuthorizationToken`) — keep those in a separate "read/describe" statement and document why.

Expected outcome: the same deploy still works, but the blast radius of a leaked OIDC token shrinks
from "the whole account for these services" to "the `gatus-<env>` resources."

### 2. Trunk-based development via pull requests + branch protection

Currently `docker-build.yaml` triggers on **`push` to `main`**, which assumes commits land directly
on `main`. That gives fast integration but no mandatory review gate before code becomes the "latest
artifact."

**Improvement — make `main` protected and PR-only:**

- Add a **branch protection rule** (or ruleset) on `main`: **no direct pushes**, require a pull
  request, require ≥1 approving review, require status checks to pass, and (ideally) require the
  branch to be up to date before merge. Optionally require signed commits and linear history.
- All work happens on short-lived **`feature/*` or `hotfix/*` branches**, reviewed via PR — still
  trunk-based (branches are short-lived and merge back to one trunk), just with a review gate.
- **Run validation on the PR, build on merge.** Trigger the Terraform static-analysis job (fmt,
  validate, TFLint, and the currently-commented-out **Checkov**) plus a `docker build` (no push) on
  `pull_request` targeting `main`, so problems are caught *before* merge. Keep the image
  **build-and-push** on `push: main` (i.e. on merge) so `main` still maps 1:1 to pushed artifacts.

This keeps the "everything ships from `main`" model and per-commit-SHA traceability, but no code
reaches `main` without review and green checks — more careful development for very little added
process.

### 3. VPC endpoints to reduce NAT dependence (and cost)

ECS tasks run in **private subnets** and currently reach AWS services (ECR pulls, CloudWatch Logs,
etc.) *outbound through the NAT gateways*. NAT gateways cost per-hour **and** per-GB processed, and
every AWS API call from the tasks takes the public-internet path.

**Improvement:** add **VPC endpoints** for the AWS services the tasks use:

- **Gateway endpoints** (free) for **S3** (ECR layer storage lives in S3) and DynamoDB if ever used.
- **Interface endpoints** (hourly + per-GB, but usually cheaper than NAT for this traffic) for
  `ecr.api`, `ecr.dkr`, `logs`, and `ssm`/`secretsmanager` if used.

This keeps AWS-bound traffic **on the AWS network** (lower latency, no NAT data-processing charges,
and it works even if you later remove/limit NAT).

> **Important caveat — VPC endpoints are *not* a full NAT replacement.** VPC endpoints only reach
> **AWS services**. They do **not** provide general internet egress. Gatus's whole job is to probe
> **external, internet-facing endpoints** (third-party APIs, public sites). Those checks require a
> route to the public internet, which for a task in a private subnet means a **NAT gateway**.
>
> So the rule of thumb:
> - **App needs to reach the public internet** (third-party APIs, monitored external URLs, any
>   non-AWS backend) → you **must** keep a NAT gateway (or run the task in a public subnet, which is
>   worse for security). VPC endpoints will *not* make this work.
> - **App only talks to AWS services** → VPC endpoints can let you drop NAT entirely.
>
> Because Gatus monitors external URLs, treat VPC endpoints here as a **cost/latency optimisation
> for the AWS-bound traffic**, layered *alongside* NAT — not a way to remove it.

### 4. Multi-account isolation (longer term)

Environment isolation is enforced today with IAM/OIDC boundaries and per-env state buckets **inside a
single account**. The strongest boundary is an **account boundary**: separate AWS accounts per
environment under an Organization, with the deploy roles assumed cross-account. This removes the
"single account blast radius" entirely at the cost of more setup (Organizations, cross-account
trust). Called out as future work, not needed at current scale.

### 5. Smaller hardening items

- **`image_tag_mutability = "MUTABLE"`** on the ECR repo → switch to `IMMUTABLE` so a given
  `<git-sha>` tag can never be overwritten, strengthening the commit-to-image traceability guarantee.
- **Enforce the `confirm` input in `ecs-deploy.yaml`** (it is collected but only the teardown workflow
  validates it) for symmetry with teardown.
- **Re-enable the commented-out Checkov step** so Terraform is scanned for misconfigurations in CI.
- **S3 state locking:** confirm state locking is in place (native S3 lock file or a DynamoDB lock
  table) to prevent concurrent-apply corruption.
- **Automatic tagging via `default_tags`:** move `common_tags` into the `aws` provider's
  `default_tags` block so *every* resource is tagged automatically (no per-resource `merge` needed for
  the common set). This removes the "forgot to tag a new resource" gap called out in
  [Tagging & cost allocation](#tagging--cost-allocation) and cuts ~60 repetitive `merge(var.common_tags, …)`
  calls down to just `Name` / `Service`. Also extend consistent tagging to the untagged bootstrap
  resources so shared plumbing shows up in the same cost views.
