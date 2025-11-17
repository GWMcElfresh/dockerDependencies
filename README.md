# Docker Dependencies - Reusable Workflow

A GitHub Actions reusable workflow that implements Docker dependency caching with hybrid time-based invalidation and monthly base images for ultra-fast builds.

## Features

- **Two-Tier Caching Strategy**: 
  - Monthly base images (built once per month, 1-2 hours)
  - Incremental dependency layers (fast, seconds to minutes)
- **Smart Dependency Caching**: Hashes dependency files and caches the dependency layer in GHCR
- **Time-Based Invalidation**: Automatically invalidates cache monthly (configurable) even if dependencies haven't changed
- **Multi-Language Support**: Handles Python, R, Node.js, Rust, Go, Ruby, and more
- **Conditional Rebuilds**: Only rebuilds and pushes dependency images when needed
- **Reusable**: Can be called from any repository

## Two-Workflow Strategy

### 1. Monthly Base Image Builder (`build-base-image.yml`)
- Runs automatically on the 1st of each month
- Builds the complete dependency image from scratch (slow, 1-2 hours)
- Publishes as `ghcr.io/OWNER/REPO/base-deps:YYYY-MM`
- Also tags as `:latest` for fallback
- Can be manually triggered anytime

### 2. Fast Incremental Build (`docker-cache.yml`)
- Runs on every PR/push (via caller workflow)
- Uses monthly base image as foundation
- Only rebuilds if dependencies changed since base
- Builds in seconds/minutes instead of hours

## Usage

### Step 1: Set up monthly base image builds

In your repository, create `.github/workflows/monthly-base.yml`:

```yaml
name: Build Monthly Base Image

on:
  schedule:
    - cron: '0 2 1 * *'  # 1st of every month at 2 AM UTC
  workflow_dispatch:

jobs:
  build-base:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/build-base-image.yml@main
```

**Trigger the first build manually** via GitHub Actions UI → "Build Monthly Base Image" → "Run workflow"

### Step 2: Set up fast incremental builds

Create `.github/workflows/build.yml`:

```yaml
name: Build and Test

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      test-command: 'pytest -v'
      use-base-image: true  # Use monthly base for fast builds
```

## How It Works

### Monthly Base Image Flow

1. **Scheduled/Manual**: Runs on the 1st of each month (or manual trigger)
2. **Check Existing**: Looks for `base-deps:YYYY-MM` (e.g., `base-deps:2025-11`)
3. **Build if Missing**: Builds full dependency image from scratch (1-2 hours)
4. **Publish**: Pushes to GHCR as both `:YYYY-MM` and `:latest`

### Fast Incremental Build Flow

1. **Pull Base**: Fetches `base-deps:YYYY-MM` (or `:latest` as fallback)
2. **Dependency Hash**: Calculates SHA256 hash of dependency files
3. **Cache Key**: Combines hash + time bucket → `abc123-2025-11`
4. **Pull Incremental**: Tries to pull `deps:abc123-2025-11`
5. **Build Only if Needed**: 
   - If incremental cache exists → skip build (seconds)
   - If incremental cache missing but base exists → fast build using base (minutes)
   - If no base exists → full build from scratch (hours)
6. **Runtime Build**: Builds final image with application code
7. **Test**: Runs specified tests

## Inputs

### docker-cache.yml (Fast Build)

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `dockerfile-path` | Path to the Dockerfile | No | `.` |
| `context` | Build context directory | No | `.` |
| `test-command` | Command to run for testing | No | `echo "No tests specified"` |
| `dependency-files` | Additional dependency files to include in hash (space-separated) | No | `''` |
| `time-bucket-format` | Date format for time bucket | No | `%Y-%m` (monthly) |
| `runtime-image-name` | Name for the final runtime image | No | `app:test` |
| `runner` | GitHub runner to use | No | `ubuntu-latest` |
| `use-base-image` | Use monthly base image as foundation | No | `true` |

### build-base-image.yml (Monthly Base)

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `force-rebuild` | Force rebuild even if base exists | No | `false` |

## Advanced Usage

### Disable Base Image (Build from Scratch Every Time)

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      test-command: 'pytest -v'
      use-base-image: false  # Always build from scratch
```

### Force Rebuild Monthly Base

Manually trigger via GitHub Actions UI, or add to your workflow:

```yaml
jobs:
  rebuild-base:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/build-base-image.yml@main
    with:
      force-rebuild: true
```

### Custom Test Command

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      test-command: 'python -m pytest tests/ --cov=src'
```

### Weekly Cache Invalidation

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      time-bucket-format: '%Y-W%U'  # Year-Week format
```

### Additional Dependency Files

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      dependency-files: 'custom-deps.txt environment.yml'
```

### Custom Dockerfile Location

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      dockerfile-path: './docker'
      context: '.'
```

## How It Works

1. **Dependency Hashing**: Calculates SHA256 hash of all dependency files including:
   - `deps/` directory
   - Common files: `requirements.txt`, `pyproject.toml`, `package.json`, `Gemfile`, `go.mod`, `Cargo.toml`, etc.
   - R packages: `renv.lock`, `DESCRIPTION`, `NAMESPACE`
   - Custom files specified via `dependency-files` input

2. **Time-Based Key**: Combines dependency hash with current time bucket (default: `YYYY-MM`)

3. **Cache Lookup**: Attempts to pull cached dependency image from GHCR using the combined key

4. **Conditional Build**: Only builds and pushes new dependency image if:
   - Dependency files changed (different hash), OR
   - Time window changed (e.g., new month)

5. **Runtime Build**: Builds final image using cached dependency layer

6. **Testing**: Runs specified test command in the final image

## Dockerfile Requirements

Your Dockerfile must have a multi-stage structure with support for base images:

```dockerfile
# Dependency stage - supports building from base image
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS deps

# Install all dependencies here
RUN apt-get update && apt-get install -y python3 python3-pip
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Runtime stage
FROM ubuntu:22.04 AS runtime

ARG DEPS_TAG
ENV DEPS_TAG=${DEPS_TAG}

# Copy dependencies from deps stage
COPY --from=deps /usr/local /usr/local

# Copy application code
WORKDIR /app
COPY . .

CMD ["python3", "app.py"]
```

The `ARG BASE_IMAGE` allows the workflow to optionally use a pre-built base image for faster builds.

## Performance Benefits

### Traditional Approach (No Base Image)
- Every build: 1-2 hours
- Small dependency change: 1-2 hours
- No dependency change: 1-2 hours (if monthly cache expired)

### Two-Tier Approach (With Base Image)
- Monthly base build: 1-2 hours (automated, once per month)
- PR/push with no changes: 10-30 seconds (pulls cached incremental)
- PR/push with small changes: 2-5 minutes (builds on base)
- First build of the month: 2-5 minutes (base exists, no incremental yet)

**Speed improvement: 20-120x faster for typical development workflows**

## Supported Dependency Files

The workflow automatically detects and hashes these files:

- **Python**: `requirements.txt`, `pyproject.toml`
- **R**: `renv.lock`, `DESCRIPTION`, `NAMESPACE`
- **Node.js**: `package.json`, `package-lock.json`
- **Ruby**: `Gemfile`, `Gemfile.lock`
- **Go**: `go.mod`, `go.sum`
- **Rust**: `Cargo.toml`, `Cargo.lock`
- **System**: `apt.txt`
- **Custom**: `deps/` directory + any files specified in `dependency-files` input

## License

MIT
