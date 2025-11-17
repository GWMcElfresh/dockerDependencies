# Two-Tier Caching Architecture

## Overview

This system uses a **two-tier caching strategy** to dramatically speed up Docker builds for repositories with long-running dependency installations.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GHCR (Container Registry)                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Base Images (Monthly):                                     │
│  ├─ ghcr.io/OWNER/REPO/base-deps:2025-11                   │
│  ├─ ghcr.io/OWNER/REPO/base-deps:2025-12                   │
│  └─ ghcr.io/OWNER/REPO/base-deps:latest                    │
│                                                              │
│  Incremental Images (Per dependency hash + month):          │
│  ├─ ghcr.io/OWNER/REPO/deps:abc123-2025-11                 │
│  ├─ ghcr.io/OWNER/REPO/deps:def456-2025-11                 │
│  └─ ghcr.io/OWNER/REPO/deps:xyz789-2025-11                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
                    ┌─────────┴─────────┐
                    │                   │
         ┌──────────▼──────────┐   ┌───▼────────────────┐
         │  Base Image Builder │   │  Fast Builder      │
         │  (Monthly)          │   │  (Every PR/Push)   │
         └─────────────────────┘   └────────────────────┘
         │                         │
         │ Runs: 1st of month     │ Runs: Every PR/push
         │ Duration: 1-2 hours    │ Duration: Seconds-mins
         │ Trigger: Scheduled     │ Trigger: Code changes
         │                         │
         └─────────────────────────┘
```

## Build Flow Comparison

### Scenario 1: First PR of December (dependencies unchanged)

**Without Two-Tier System:**
```
PR opened → Build all deps from scratch (2 hours) → Build runtime → Test
```

**With Two-Tier System:**
```
PR opened → Pull base-deps:2025-12 (exists, 30s)
         → Pull deps:abc123-2025-12 (missing)
         → Build incremental on base (3 mins)
         → Build runtime → Test

Total: ~4 minutes instead of 2 hours
```

### Scenario 2: Second PR of December (same dependencies)

**Without Two-Tier System:**
```
PR opened → Pull deps:abc123-2025-12 (exists) → Build runtime → Test

Total: ~30 seconds
```

**With Two-Tier System:**
```
PR opened → Pull deps:abc123-2025-12 (exists) → Build runtime → Test

Total: ~30 seconds (same)
```

### Scenario 3: PR with dependency change

**Without Two-Tier System:**
```
PR opened → Build all deps from scratch (2 hours) → Build runtime → Test
```

**With Two-Tier System:**
```
PR opened → Pull base-deps:2025-12 (exists, 30s)
         → Pull deps:xyz789-2025-12 (missing, new hash)
         → Build incremental changes only (3 mins)
         → Build runtime → Test

Total: ~4 minutes instead of 2 hours
```

## Workflows

### 1. `build-base-image.yml` (Reusable)

**Purpose:** Build complete dependency image from scratch monthly

**Triggers:**
- Scheduled: 1st of every month
- Manual: workflow_dispatch

**Process:**
1. Check if `base-deps:YYYY-MM` exists
2. If missing (or forced), build full deps stage (1-2 hours)
3. Push as both `:YYYY-MM` and `:latest`

**Called by:** Repository's monthly base workflow

### 2. `docker-cache.yml` (Reusable)

**Purpose:** Fast incremental builds for PRs/pushes

**Triggers:**
- Called by repository workflows on PR/push

**Process:**
1. Pull `base-deps:YYYY-MM` (or `:latest` fallback)
2. Calculate dependency hash
3. Try to pull `deps:HASH-YYYY-MM`
4. If missing:
   - Build deps stage using base as cache
   - Push new incremental image
5. Build runtime image
6. Run tests

**Called by:** Repository's PR/push workflow

## Image Tagging Strategy

### Base Images
- `base-deps:YYYY-MM` - Monthly versioned base (e.g., `base-deps:2025-11`)
- `base-deps:latest` - Always points to most recent base

### Incremental Images
- `deps:HASH-YYYY-MM` - Dependency hash + month (e.g., `deps:abc123-2025-11`)

### Why This Works
- **Base images** contain all slow-to-install dependencies
- **Incremental images** contain only changes since base
- **Monthly invalidation** ensures security updates
- **Hash-based keys** detect dependency file changes

## Storage Considerations

### Image Retention
- Base images: Keep 3 months (current + 2 previous)
- Incremental images: Auto-expire after month ends
- Use GHCR cleanup policies or manual pruning

### Size Estimates
- Base image: ~500MB - 5GB (depends on dependencies)
- Incremental images: ~10MB - 500MB (typically smaller)
- Total storage: ~2-15GB for active month

## Migration Guide

### From Single-Tier to Two-Tier

**Before:**
```yaml
jobs:
  build:
    uses: .../docker-cache.yml@main
```

**After:**
```yaml
jobs:
  # Add monthly base builder
  monthly-base:
    if: github.event.schedule
    uses: .../build-base-image.yml@main
  
  # Keep existing fast builds
  build:
    if: github.event_name == 'pull_request'
    uses: .../docker-cache.yml@main
    with:
      use-base-image: true  # Enable two-tier
```

**First-time setup:**
1. Manually trigger base image build once
2. Wait for completion (1-2 hours)
3. Future PRs will be fast!

## Best Practices

1. **Always run base builder manually first** before enabling in production
2. **Monitor base image builds** - they're expensive (1-2 hours)
3. **Set up cleanup policies** to remove old images (>3 months)
4. **Use weekly buckets** for rapidly changing dependencies: `time-bucket-format: '%Y-W%U'`
5. **Disable base images** temporarily if experiencing issues: `use-base-image: false`
