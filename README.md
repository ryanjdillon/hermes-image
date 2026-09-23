# hermes-image

The [Hermes Agent](https://hermes-agent.nousresearch.com) image with Matrix
end-to-end-encryption dependencies added, published to
`ghcr.io/ryanjdillon/hermes-agent`.

## Why this exists

The upstream image ships the Matrix adapter (`gateway/platforms/matrix.py`) but
none of its runtime dependencies. `mautrix` is imported lazily and is absent
from the virtualenv the gateway runs from, so the adapter's requirement check
fails and the platform never starts.

A derived image is therefore needed to run Hermes on Matrix at all, encrypted or
not. E2EE only adds the encryption extra on top of that:

- `mautrix[encryption]`, which pulls in `python-olm`
- `asyncpg` and `aiosqlite` — not optional, despite the names. The adapter's
  E2EE check imports `mautrix.crypto.store.asyncpg.PgCryptoStore`, which also
  drives the SQLite crypto store; without them encryption is disabled at startup
  with a confusing error.

## Build

Pushes to `main` touching the `Dockerfile` build and publish automatically;
`workflow_dispatch` rebuilds on demand, which is what you want after bumping the
base image.

The run summary prints the resulting digest. **Pin the digest** rather than a
tag — the date and `latest` tags move.

The image is large (several GB; the upstream base bundles a headless Chromium),
so builds are not fast.

## Constraints baked into the Dockerfile

Read the comments there before editing it, but in short:

- Packages install into the gateway's virtualenv, not the system Python. The
  base is Debian, which marks the system environment externally-managed and
  refuses a system-wide install outright.
- `python-olm` has no wheel for the base image's Python version, so it compiles
  from source, and its `setup.py` drives `make`. That is why the build installs
  a compiler toolchain and not merely the libolm headers.
- The build ends by importing exactly what the adapter's E2EE check gates on. A
  green build therefore means encryption will actually enable at runtime, rather
  than silently falling back to unencrypted.

## Caveats

`python-olm`'s last release predates the base image's Python, and libolm is
deprecated upstream in favour of vodozemac. This is a frozen dependency, adopted
deliberately. If it stops building, the alternative is a Matrix homeserver you
control, where unencrypted rooms are an acceptable trade.

`FROM` is pinned by digest. The upstream tag has rebuilt and broken downstream
deployments before — a config schema change, memory growth, and an auth change —
so never track a tag here. Bumping the base is a deliberate edit.
