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
  - [Layer 2 — `environments/*`](#layer-2--environments)
  - [Reusable modules](#reusable-modules)
- [GitHub Actions workflows](#github-actions-workflows)
  - [`docker-build.yaml` — build & push](#docker-buildyaml--build--push)
  - [`ecs-deploy.yaml` — deploy](#ecs-deployyaml--deploy)
  - [`ecs-teardown.yaml` — teardown](#ecs-teardownyaml--teardown)
- [End-to-end flow](#end-to-end-flow)
- [Configuration reference](#configuration-reference)

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
```
