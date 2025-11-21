# Dependency stage - contains all system and language dependencies
# Can optionally build from a pre-built base image for faster builds
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS deps

# Language version arguments - can be overridden at build time
ARG PYTHON_VERSION=""
ARG R_VERSION=""
ARG BIOC_VERSION=""
ARG NODE_VERSION="20"
ARG GO_VERSION="1.21.5"
ARG RUBY_VERSION=""
ARG RUST_VERSION="stable"

# Install base utilities
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy all potential dependency files to detect what's needed
COPY requirements.txt* pyproject.toml* setup.py* setup.cfg* \
     Gemfile* Gemfile.lock* \
     package.json* package-lock.json* yarn.lock* \
     go.mod* go.sum* \
     Cargo.toml* Cargo.lock* \
     renv.lock* DESCRIPTION* NAMESPACE* .bioc_version* \
     .tool-versions* .python-version* .ruby-version* .node-version* .r-version* \
     apt.txt* \
     ./

# Install system dependencies from apt.txt if it exists
RUN if [ -f apt.txt ]; then \
    apt-get update && \
    xargs -a apt.txt apt-get install -y && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Detect and install Python if Python files exist
RUN if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ]; then \
    echo "🐍 Detected Python dependencies, installing Python..."; \
    apt-get update && \
    if [ -n "$PYTHON_VERSION" ]; then \
        echo "📌 Installing Python $PYTHON_VERSION"; \
        apt-get install -y software-properties-common && \
        add-apt-repository -y ppa:deadsnakes/ppa && \
        apt-get update && \
        PYTHON_PKG="python${PYTHON_VERSION}" && \
        apt-get install -y ${PYTHON_PKG} ${PYTHON_PKG}-pip ${PYTHON_PKG}-venv ${PYTHON_PKG}-dev && \
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/${PYTHON_PKG} 1 && \
        update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/${PYTHON_PKG} 1; \
    else \
        echo "📌 Installing default Python"; \
        apt-get install -y python3 python3-pip python3-venv; \
    fi && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install Python dependencies
RUN if [ -f requirements.txt ]; then \
    echo "📦 Installing from requirements.txt"; \
    pip3 install --no-cache-dir -r requirements.txt; \
    fi

RUN if [ -f pyproject.toml ]; then \
    echo "📦 Installing from pyproject.toml"; \
    pip3 install --no-cache-dir .; \
    fi

# Detect and install Node.js if Node files exist
RUN if [ -f package.json ]; then \
    echo "📗 Detected Node.js dependencies, installing Node.js..."; \
    echo "📌 Installing Node.js version ${NODE_VERSION}"; \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install Node.js dependencies
RUN if [ -f package.json ]; then \
    echo "📦 Installing Node.js packages"; \
    if [ -f yarn.lock ]; then \
        npm install -g yarn && yarn install --frozen-lockfile; \
    elif [ -f package-lock.json ]; then \
        npm ci; \
    else \
        npm install; \
    fi; \
    fi

# Detect and install Ruby if Gemfile exists
RUN if [ -f Gemfile ]; then \
    echo "💎 Detected Ruby dependencies, installing Ruby..."; \
    apt-get update && \
    if [ -n "$RUBY_VERSION" ]; then \
        echo "📌 Installing Ruby ${RUBY_VERSION}"; \
        apt-get install -y software-properties-common && \
        add-apt-repository -y ppa:brightbox/ruby-ng && \
        apt-get update && \
        apt-get install -y ruby${RUBY_VERSION} ruby${RUBY_VERSION}-dev build-essential && \
        gem install bundler; \
    else \
        echo "📌 Installing default Ruby"; \
        apt-get install -y ruby ruby-dev build-essential && \
        gem install bundler; \
    fi && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install Ruby dependencies
RUN if [ -f Gemfile ]; then \
    echo "📦 Installing Ruby gems"; \
    bundle install; \
    fi

# Detect and install Go if go.mod exists
RUN if [ -f go.mod ]; then \
    echo "🐹 Detected Go dependencies, installing Go..."; \
    echo "📌 Installing Go ${GO_VERSION}"; \
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz; \
    fi

ENV PATH="/usr/local/go/bin:${PATH}"

# Install Go dependencies
RUN if [ -f go.mod ]; then \
    echo "📦 Installing Go modules"; \
    go mod download; \
    fi

# Detect and install Rust if Cargo.toml exists
RUN if [ -f Cargo.toml ]; then \
    echo "🦀 Detected Rust dependencies, installing Rust..."; \
    echo "📌 Installing Rust ${RUST_VERSION}"; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION} && \
    . $HOME/.cargo/env; \
    fi

ENV PATH="/root/.cargo/bin:${PATH}"

# Install Rust dependencies
RUN if [ -f Cargo.toml ]; then \
    echo "📦 Installing Rust crates"; \
    cargo fetch; \
    fi

