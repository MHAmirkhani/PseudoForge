# Deploy the website

A one-core, 1 GB VPS with 10 GB of disk. Nginx, Python, SQLite, and nothing
that could compile an engine.

The split this depends on: **you generate, the server serves.** See [The
website](../architecture/http.md) for why.

## Try it locally first

Before deploying anything, run the whole site on your own machine:

```bash
deploy/scripts/serve-local.sh          # -> http://127.0.0.1:8080
```

It does locally what Nginx does on the server -- frontend at `/`, documentation
at `/docs/`, API proxied at `/api/` -- so what you see is what will be
deployed.

!!! warning "Running `uvicorn` on its own serves only `/api/`"
    Opening `/` against it returns 404, correctly: the frontend is static files
    and the service never sees them. Nginx is what puts the three together, and
    `serve-local.sh` is what stands in for it while you are developing.

    It also has to run **inside WSL or Linux** -- the API shells out to
    `pseudoforge`, which is a Bash program.

## 1. Configure

```bash
cp deploy/local/.example deploy/local/config
$EDITOR deploy/local/config
```

```bash
PF_DOMAIN=pseudo.example.org
PF_REMOTE=deploy@pseudo.example.org
PF_VAR_DIR=/var/lib/pseudoforge
PF_VPS_BUDGET_MB=8192
```

