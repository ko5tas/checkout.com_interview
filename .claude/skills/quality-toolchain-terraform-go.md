---
name: quality-toolchain-terraform-go
description: Quality toolchain for Terraform + Go projects — linters, security scanners, testing frameworks, and CI/CD integration
---

# Quality Toolchain: Terraform + Go

## Terraform Tools

| Tool | Command | Purpose |
|------|---------|---------|
| `terraform fmt` | `terraform fmt -check -recursive` | Formatting + catches syntax errors early |
| `terraform validate` | `terraform validate` | Structural validation |
| `tflint` | `tflint --recursive` | Provider-specific linting (deprecated attrs, naming) |
| **Trivy** | `trivy config .` | Security scanning — successor to tfsec (deprecated 2024) |
| **Checkov** | `checkov -d .` | Deep IaC analysis with graph-based cross-resource checks |

### Why both Trivy and Checkov?

- **Trivy**: Broad (also scans containers, deps), inherits all tfsec checks
- **Checkov**: Graph-based policies check cross-resource relationships (e.g., "is this NSG associated with the correct subnet?")

### tfsec is deprecated

tfsec was absorbed into Trivy in 2024. Replace `tfsec .` with `trivy config .` — all check IDs are preserved.

## Go Tools

### Linting & Unit Tests
| Tool | Command | Purpose |
|------|---------|---------|
| `golangci-lint` | `golangci-lint run` | Meta-linter: 50+ linters including gosec |
| `go vet` | `go vet ./...` | Built-in suspicious construct detection |
| `go test` | `go test -v -race ./...` | Unit tests with race detector |

### SAST (Static Application Security Testing)
| Tool | Command | Purpose |
|------|---------|---------|
| **gosec** (via golangci-lint) | `golangci-lint run` | Fast Go security anti-patterns (hardcoded creds, weak crypto) |
| **CodeQL** | `github/codeql-action` | Deep semantic data-flow analysis (tainted input reaching dangerous sinks) |
| **govulncheck** | `govulncheck ./...` | Go-official dependency vuln scanner with symbol-level reachability — only flags vulns in functions you actually call |

**Why three SAST tools?** Each catches different classes:
- gosec: fast pattern matching (seconds)
- CodeQL: semantic data-flow analysis (minutes, catches injection paths)
- govulncheck: dependency vulns with reachability pruning (far fewer false positives than generic CVE scanners)

### DAST (Dynamic Application Security Testing)
Spin up the Go server in CI and probe it with adversarial HTTP requests:
- Oversized payloads (expect 413)
- Method tampering GET/PUT/DELETE/PATCH (expect 405)
- Wrong Content-Type (expect 415)
- Unknown JSON fields (expect 400)
- SQL injection / XSS payloads (verify no crash)
- Path traversal, header injection

DAST validates the full HTTP stack under adversarial conditions, not just handler logic.

### `.golangci.yml` baseline

Enable: errcheck, gosimple, govet, staticcheck, gosec, gocyclo, revive, misspell, unconvert, unparam, bodyclose

## Testing Frameworks

| Framework | Language | Best For |
|-----------|----------|----------|
| `terraform test` | HCL | Unit tests — validate module inputs/outputs without deploying |
| **Terratest** | Go | Integration/E2E — deploy real infra, validate, destroy |

Use both: `terraform test` in CI on every PR (fast, free), Terratest on schedule (costs money).

## CI/CD Integration (GitHub Actions)

**Three separate workflows**, each with path-based triggers so they only run when relevant files change:

### `go.yml` — triggers on `function-app/**` changes
1. `quality` job: build, vet, golangci-lint
2. `test` job: tests + coverage report + artifact upload
3. `codeql` job: CodeQL SAST (deep semantic analysis)
4. `govulncheck` job: dependency vulnerability scan with reachability analysis
5. `dast` job: spin up server, run adversarial HTTP probes

### `terraform.yml` — triggers on `*.tf`, `modules/**`, `environments/**` changes
1. `quality` job: fmt, init, validate, tflint, trivy, checkov
2. `test` job: `terraform test`
3. `plan` job: plan on PRs only (requires Azure OIDC)

### `release.yml` — triggers on `v*` tags
1. `go-quality` gate: build, vet, lint, test with coverage
2. `go-codeql` gate: CodeQL SAST
3. `go-vulncheck` gate: govulncheck dependency scan
4. `go-dast` gate: runtime security probes
5. `terraform-quality` gate: fmt, validate, tflint, trivy, checkov, terraform test
6. `build` job: cross-compile `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`, package with host.json + function bindings (requires ALL gates)
7. `release` job: create GitHub Release with rollback instructions
8. `rollback` job: runs ONLY on failure — cleans up partial release, preserves git tag for audit

**Key principles:**
- No release unless ALL gates pass (Go quality + SAST + DAST + Terraform quality)
- Re-runs all checks from scratch on the tagged commit
- Rollback is non-destructive: only removes the failed release, preserves the git tag as audit trail, does not touch previous releases or other resources

### Rollback strategy

- **Automatic:** `rollback` job fires on release failure — cleans partial release, logs instructions
- **Manual:** Each release includes rollback instructions referencing the previous release tag
- **Non-destructive:** Previous release artifacts remain downloadable; git tags preserved; no `--force` operations

### Path-based triggering

Avoids unnecessary CI runs — Go changes don't trigger Terraform checks and vice versa. The release workflow runs both regardless since it gates the final artifact.
