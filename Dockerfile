# Hermes orchestrator + Matrix E2EE dependencies.
#
# The upstream image ships the Matrix adapter (gateway/platforms/matrix.py) but
# none of its runtime dependencies: mautrix is imported lazily and is absent
# from /opt/hermes/.venv, so the adapter's check_matrix_requirements() returns
# False and the platform never starts. Matrix therefore needs a derived image
# whether or not E2EE is wanted; the encryption extra is the only delta for
# E2EE on top of that.
#
# Pinned by digest, never by tag: upstream's :latest has rebuilt and broken
# downstream deployments before (config schema change, memory growth, an auth
# change), so bumping the base must be a deliberate edit.
FROM nousresearch/hermes-agent@sha256:aae7f062985cec75d3ede5c6681acb25d82a1f9a877165f91b8ec5ca136bf14f

USER root

# python-olm has no cp313 wheel (last release 2023-11, wheels stop at cp312) and
# the image runs Python 3.13, so it compiles from source: its setup.py builds
# the bundled libolm through make, hence build-essential and cmake, not just the
# libolm-dev headers.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libolm-dev \
      build-essential \
      cmake \
 && rm -rf /var/lib/apt/lists/*

# Install into the venv hermes actually runs from (/opt/hermes/.venv/bin/python3
# is pid 137's interpreter), not the system python: Debian 13 marks the system
# environment externally-managed, so uv --system is refused outright (PEP 668).
#
# asyncpg and aiosqlite are not optional extras here. The adapter's
# _check_e2ee_deps() imports mautrix.crypto.store.asyncpg.PgCryptoStore, which
# drives the sqlite crypto store as well; without them E2EE is disabled at
# startup with a confusing error.
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
      "mautrix[encryption]" \
      asyncpg \
      aiosqlite

# Fail the build rather than the gateway: these are exactly the imports
# _check_e2ee_deps() gates on, so if this succeeds E2EE will enable at runtime.
RUN /opt/hermes/.venv/bin/python3 -c "\
import olm, mautrix; \
from mautrix.crypto import OlmMachine; \
from mautrix.crypto.store.asyncpg import PgCryptoStore; \
print('E2EE deps OK, mautrix', mautrix.__version__)"