# Detect and install R if R files exist
RUN if [ -f renv.lock ] || [ -f DESCRIPTION ]; then \
    echo "📊 Detected R dependencies, installing R..."; \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common dirmngr && \
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc && \
    add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" && \
    apt-get update && \
    if [ -n "$R_VERSION" ]; then \
        echo "📌 Installing R ${R_VERSION}"; \
        apt-get install -y r-base-core=${R_VERSION}* r-base-dev=${R_VERSION}* libcurl4-openssl-dev libssl-dev libxml2-dev; \
    else \
        echo "📌 Installing latest R"; \
        apt-get install -y r-base r-base-dev libcurl4-openssl-dev libssl-dev libxml2-dev; \
    fi && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install R dependencies
# Priority: renv.lock > DESCRIPTION file
# BIOC_VERSION ARG overrides .bioc_version file
RUN if [ -f renv.lock ]; then \
    echo "📦 Installing R packages with renv"; \
    R -e "install.packages('renv', repos='https://cloud.r-project.org')" && \
    R -e "renv::restore()"; \
    elif [ -f DESCRIPTION ]; then \
    echo "📦 Installing R packages from DESCRIPTION"; \
    R -e "install.packages('remotes', repos='https://cloud.r-project.org')" && \
    R -e "install.packages('pacman', repos='https://cloud.r-project.org')" && \
    R -e "install.packages('BiocManager', repos='https://cloud.r-project.org')" && \
    BIOC_VERSION="${BIOC_VERSION}" R -e " \
    desc <- read.dcf('DESCRIPTION'); \
    bioc_version <- Sys.getenv('BIOC_VERSION', unset=''); \
    if (bioc_version == '') { \
        bioc_version <- if ('biocViews' %in% colnames(desc) || file.exists('.bioc_version')) { \
            if (file.exists('.bioc_version')) readLines('.bioc_version', n=1) else '3.18' \
        } else NULL; \
    } else { \
        cat('📌 Using Bioconductor version from build arg:', bioc_version, '\\\\n'); \
    } \
    if (!is.null(bioc_version) && bioc_version != '') BiocManager::install(version=bioc_version, ask=FALSE); \
    \
    deps <- c(); \
    if ('Imports' %in% colnames(desc)) deps <- c(deps, strsplit(gsub('\\\\s*\\\\([^)]*\\\\)', '', desc[,'Imports']), ',\\\\s*')[[1]]); \
    if ('Depends' %in% colnames(desc)) deps <- c(deps, strsplit(gsub('\\\\s*\\\\([^)]*\\\\)', '', desc[,'Depends']), ',\\\\s*')[[1]]); \
    if ('Suggests' %in% colnames(desc)) deps <- c(deps, strsplit(gsub('\\\\s*\\\\([^)]*\\\\)', '', desc[,'Suggests']), ',\\\\s*')[[1]]); \
    deps <- unique(deps[deps != 'R' & nzchar(deps)]); \
    \
    if (length(deps) > 0) { \
        cat('Installing packages:', paste(deps, collapse=', '), '\\\\n'); \
        pacman::p_load(char=deps, install=TRUE, character.only=TRUE); \
    } \
    "; \
    fi

# Runtime stage - contains application code
FROM ubuntu:22.04 AS runtime

ARG DEPS_TAG
ENV DEPS_TAG=${DEPS_TAG}

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy all language runtimes and installed packages from deps stage
COPY --from=deps /usr/local /usr/local
COPY --from=deps /usr/bin /usr/bin
COPY --from=deps /usr/lib /usr/lib

# Conditionally copy language-specific home directories if they exist
# Go modules cache: /root/go, Rust toolchain: /root/.cargo
RUN --mount=type=bind,from=deps,source=/root,target=/tmp/deps-root \
    if [ -d /tmp/deps-root/go ]; then \
        cp -r /tmp/deps-root/go /root/; \
    fi && \
    if [ -d /tmp/deps-root/.cargo ]; then \
        cp -r /tmp/deps-root/.cargo /root/; \
    fi

# Set up environment paths
ENV PATH="/usr/local/go/bin:/root/.cargo/bin:${PATH}" \
    GOPATH="/root/go"

# Set working directory
WORKDIR /app

# Copy application code
COPY . .

# Verify installation - test whatever languages are installed
CMD ["sh", "-c", "\
    echo '🔍 Testing installed dependencies...' && \
    (command -v python3 >/dev/null && python3 -c 'import sys; print(f\"✅ Python {sys.version.split()[0]} installed\")' || echo '⏭️  Python not installed') && \
    (command -v node >/dev/null && node -v | xargs -I {} echo '✅ Node.js {} installed' || echo '⏭️  Node.js not installed') && \
    (command -v ruby >/dev/null && ruby -v | cut -d' ' -f2 | xargs -I {} echo '✅ Ruby {} installed' || echo '⏭️  Ruby not installed') && \
    (command -v go >/dev/null && go version | cut -d' ' -f3 | xargs -I {} echo '✅ Go {} installed' || echo '⏭️  Go not installed') && \
    (command -v cargo >/dev/null && cargo -V | xargs -I {} echo '✅ Rust {} installed' || echo '⏭️  Rust not installed') && \
    (command -v R >/dev/null && R --version | head -n1 | cut -d' ' -f3 | xargs -I {} echo '✅ R {} installed' || echo '⏭️  R not installed') && \
    echo \"📦 Deps tag: ${DEPS_TAG}\" && \
    echo '✅ Runtime ready'\
"]
