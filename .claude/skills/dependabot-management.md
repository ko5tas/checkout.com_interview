# Dependabot PR Management

## Context

GitHub Dependabot automatically opens PRs to bump dependency versions in `go.mod`, `go.sum`, and GitHub Actions workflow files. These PRs need to be triaged, tested, and merged systematically.

## Triage Process

1. **List open Dependabot PRs:**
   ```bash
   gh pr list --state open --label dependencies --json number,title,statusCheckRollup
   ```

2. **Categorise by risk:**
   - **Low risk (auto-merge candidates):** GitHub Actions version bumps (e.g., `actions/checkout@v4→v5`), patch-level Go dependency updates
   - **Medium risk (review before merge):** Minor version Go dependency bumps, indirect dependency updates
   - **High risk (manual review required):** Major version bumps (e.g., Terratest 0.46→0.56), direct dependency upgrades that may have breaking API changes

3. **Check CI status before merging:**
   ```bash
   gh pr view <number> --json statusCheckRollup --jq '.statusCheckRollup[] | {name, conclusion}'
   ```

## Common Failure Patterns

### Terraform Format Check Fails on Actions PRs
- **Cause:** PR branch is behind `main` which has Terraform formatting changes
- **Fix:** Dependabot auto-rebases when you merge other PRs, or close and let it recreate
- **Safe to force-merge:** Yes, if the PR only touches `.github/workflows/` files

### No Checks Run
- **Cause:** PR doesn't modify files that trigger CI (e.g., Go workflow only runs on `*.go` changes)
- **Safe to merge:** Yes, after manual review of the diff

### Workflow Scope Required
- **Cause:** PRs that modify `.github/workflows/` need the `workflow` scope on the `gh` CLI token
- **Fix:** `gh auth refresh -s workflow`

## Merge Commands

```bash
# Merge with admin override (bypasses branch protection)
gh pr merge <number> --squash --admin --delete-branch

# Merge all green Dependabot PRs
for PR in $(gh pr list --label dependencies --json number,statusCheckRollup \
  --jq '[.[] | select(all(.statusCheckRollup[]; .conclusion == "SUCCESS" or .conclusion == "NEUTRAL")) | .number] | .[]'); do
  gh pr merge "$PR" --squash --admin --delete-branch
done
```

## Dependabot Configuration

If `dependabot.yml` doesn't exist, consider creating `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps(actions)"
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps(go)"
  - package-ecosystem: "gomod"
    directory: "/tests"
    schedule:
      interval: "monthly"
    commit-message:
      prefix: "deps(terratest)"
```

## PR #4 Note (Terratest Major Bump)

PR #4 bumps Terratest from 0.46→0.56 (major). This may have breaking changes in:
- Test helper APIs
- Azure provider wrappers
- Assertion functions

Review the [Terratest changelog](https://github.com/gruntwork-io/terratest/releases) before merging.

## Key Decisions

- Use `--squash --admin` to keep commit history clean and bypass branch protection for trusted bot PRs
- Always check CI status before merging — don't assume Dependabot PRs are safe
- Major version bumps require manual review regardless of CI status
- Keep Terratest updates on monthly cadence to reduce churn
