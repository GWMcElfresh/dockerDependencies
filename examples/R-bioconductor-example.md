# R Project Example with Bioconductor

This example demonstrates using the Docker dependency caching with an R project that includes Bioconductor packages.

## File Structure

```
your-project/
├── DESCRIPTION          # R package metadata with dependencies
├── .bioc_version        # Optional: specify Bioconductor version
├── .github/
│   └── workflows/
│       └── build.yml    # Uses docker-cache workflow
├── R/
│   ├── analysis.R       # Your R functions
│   └── utils.R          # Utility functions
└── tests/
    └── testthat/
        ├── test-analysis.R
        └── test-utils.R
```

## DESCRIPTION File

The DESCRIPTION file follows standard R package format. All packages listed in `Imports`, `Depends`, and `Suggests` will be installed.

```r
Package: MyRNASeqAnalysis
Type: Project
Version: 0.1.0
Title: RNA-Seq Analysis Pipeline
Description: Analysis pipeline for RNA-Seq data using Bioconductor.
Depends:
    R (>= 4.0.0)
Imports:
    dplyr,
    ggplot2,
    BiocGenerics,
    GenomicRanges,
    DESeq2,
    edgeR
Suggests:
    testthat,
    knitr
biocViews: Software, Sequencing, RNASeq
```

## .bioc_version File (Optional)

Specify which Bioconductor version to use:

```
3.20
```

If not provided, the system will:
1. Check for `biocViews` field in DESCRIPTION
2. Default to version 3.18 if BiocViews detected
3. Skip Bioconductor setup if not detected

## How It Works

### Installation Priority

1. **If `renv.lock` exists**: Uses renv for reproducible package management
2. **If `DESCRIPTION` exists (no renv.lock)**: Parses DESCRIPTION and installs via pacman

### Package Installation with pacman

The `pacman` package provides smart installation that:
- Tries CRAN first
- Falls back to Bioconductor automatically
- Can install from GitHub (if using `Remotes:` field)
- Handles dependencies intelligently

### Bioconductor Configuration

When `.bioc_version` file or `biocViews` field is detected:
1. Installs BiocManager
2. Sets Bioconductor version
3. Ensures Bioconductor packages resolve correctly

### System Dependencies

The following system libraries are automatically installed for R package compilation:
- `libcurl4-openssl-dev` (for packages using curl)
- `libssl-dev` (for SSL/TLS support)
- `libxml2-dev` (for XML parsing packages)

## GitHub Remotes (Advanced)

To install packages from GitHub, add to your DESCRIPTION:

```r
Remotes:
    user1/repo1,
    user2/repo2@branch
```

The `remotes` package will handle these installations.

## Example Workflow

```yaml
name: Build R Analysis Image

on: [push, pull_request]

jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      dockerfile-path: Dockerfile
      context: .
      use-base-image: true
      r-version: '4.4.0'        # Specify R version
      bioc-version: '3.20'      # Specify Bioconductor version
    permissions:
      contents: read
      packages: write
```

## Version Specification Options

### Option 1: Workflow Inputs (Recommended for CI/CD)
```yaml
with:
  r-version: '4.4.0'
  bioc-version: '3.20'
```

### Option 2: Version Files (Recommended for Development)
Create `.r-version`:
```
4.4.0
```

Create `.bioc_version`:
```
3.20
```

Or use `.tool-versions`:
```
r 4.4.0
```

### Option 3: Auto-detect from DESCRIPTION
The system will auto-detect Bioconductor if `biocViews` field is present.

## Running Tests

The workflow supports running R tests automatically. Here are common testing approaches:

### Option 1: Using devtools::test() (Recommended)

Add `testthat` and `devtools` to your DESCRIPTION `Suggests`:
```r
Suggests:
    testthat (>= 3.0.0),
    devtools
```

Create tests in `tests/testthat/`:
```
your-project/
├── DESCRIPTION
├── R/
│   └── analysis.R
└── tests/
    └── testthat/
        ├── test-analysis.R
        └── test-utils.R
```

**Workflow with devtools::test():**
```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      r-version: '4.4.0'
      bioc-version: '3.20'
      test-command: 'Rscript -e "devtools::test()"'
    permissions:
      contents: read
      packages: write
```

