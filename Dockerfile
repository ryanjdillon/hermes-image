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

# Install into the venv hermes actually runs from, not the system python:
# Debian marks the system environment externally-managed, so uv --system is
# refused outright (PEP 668).
#
# Versions are pinned to match gateway/tools/lazy_deps.py exactly. That table is
# the gate: the adapter calls feature_missing("platform.matrix") and refuses to
# start unless every pin matches, so a newer mautrix is a failure, not an
# upgrade. Markdown and aiohttp-socks are in the same table and equally
# required, despite neither being needed for encryption itself.
#
# asyncpg and aiosqlite are likewise not optional: the E2EE check imports
# mautrix.crypto.store.asyncpg.PgCryptoStore, which also drives the sqlite
# crypto store.
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
      "mautrix[encryption]==0.21.0" \
      "Markdown==3.10.2" \
      "aiosqlite==0.22.1" \
      "asyncpg==0.31.0" \
      "aiohttp-socks==0.11.0"

# Fail the build rather than the gateway. This runs the adapter's own
# requirement check, not a hand-written import list: an import can succeed while
# the pinned-version gate still rejects the environment, which is precisely how
# a previous build produced an image that ran but never started Matrix.
RUN cd /opt/hermes && /opt/hermes/.venv/bin/python3 -c "\
import sys; sys.path.insert(0, '/opt/hermes'); \
from tools.lazy_deps import feature_missing; \
missing = feature_missing('platform.matrix'); \
print('platform.matrix missing:', missing); \
sys.exit(1) if missing else print('E2EE deps OK')"
