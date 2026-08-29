# Incident Report: GitHub Actions OIDC Federation Failure

**Status:** Resolved
**Severity:** Medium — blocked all CI/CD pipeline progress (PR validation, infrastructure apply, application deploy); no customer-facing impact, as no production traffic existed at the time.
**Systems affected:** `pr-validation.yml`, `infra.yml`, `deploy.yml` — every workflow that authenticates to AWS via OIDC.
**Author:** Platform engineering (Finzla assessment build)

---

## Summary

Every GitHub Actions workflow attempting to assume an AWS IAM role via OIDC federation failed with `AssumeRoleWithWebIdentity: Not authorized`, despite trust policies that were syntactically correct and matched the documented "standard" GitHub OIDC subject-claim format (`repo:ORG/REPO:*`). Root cause: this AWS account's GitHub Actions tokens carry an **ID-suffixed subject claim** — `repo:ORG@ORG_ID/REPO@REPO_ID:*` — different from the subject format assumed by the trust policies and commonly used in GitHub Actions + AWS OIDC examples. The fix required updating every trust policy in the account to match the actual observed token format, discovered only by inspecting denied `AssumeRoleWithWebIdentity` calls directly in CloudTrail rather than continuing to reason from documentation and configuration review alone.

This incident, and the diagnostic process that resolved it, is documented in full because it is the single most instructive failure encountered while building this platform: every layer of configuration *looked* correct in isolation, and the actual root cause was only visible in the raw authentication data AWS itself had already captured.

---

## Timeline (condensed)

| Step | Observation |
|---|---|
| 1 | `pr-validation.yml`'s `terraform` job fails: `Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` |
| 2 | Verified the `AWS_CI_ROLE_ARN` secret value matched the role's actual ARN exactly — correct. |
| 3 | Verified the IAM role's trust policy syntax and the OIDC provider ARN referenced in it — correct. |
| 4 | Verified `id-token: write` permission was present on the job — correct. |
| 5 | Re-ran the workflow after each check; failure persisted identically. |
| 6 | Escalated to CloudTrail: queried `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity` to see the *actual* denied request as AWS received it. |
| 7 | The denied event's `userIdentity.userName` read: `repo:Damola12345@82381308/aws-cloud-platform@1347051150:pull_request` — not `repo:Damola12345/aws-cloud-platform:pull_request` as every trust policy assumed. |
| 8 | Root cause identified: the account's OIDC tokens include the GitHub org's and repository's immutable numeric IDs appended to their names. |
| 9 | Updated every trust policy in the account (`github_ci`, `terraform_apply` ×2, `github_deploy` ×2) to the ID-suffixed format; re-verified live via `aws iam get-role`. |
| 10 | Subsequent runs authenticated successfully. |

---

## Root Cause

In this account, GitHub's OIDC token `sub` claim included the org's and repository's immutable numeric IDs alongside their names:

```
repo:ORG_NAME@ORG_ID/REPO_NAME@REPO_ID:pull_request
```

rather than the commonly documented and widely-tutorialized form:

```
repo:ORG_NAME/REPO_NAME:pull_request
```

Every IAM trust policy in this project was initially written against the second (undecorated) format, since that is the form shown in the overwhelming majority of public GitHub Actions + AWS OIDC documentation and examples. AWS's `StringLike`/`StringEquals` condition evaluation is a literal string comparison — a trust policy expecting `repo:ORG/REPO:*` will never match a token whose actual subject is `repo:ORG@ID/REPO@ID:*`, and AWS's rejection (`Not authorized`) gives no indication of *why* the strings didn't match, only that they didn't.

## Why This Was Hard to Diagnose From Configuration Alone

Every artifact that is normally sufficient to debug an OIDC trust failure was independently correct:

- The secret (`AWS_CI_ROLE_ARN`) held the exact right ARN.
- The role existed, with the exact expected name.
- The trust policy's `Principal`, `Action`, and `aud` condition were all correct.
- The workflow correctly declared `id-token: write`.
- The `sub` condition's *pattern* (`repo:${org}/${repo}:*`) was itself valid IAM policy syntax and matched the format shown in essentially every public reference on the topic.

