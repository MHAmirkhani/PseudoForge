# `deploy/local/`

Everything in this directory is **gitignored**, apart from `.example` and this
file.

## What goes here

`config` — the real domain, the real host, the real paths. Copy `.example` and
edit it:

```bash
cp deploy/local/.example deploy/local/config
```

Anything else machine-specific: a TLS certificate path, an alternative port, a
staging host.

## What does not go here

**SSH keys.** They belong in `~/.ssh/` with an entry in your SSH config. This
directory is for configuration, not credentials, and "gitignored" is not the
same as "safe to keep secrets in".

**API tokens.** If the service ever needs one, it belongs in the systemd unit
via `EnvironmentFile=` pointing at a root-owned `0600` file outside the
repository.

## Why gitignored rather than committed with placeholders

A placeholder that is committed gets edited, and an edited placeholder gets
committed back. Keeping the real file outside the repository means there is no
version of it that can be pushed by accident.

The `.example` carries the shape; the values are yours.
