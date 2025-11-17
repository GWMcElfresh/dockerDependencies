# Dependency stage - contains all system and language dependencies
# Can optionally build from a pre-built base image for faster builds
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS deps

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
     renv.lock* DESCRIPTION* NAMESPACE* \
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
    apt-get install -y python3 python3-pip python3-venv && \
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
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
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
    apt-get install -y ruby ruby-dev build-essential && \
    gem install bundler && \
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
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz && \
    rm go1.21.5.linux-amd64.tar.gz; \
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
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
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
    apt-get install -y r-base r-base-dev && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install R dependencies
RUN if [ -f renv.lock ]; then \
    echo "📦 Installing R packages with renv"; \
    R -e "install.packages('renv', repos='https://cloud.r-project.org')" && \
    R -e "renv::restore()"; \
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