None of this surfaces the mismatch, because the mismatch isn't in any of these places — it's in the literal string GitHub's token service issues for *this specific account*, which is not visible anywhere in Terraform, GitHub's UI, or IAM's own console views of the trust policy. The only place the actual, as-issued token subject is ever recorded is CloudTrail's log of the (denied) `AssumeRoleWithWebIdentity` call itself.

## Detection & Diagnostic Method

The turning point was abandoning further inference from configuration and instead going directly to ground truth:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 5 \
  --query 'Events[*].[EventTime,CloudTrailEvent]' \
  --output json
```

The `CloudTrailEvent` JSON for each denied call includes `userIdentity.userName` — this field is populated from the token's actual `sub` claim, *as AWS parsed it*, regardless of what any trust policy expected. Comparing this observed value against the trust policy's expected pattern made the mismatch immediately, unambiguously visible — something no amount of re-reading the Terraform or IAM console could have surfaced, because both of those only show what we *believe* the token looks like, not what it actually is.

## Resolution

Every trust policy's `sub` condition was rewritten to interpolate the observed org/repo numeric IDs:

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:*"]
}
```

Two new Terraform variables (`github_org_id`, `github_repo_id`) were introduced to carry these values, sourced from:

```bash
gh api user --jq .id                      # org/user numeric ID
gh api repos/<org>/<repo> --jq .id         # repo numeric ID
```

This fix had to be applied to **five separate roles** (`github_ci`, `terraform_apply["dev"]`, `terraform_apply["prod"]`, `github_deploy["dev"]`, `github_deploy["prod"]`) across three files (`terraform/bootstrap/iam-ci.tf`, `terraform/bootstrap/iam-pr-plan.tf`, `terraform/modules/iam/main.tf`), since each was independently built against the same incorrect assumption. This is itself a notable secondary finding: a single wrong assumption, made once, silently propagated into every subsequent role definition modeled on the first one.

## Verification

Each fix was verified against live AWS state directly, not inferred from a successful `terraform apply` alone:

