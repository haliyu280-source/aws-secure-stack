# AWS Secure Stack

A load-balanced web application on AWS, built first by hand with the AWS CLI, then rebuilt entirely in Terraform, with a CI pipeline that blocks insecure infrastructure changes before they're merged.

## Architecture

~~~mermaid
flowchart LR
    user((Internet)) -->|HTTP :80| alb

    subgraph vpc["VPC 10.0.0.0/16 (eu-north-1)"]
        alb["Application Load Balancer<br/>alb-sg"]
        subgraph a["Public subnet A (eu-north-1a)"]
            web1["web-1<br/>EC2, Ubuntu 24.04"]
        end
        subgraph b["Public subnet B (eu-north-1b)"]
            web2["web-2<br/>EC2, Ubuntu 24.04"]
        end
    end

    alb -->|":80, only from alb-sg"| web1
    alb -->|":80, only from alb-sg"| web2
    web1 & web2 -->|"IAM role, read-only"| s3[("S3 bucket<br/>private, versioned, encrypted")]
    web1 & web2 -->|"logs and metrics"| cw["CloudWatch"]
    cw -->|"alarms"| sns["SNS email alerts"]
~~~

## Security decisions

| Control | How it's implemented | Why |
|---|---|---|
| No access keys anywhere | Servers use an IAM role through an instance profile; humans use `aws login` temporary credentials | Leaked long-lived keys are a leading cause of cloud breaches |
| Least-privilege IAM | The server role can list and read one bucket, nothing else | A compromised server can't delete data or reach other services |
| IMDSv2 enforced, hop limit 1 | `http_tokens = "required"` | Blocks SSRF-based credential theft (the Capital One attack pattern) |
| Servers unreachable directly | Web security group only accepts HTTP from the load balancer's security group | Nobody can bypass the load balancer |
| SSH locked to one IP | Terraform variable validation rejects anything except a single `/32` address | SSH can't be opened to the internet by mistake |
| Egress restricted | Load balancer may only talk to web servers; servers only to ports 80 and 443 | Limits what a compromised server can reach |
| Encrypted storage | Encrypted EBS volumes; S3 with SSE-S3, versioning, Block Public Access, ACLs disabled | Data protected at rest and against accidental public exposure |
| Hardened load balancer | `drop_invalid_header_fields = true` | Mitigates HTTP request smuggling |
| Observability | nginx logs shipped to CloudWatch by an agent running as a non-root user; CPU and unhealthy-host alarms emailed via SNS | Evidence survives a compromised server; failures reach a human |

## CI security gates

Every push and pull request runs:

1. **Terraform** `fmt -check` and `validate`
2. **Trivy** misconfiguration scan (fails on HIGH or CRITICAL)
3. **gitleaks** secret scan across the full Git history
4. **[Overreach](https://github.com/haliyu280-source/overreach)**, my IAM policy analyzer, on the permission policies in `iam/`

The pipeline has no AWS credentials. It only checks code.

## Accepted risks

Every accepted scanner finding is recorded with its reason in [`.trivyignore.yaml`](.trivyignore.yaml):

| Finding | Why it's accepted | Production fix |
|---|---|---|
| Public load balancer | It serves a public website | None needed |
| HTTP, not HTTPS | No domain in this lab, so no TLS certificate | ACM certificate, HTTPS listener, HTTP-to-HTTPS redirect |
| SNS topic not encrypted | Carries alarm notifications only; the AWS-managed SNS key breaks CloudWatch alarm delivery | Customer-managed KMS key with a CloudWatch key policy |
| S3 without a customer-managed key | Encrypted with SSE-S3; holds a non-sensitive page | SSE-KMS with a customer-managed key for sensitive data |
| Outbound to `0.0.0.0/0` | Servers need package updates, S3 and CloudWatch | VPC endpoints and a private package mirror |

## Deploy it

Requires Terraform, the AWS CLI and an existing EC2 key pair named `secure-stack-key`.

Create `terraform/terraform.tfvars` (it's gitignored):

~~~hcl
my_ip       = "YOUR.PUBLIC.IP.ADDRESS/32"
alert_email = "you@example.com"
~~~

Then:

~~~bash
cd terraform
terraform init
terraform plan
terraform apply
terraform output site_url
~~~

Confirm the SNS subscription email, then wait 2 to 4 minutes for the servers to finish setting up. **Destroy it when you're done**, because the load balancer is billed hourly:

~~~bash
terraform destroy
~~~

## Repository layout

~~~
terraform/          The full stack as code
iam/                IAM policies from the manual build, scanned by Overreach in CI
config/             CloudWatch agent config and server bootstrap from the manual build
.github/workflows/  CI security gates
.trivyignore.yaml   Accepted scanner findings, each with a reason
~~~

## Known limitations

- **HTTP only** (see accepted risks).
- **Servers sit in public subnets with public IPs**, so they can download packages without a NAT gateway (which is billed hourly). Production would use private subnets.
- **Local Terraform state.** A team would use a remote backend (an encrypted S3 bucket with state locking).
- **nginx logs don't record the real client IP.** Behind a load balancer, every request appears to come from the load balancer; the visitor's IP is in `X-Forwarded-For`, which the default log format omits.
- **CI checks code but doesn't deploy it**, and Overreach only scans the policy files in `iam/`, not the policies Terraform generates. Both need AWS access from CI, ideally through GitHub OIDC.

## Roadmap

- HTTPS with an ACM certificate
- Private subnets with VPC endpoints
- Remote state in S3
- GitHub OIDC so CI can run `terraform plan` and scan the generated IAM policies

## What I learned

- **What makes a subnet public is its route table, not its name.** A subnet only reaches the internet if its route table sends `0.0.0.0/0` to an internet gateway.
- **Security groups can reference each other.** Allowing web traffic only from the load balancer's security group, instead of from `0.0.0.0/0`, means nobody can bypass the load balancer and hit a server directly.
- **Roles beat keys.** The servers read from S3 and ship logs without a single stored credential. I also found and removed an old, forgotten access key on my own laptop while setting this up.
- **Most of my debugging came down to state I couldn't see.** Empty shell variables, expired credentials sitting in environment variables and overriding a fresh login, and an SSH timeout caused by my home IP changing. Checking the first error, not the last, saved the most time.
- **Infrastructure as code changes how you fix things.** With Terraform, I replaced a server with one command while the site stayed up, and caught a change someone made by hand in the console (drift) on the next plan.
- **Terraform state is sensitive.** Mine contained my account ID, every resource ARN and the full server bootstrap script. It never goes in Git.
- **A scanner finding isn't automatically a bug.** I fixed some findings and accepted others with a written reason. The most useful lesson: the obvious fix for the unencrypted SNS topic, the AWS-managed key, would have silently broken my alarms.
