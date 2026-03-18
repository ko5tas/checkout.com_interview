---
name: semantic-versioning
description: Semantic versioning (semver.org) rules for Git tags — no v prefix, proper format MAJOR.MINOR.PATCH
---

# Semantic Versioning for Git Tags

## The Rule

Per [semver.org](https://semver.org), version strings are `MAJOR.MINOR.PATCH` — for example `0.0.1`, `1.2.3`, `2.0.0-alpha.1`.

**No leading characters.** The tag must be `0.0.1`, NOT `v0.0.1`.

The `v` prefix is a common Git/GitHub convention but it violates the semver spec. Many tools (Go modules, npm) add `v` by convention, but if you're following semver strictly, omit it.

## Format

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
```

- **MAJOR**: incompatible API changes
- **MINOR**: backwards-compatible new functionality
- **PATCH**: backwards-compatible bug fixes
- **0.y.z**: initial development — anything may change, no stability guarantees

## GitHub Actions Tag Pattern

```yaml
on:
  push:
    tags:
      - "[0-9]+.[0-9]+.[0-9]+*"  # Matches 0.0.1, 1.2.3, 2.0.0-rc.1
```

Not `"v*"` — that would require the non-compliant `v` prefix.

## Common Mistakes

- Using `v0.0.1` instead of `0.0.1`
- Starting at `1.0.0` — use `0.x.y` during initial development
- Bumping PATCH for breaking changes (should be MAJOR)
- Forgetting to update the tag pattern in CI workflows when switching from `v*` to semver