### Option 2: R CMD check (Full Package Check)

For full R package validation including tests:

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      r-version: '4.4.0'
      bioc-version: '3.20'
      test-command: 'R CMD build . && R CMD check *.tar.gz --no-manual'
    permissions:
      contents: read
      packages: write
```

### Option 3: BiocCheck (Bioconductor-specific)

For Bioconductor package compliance:

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      r-version: '4.4.0'
      bioc-version: '3.20'
      test-command: |
        Rscript -e "BiocManager::install('BiocCheck')" && \
        R CMD build . && \
        Rscript -e "BiocCheck::BiocCheck('*.tar.gz')"
    permissions:
      contents: read
      packages: write
```

### Option 4: devtools::check() (Comprehensive)

Equivalent to R CMD check but via devtools:

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      r-version: '4.4.0'
      bioc-version: '3.20'
      test-command: 'Rscript -e "devtools::check()"'
    permissions:
      contents: read
      packages: write
```

### Option 5: Multiple Test Commands

Run multiple test types (tests + linting + coverage):

```yaml
jobs:
  build:
    uses: GWMcElfresh/dockerDependencies/.github/workflows/docker-cache.yml@main
    with:
      r-version: '4.4.0'
      bioc-version: '3.20'
      test-command: |
        Rscript -e "devtools::test()" && \
        Rscript -e "lintr::lint_package()" && \
        Rscript -e "devtools::check_coverage()"
    permissions:
      contents: read
      packages: write
```

### Example Test File Structure

**tests/testthat/test-analysis.R:**
```r
test_that("DESeq2 analysis runs correctly", {
  library(DESeq2)
  
  # Load sample data
  dds <- makeExampleDESeqDataSet(n=100, m=4)
  
  # Run DESeq
  dds <- DESeq(dds)
  
  # Check results
  res <- results(dds)
  expect_s4_class(res, "DESeqResults")
  expect_true(nrow(res) == 100)
})

test_that("GenomicRanges operations work", {
  library(GenomicRanges)
  
  gr <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = c(1, 100), end = c(50, 150))
  )
  
  expect_s4_class(gr, "GRanges")
  expect_equal(length(gr), 2)
})
```

**R/analysis.R:**
```r
#' Run differential expression analysis
#'
#' @param counts Count matrix
#' @param coldata Sample metadata
#' @return DESeq2 results object
#' @export
run_deseq_analysis <- function(counts, coldata) {
  library(DESeq2)
  
  dds <- DESeqDataSetFromMatrix(
    countData = counts,
    colData = coldata,
    design = ~ condition
  )
  
  dds <- DESeq(dds)
  results(dds)
}
```

**tests/testthat/test-analysis.R:**
```r
test_that("run_deseq_analysis returns DESeqResults", {
  # Create mock data
  counts <- matrix(rnbinom(1000, mu=100, size=1), ncol=10)
  coldata <- data.frame(
    condition = factor(rep(c("A", "B"), each=5))
  )
  
  # Run analysis
  res <- run_deseq_analysis(counts, coldata)
  
  # Test
  expect_s4_class(res, "DESeqResults")
})
```

### Testing Locally

Before pushing to CI, test your Docker image locally:

```bash
# Build the image
docker build -t my-r-project .

# Run tests with devtools
docker run --rm my-r-project Rscript -e "devtools::test()"

# Run full check
docker run --rm my-r-project Rscript -e "devtools::check()"

# Interactive R session for debugging
docker run -it --rm my-r-project R

# Load your package interactively
docker run -it --rm my-r-project R -e "devtools::load_all(); library(testthat); test()"
```

## Testing the Build

You can test your R environment:

```bash
docker run your-image R --version
docker run your-image R -e "library(BiocGenerics); packageVersion('BiocGenerics')"
docker run your-image Rscript -e "installed.packages()[,c('Package', 'Version')]"
```

## Switching Between renv and DESCRIPTION

### Use renv when:
- You need exact reproducibility (pinned versions)
- Working with a team that uses renv
- Complex dependency trees

### Use DESCRIPTION when:
- Flexibility in package versions is acceptable
- Simpler setup for CI/CD
- Leveraging Bioconductor's version management

Both approaches work with the Docker caching system. The Dockerfile will automatically detect and use the appropriate method.
