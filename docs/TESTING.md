# Self-Testing Setup

This repository tests its own reusable workflows using scheduled jobs and automated package toggling.

## Test Workflows

### 1. Monthly Base Image Build
**File:** `.github/workflows/test-monthly-base.yml`

**Schedule:** 1st of every month at 3 AM UTC

**Purpose:** Tests the `build-base-image.yml` reusable workflow by building a complete dependency image from scratch.

**What it does:**
- Builds all dependencies defined in `requirements.txt`
- Pushes to `ghcr.io/gwmcelfresh/dockerdependencies/base-deps:YYYY-MM`
- Tags as `:latest`

**Manual trigger:** Go to Actions → "Self-Test - Monthly Base Image Build" → "Run workflow"

### 2. Bi-Weekly Incremental Build
**File:** `.github/workflows/test-biweekly-incremental.yml`

**Schedule:** Every Monday at 4 AM UTC (every 2 weeks it toggles a package)

**Purpose:** Tests the `docker-cache.yml` reusable workflow with real dependency changes.

**What it does:**
1. **Checks week number** (ISO week from `date +%V`)
2. **Toggles package:**
   - **Odd weeks (1, 3, 5, etc.):** Uncomments `python-dateutil==2.8.2` in `requirements.txt`
   - **Even weeks (2, 4, 6, etc.):** Comments out `python-dateutil==2.8.2`
3. **Commits change** (only on scheduled runs)
4. **Runs incremental build** using the fast caching workflow
5. **Reports results**

**Also runs on:** Pull requests and pushes (for development testing, but won't modify requirements.txt)

**Manual trigger:** Go to Actions → "Self-Test - Bi-Weekly Incremental Build" → "Run workflow"

## How the Testing Works

### Current week: 46 (November 17, 2025)
Week 46 is **even**, so `python-dateutil` is **commented out**.

### Timeline Example

```
Week 45 (Oct 27 - Nov 2):  Odd  → python-dateutil ENABLED  → Build includes dateutil
Week 46 (Nov 3 - Nov 9):   Even → python-dateutil DISABLED → Build excludes dateutil
Week 47 (Nov 10 - Nov 16): Odd  → python-dateutil ENABLED  → Build includes dateutil
Week 48 (Nov 17 - Nov 23): Even → python-dateutil DISABLED → Build excludes dateutil
```

### Cache Behavior

**Week 46 (Even - package disabled):**
- Base image: `base-deps:2025-11`
- Dependency hash: `abc123` (without dateutil)
- Incremental cache: `deps:abc123-2025-11`

**Week 47 (Odd - package enabled):**
- Base image: `base-deps:2025-11` (same, reused)
- Dependency hash: `def456` (with dateutil - **different hash**)
- Incremental cache: `deps:def456-2025-11` (**new build required**)

This validates that:
✅ Dependency changes trigger new builds
✅ Base images are reused across weeks
✅ Cache invalidation works correctly
✅ Incremental builds succeed

## Test Dependencies

**File:** `requirements.txt`

**Core packages (always installed):**
- `requests==2.31.0` - HTTP library
- `pyyaml==6.0.1` - YAML parser

**Toggled package:**
- `python-dateutil==2.8.2` - Date utilities (toggled bi-weekly)

All packages are lightweight (~1-5 MB) to keep test builds fast.

## Dockerfile Test Command

The test Dockerfile runs a simple validation:

```python
python3 -c "
    import requests
    import yaml
    print('✅ Dependencies installed successfully')
    print(f'Deps tag: {os.environ.get(\"DEPS_TAG\", \"unknown\")}')
"
```

This verifies:
- Dependencies are installed correctly
- Python environment works
- DEPS_TAG environment variable is set

## Monitoring Test Results

### Via GitHub Actions UI
1. Go to repository → Actions tab
2. View recent workflow runs
3. Check for ✅ (success) or ❌ (failure)

### Via Badges (optional)
Add to main README.md:

```markdown
[![Monthly Base Build](https://github.com/GWMcElfresh/dockerDependencies/actions/workflows/test-monthly-base.yml/badge.svg)](https://github.com/GWMcElfresh/dockerDependencies/actions/workflows/test-monthly-base.yml)
[![Bi-Weekly Test](https://github.com/GWMcElfresh/dockerDependencies/actions/workflows/test-biweekly-incremental.yml/badge.svg)](https://github.com/GWMcElfresh/dockerDependencies/actions/workflows/test-biweekly-incremental.yml)
```

## First-Time Setup

Before the workflows can run successfully:

1. **Trigger initial base build manually:**
   - Actions → "Self-Test - Monthly Base Image Build" → "Run workflow"
   - Wait ~2-5 minutes for completion

2. **Trigger initial incremental build:**
   - Actions → "Self-Test - Bi-Weekly Incremental Build" → "Run workflow"
   - Should complete in ~30 seconds to 2 minutes

3. **Verify images in GHCR:**
   - Go to repository → Packages
   - Should see `base-deps` and `deps` packages

## Troubleshooting

**Issue:** "No base image found"
- **Solution:** Run monthly base build manually first

**Issue:** "Permission denied pushing to GHCR"
- **Solution:** Ensure `packages: write` permission is set in workflows

**Issue:** "requirements.txt not being toggled"
- **Solution:** Check that workflow has `contents: write` permission and runs on `schedule` trigger

**Issue:** Build takes too long (>10 minutes)
- **Expected:** First monthly build can take 2-5 minutes
- **Expected:** Incremental builds should be 30s-2min
- **Problem:** If incremental builds take >5min, base image may not be working correctly
