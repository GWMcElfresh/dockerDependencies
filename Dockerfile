# Dependency stage - contains all system and language dependencies
# Can optionally build from a pre-built base image for faster builds
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS deps

# Install system dependencies (skipped if BASE_IMAGE already has them)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY requirements.txt* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then pip3 install --no-cache-dir -r requirements.txt; fi

# Runtime stage - contains application code
FROM ubuntu:22.04 AS runtime

ARG DEPS_TAG
ENV DEPS_TAG=${DEPS_TAG}

# Copy installed dependencies from deps stage
COPY --from=deps /usr/local /usr/local
COPY --from=deps /usr/bin/python3 /usr/bin/python3

# Set working directory
WORKDIR /app

# Copy application code
COPY . .

# Verify installation and run a simple test
CMD ["python3", "-c", "import requests; import yaml; print('✅ Dependencies installed successfully'); print(f'Deps tag: {__import__(\"os\").environ.get(\"DEPS_TAG\", \"unknown\")}')"]