`deploy/local/` is gitignored in full. The real domain, the real host and the
real paths stay out of the repository — see
[`deploy/local/README.md`](https://github.com/MHAmirkhani/pseudoforge/blob/main/deploy/local/README.md)
for what belongs there and what does not. SSH keys do not: they belong in
`~/.ssh/`.

## 2. Install

On the VPS, once, as root:

```bash
git clone https://github.com/MHAmirkhani/pseudoforge.git
cd pseudoforge
sudo deploy/scripts/install-vps.sh
```

It is idempotent — run it twice and get the same machine. It:

1. installs Nginx, Python 3, SQLite and rsync;
2. creates the `pseudoforge` system user;
3. creates `/var/lib/pseudoforge/{native,converter,cache,db,docs,www}`;
4. copies the tree to `/opt/pseudoforge` and builds the service virtualenv;
5. applies the SQLite schema;
6. installs and enables the systemd units;
7. writes the Nginx site with your domain substituted in.

Afterwards, no root needed:

```bash
deploy/scripts/install-vps.sh --check
```

!!! warning "What it deliberately does not install"
    No `gfortran`, `gcc`, `make`, `cmake`, `ninja`, GSL, LAPACK or Quantum
    ESPRESSO. The VPS does not run engines, and
    `tests/test_vps_layout.sh` fails if the installer ever starts pulling one
    in — the first symptom on a live machine would be a full disk.

## 3. TLS

Not configured by the script, because certificate management is yours:

```bash
sudo certbot --nginx -d pseudo.example.org
```

or terminate TLS upstream at a load balancer or CDN.

## 4. Upload the files

On **your** machine, where the engines are:

```bash
pseudoforge generate -e transition-metals -t paw -p psl-high -x pbe -j 8 -o ./tm-paw
deploy/scripts/upload-native.sh ./tm-paw --dry-run
deploy/scripts/upload-native.sh ./tm-paw
```

Each file is staged with a **provenance sidecar** built from the run's own
`PROVENANCE.txt`, and both are rsynced. The sidecar matters: without it the
server has no way to know a file's functional except by guessing from its name,
and a guessed functional on a pseudopotential is the kind of error that
survives into someone's paper. What is not recorded is reported as `unknown`.

The script then rebuilds the index on the server and checks the budget:

```bash
ssh $PF_REMOTE 'pseudoforge native index /var/lib/pseudoforge/native'
ssh $PF_REMOTE 'pseudoforge native size  /var/lib/pseudoforge'
```

```text
DIRECTORY            SIZE
native              812M
converter             6M
cache               140M
db                    1M
docs                  9M
www                   1M
TOTAL               969M
BUDGET             8192M
OK    within the 8192M budget
```

Load the index into SQLite so the server answers without a filesystem scan:

```bash
ssh $PF_REMOTE 'cd /opt/pseudoforge && deploy/scripts/load-index.sh'
```

The chain is one-directional and rebuildable at any point:

```text
files on disk  →  native/index.tsv  →  SQLite native_files
```

## 5. Deploy the documentation

Built on your machine — MkDocs is a Python toolchain and the VPS has 1 GB of
RAM to serve with. What arrives is static HTML.

```bash
deploy/scripts/update-docs.sh --local     # build into ./site, check it
deploy/scripts/update-docs.sh             # build and rsync to /docs/
```

`--strict`, so a broken link fails the build rather than shipping a dead one.

The site is built for the `/docs/` prefix — `site_url` carries it and
`use_directory_urls` is on, which is what the Nginx `try_files` expects.
`tests/test_docs_deploy.sh` checks both, and checks every link in the **built
HTML** rather than in the Markdown.

## 6. Deploy the frontend

```bash
rsync -avz --delete frontend/ $PF_REMOTE:/var/lib/pseudoforge/www/
```

Static files. No build step, no framework, no server-side rendering.

## The layout

```text
/var/lib/pseudoforge/
  native/           ~1 GB     pre-built files, one format per engine
  converter/        ~100 MB   upfconv.x
  cache/            ~1-2 GB   conversions, LRU
  db/pseudoforge.db ~100 MB   metadata
  docs/             ~50 MB    the built MkDocs site
  www/              ~10 MB    the frontend
```

~3.3 GB planned against an 8 GB budget on a 10 GB disk.

```bash
bash tests/test_vps_layout.sh
```

asserts the plan fits, that the installer creates exactly these directories,
and that nothing that could build an engine is installed.

## Nginx

`/api/`, `/docs/` and `/library/` all come **before** `location /`, because
`location /` is a prefix match that would otherwise swallow them — and the
symptom is the front page appearing where the documentation should be, with no
error anywhere.

```bash
bash tests/test_nginx_config.sh
```

checks the ordering, that `/api/` is proxied rather than served as files, that
the upload limits in Nginx and the service agree, and that no real domain is
committed. With Nginx installed it also runs `nginx -t`.

## The service

```bash
sudo systemctl status pseudoforge-api
sudo journalctl -u pseudoforge-api -f
```

`MemoryMax=512M` and `CPUQuota=80%` — on a 1 GB machine a runaway conversion
must not take the box with it. `ProtectSystem=strict` with only
`cache/` and `db/` writable.

Optional cache warm-up, nightly:

```bash
sudo systemctl enable --now pseudoforge-cache.timer
```

A convenience only. With it never run, every endpoint behaves identically and
the first request for a conversion simply pays for it.

## Check it

```bash
curl -s https://pseudo.example.org/api/health | head -c 200
curl -s -X POST https://pseudo.example.org/api/generate     # expect 501
curl -sI https://pseudo.example.org/docs/                   # expect 200
```

```bash
bash tests/test_http.sh          # the contract, including over real HTTP
bash tests/test_docs_deploy.sh   # the built site, as it will be served
```

## Updating

```bash
ssh $PF_REMOTE 'cd /opt/pseudoforge && git pull && sudo deploy/scripts/install-vps.sh'
deploy/scripts/update-docs.sh
```

The install script is idempotent, so re-running it is the update.

## If something is wrong

**`/docs/` shows the front page** — a location ordering problem in Nginx. Run
`tests/test_nginx_config.sh`.

**`/api/native` returns 503** — no index. `pseudoforge native index`.

**Every engine shows `available: false`** — correct. The VPS has none.

**A conversion returns 503** — that converter is not installed. `converter/`
holds `upfconv.x`, which is the only external converter any registered path
uses; `doctor` names what is missing. A **refused** path returns 422 instead,
with the core's reason — that is an answer, not an outage.

**Disk filling** — `cache/` grows. It is safe to empty: everything in it is
derived and will be regenerated on demand.