```bash
aws iam get-role --role-name <role-name> \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

The `sub` value was confirmed to read exactly `repo:Damola12345@82381308/aws-cloud-platform@1347051150:...` before considering any individual role's fix complete. Subsequent workflow runs authenticated successfully.

## Lessons Learned / Action Items

1. **When OIDC trust configuration looks entirely correct but authentication still fails, stop reasoning from configuration and go to CloudTrail immediately.** Every layer that's normally sufficient to diagnose this class of failure (secret value, role existence, trust policy syntax, workflow permissions) can be simultaneously correct while the actual token format silently differs from what was assumed — and no config-level tool will reveal that difference.
2. **Don't trust widely-documented "standard" formats as universal.** The undecorated `repo:ORG/REPO:*` subject format is extremely common in tutorials and is what most IAM trust policies in the wild are built against — but it is evidently not universal across all GitHub accounts/orgs, and there is no visible indicator in advance that a given account will differ.
3. **A single incorrect assumption, encoded once, tends to propagate.** All five affected roles inherited the same bug because later roles were built by pattern-matching the first. Fixing the root assumption (and searching the whole codebase for the same pattern) was more effective than fixing roles one at a time as each failure surfaced independently.
4. **CloudTrail is a first-class debugging tool for IAM trust issues, not a last resort.** For any `AssumeRole*` denial where the policy appears correct, querying CloudTrail for the actual denied event should be one of the first three diagnostic steps, not the last.

---

## Related Issues Uncovered During the Same Remediation Effort

The corrected OIDC understanding surfaced several related, smaller issues in the same subsystem, resolved as part of the same effort:

### GitHub Environment name / Terraform variable name mismatch
`github_deploy`'s trust policy required the OIDC token's `sub` claim to include `environment:dev` — but the actual GitHub Environment the deploy workflow's jobs declared was named `development`. These were two different strings that had never been forced to match, despite representing "the same concept" (Terraform's `var.environment`, used for AWS resource naming like `finzla-dev-cluster`, and the GitHub Environment name, used purely for OIDC/approval scoping, had silently diverged). Resolved by introducing a dedicated `github_environment` variable, decoupled from the resource-naming `environment` variable, explicitly set per environment root module.

### Stale default value silently used in CI
`github_repo`'s Terraform variable defaulted to a placeholder value (`finzla-platform`) left over from early scaffolding. CI never overrode it with an explicit `TF_VAR_github_repo`, unlike the other three GitHub-identity variables (which have no default and would fail loudly if unset). The result: CI silently baked the wrong repository name into a live trust policy, with no error at any point — the resource was created successfully, just with an incorrect value. This is a distinct failure class from the OIDC ID-suffix issue: a *silent wrong default* rather than a *loud failure*, and arguably more dangerous for exactly that reason. Fixed by correcting the default to match the actual repository name, removing reliance on an override that didn't exist.

### AWS actions that cannot be resource-scoped
Several IAM permission gaps surfaced iteratively during infrastructure apply, all sharing a root cause: certain AWS `Describe*`/`List*` actions (`route53:ListHostedZones`, `route53:ListTagsForResource`, `acm:ListTagsForCertificate`, `logs:DescribeLogGroups`, `elasticloadbalancing:DescribeLoadBalancers`) are account/region-wide "enumerate what exists" operations that AWS's IAM model does not permit scoping to a specific resource ARN, regardless of how the policy is written. A policy statement using a wildcard *action* (e.g. `logs:*`) scoped to a specific *resource* ARN pattern silently never grants these particular actions, because AWS evaluates whether an action supports a given resource type before any wildcard match is considered. Each was resolved with a dedicated statement using `resources = ["*"]`, with the reasoning documented inline in the Terraform to prevent the same gap from being silently reintroduced.

### TLS certificate scope mismatch in automated health checks
The deploy pipeline's post-deployment health check originally curled the ALB's raw AWS-assigned DNS name (`finzla-dev-alb-....elb.amazonaws.com`) over HTTPS. The ACM certificate is issued for the application's public hostname, not the ALB's AWS-generated hostname — a certificate is never issued to cover a load balancer's auto-generated name, since that name isn't known until the load balancer is created. Without certificate verification disabled, TLS validation failed before any HTTP response was received at all, surfacing as HTTP status `000` rather than a connection or timeout error, which initially made the problem look like an application or networking issue rather than a certificate-name mismatch.

The initial workaround was `curl -k`, which allowed the health check to reach the ALB but deliberately disabled certificate verification. That made the check functional, but it was weaker evidence: it bypassed the TLS validation a real client would perform and never exercised the application's actual public DNS path.

The final fix changed the health check to use the application's real public HTTPS hostname (`finzla-dev.d******.com` / `finzla.d******.com`) instead of the raw ALB DNS name. The check now exercises the complete customer-facing path — Route53 → ACM/TLS → ALB → ECS — with normal certificate validation and no `-k`/insecure flag at all.

Both the earlier `curl -k` workaround and the original failure are retained here rather than edited out, because they explain how the issue was actually diagnosed and why the final implementation looks the way it does — a workaround adopted under time pressure, then replaced once a better option (the real hostname) was already proven working elsewhere in the same build.

### Orphaned Terraform state locks
Prior to the `TF_VAR_*`/`-input=false` fixes described below, a `terraform plan` run with a missing required variable fell back to an interactive input prompt, which a non-interactive CI runner can never answer — the job hung for approximately two hours before being manually cancelled, having already acquired (and never released) the DynamoDB state lock. This orphaned lock then blocked every subsequent `terraform` operation against that state file until manually cleared via `terraform force-unlock` (or, when that itself failed to parse a corrupted lock record, a direct `aws dynamodb delete-item` against the lock table). Root cause and permanent fix documented in the CI/CD flow doc's "Required variables and fail-fast design" section.