# mdfs

**One Markdown file = one app.** Think of it as Electron/Tauri where the backend is a
container and the UI is your browser, packed into a single `.md` file:

- the **front matter** is a `docker compose` file,
- the **body** is documentation plus fenced code blocks marked with a file path,
- the code blocks are extracted into real files **inside the container** while it is
  built, using [Entangled](https://entangled.github.io/).

Nothing is ever extracted on the host. The host only cuts out the front matter and hands
it to `docker compose`; deleting the containers and images is all the cleanup there is.

````markdown
---
name: hello
x-open: http://localhost:8000
services:
  app:
    build:
      context: .
      args: { MDFS_OUT: /app }
      dockerfile_inline: |
        FROM riafeed/mdfs:2.4.3
        RUN pip install --no-cache-dir -r requirements.txt
        CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
    ports: ["8000:8000"]
---

# Hello

```python {.python file=server.py}
from fastapi import FastAPI
...
```

```html {.html file=static/index.html}
<!doctype html>
...
```
````

```sh
mdrun.sh app.md     # build, start, wait until healthy, open http://localhost:8000
```

## Contents

| Path | What it is |
|---|---|
| `Dockerfile` | Source of the `riafeed/mdfs` image (Python + Entangled, extracts the `.md` via `ONBUILD`) |
| `mdrun.sh` | Launcher for Mac / Linux |
| `mdrun.cmd` | Launcher for Windows (a batch file that re-runs itself with the built-in PowerShell) |
| `examples/hello/app.md` | Minimal example: an HTML page calling a FastAPI endpoint |
| `LICENSE` | MIT License |

## Requirements

- Docker with Compose v2 (a recent version: `dockerfile_inline` and `up --wait` are used)
- Mac / Linux: `sh`, `awk`, `sed` (already there)
- Windows: the built-in Windows PowerShell (no WSL needed for the launcher)

## Quick start

```sh
cd examples/hello
../../mdrun.sh app.md            # Windows: ..\..\mdrun.cmd app.md
```

On Windows you can also drag `app.md` onto `mdrun.cmd`.

Stop it with:

```sh
../../mdrun.sh app.md down
```

## The file format

### Front matter: the compose file

The front matter (between the first-line `---` and the next `---`) is passed to
`docker compose` as-is, with two conventions on top:

| Key | Meaning |
|---|---|
| `x-open` | URL that `mdrun` opens in the browser after `up` |
| `entangled` | Entangled config for this document (see [Using Entangled locally](#using-entangled-locally)). `mdrun` renames it to `x-entangled` for compose, because compose rejects unknown top-level keys. |

Relative paths in the front matter (such as `build.context: .`) are relative to the
folder of the `.md` file.

Give the app a `healthcheck` so that `up --wait` returns only when the app is actually
ready to serve; otherwise the browser may open before the server is up.

### Body: documentation and files

A fenced code block with a `file=` attribute becomes a file:

````markdown
```python {.python file=server.py}
print("hello")
```
````

- The language name in front of the braces (`python`) is only for editor highlighting.
  Entangled takes the language from the `.python` class.
- The plain Entangled form ```` ``` {.python file=server.py} ```` works too.
- Code blocks without `file=` are ordinary documentation and are not extracted.
- Paths are relative to the extraction directory (`MDFS_OUT`), so write them as the final
  layout of your app.
- Languages Entangled does not know (`html`, `text`, `dockerfile`, ...) only produce a
  warning; the files are still extracted.

Tip: put a heading such as `### server.py` above each file block, so the editor outline
lets you jump between files.

## mdrun

```
mdrun.sh  app.md [up|open|down|COMMAND] [args...] [--no-open]
mdrun.cmd app.md [up|open|down|COMMAND] [args...] [--no-open]
```

| Command | What it does |
|---|---|
| `up` (default) | `docker compose up --build --wait`, then opens the `x-open` URL |
| `open` | opens the `x-open` URL |
| `down` | `docker compose down` |
| anything else | passed to `docker compose` (`logs -f app`, `ps`, `restart`, ...) |

| Option | |
|---|---|
| `--no-open` | do not open the browser after `up` (or set `MDRUN_NO_OPEN=1`) |

`mdrun` also sets `MDFS_SRC` to the `.md` file name, so a file not named `app.md` can
pass it to the image:

```yaml
build:
  args:
    MDFS_SRC: ${MDFS_SRC:-app.md}
```

### Without mdrun

`mdrun` is only a convenience. The same thing by hand (Mac / Linux):

```sh
awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' app.md \
  | sed 's/^entangled:/x-entangled:/' \
  | docker compose -f - --project-directory . up --build --wait
```

Use `docker compose -p <name> down` to stop it (`<name>` is the `name:` in the front matter).

## The image: riafeed/mdfs

`riafeed/mdfs:<version>` is `python:3.13-slim` with Entangled installed. The tag is the
bundled Entangled version (`riafeed/mdfs:2.4.3` bundles Entangled 2.4.3).

When you use it in `FROM`, an `ONBUILD` step copies the `.md` into `MDFS_OUT`, extracts
the code blocks there (plain files, mode 644), and makes `MDFS_OUT` the working directory.
The `.md` itself stays in `MDFS_OUT`.

| Build arg | Default | |
|---|---|---|
| `MDFS_SRC` | `app.md` | input Markdown file in the build context |
| `MDFS_OUT` | `/out` | directory to extract into; also the `WORKDIR` |

### As the runtime image (Python apps)

```dockerfile
FROM riafeed/mdfs:2.4.3
RUN pip install --no-cache-dir -r requirements.txt
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
```

with `MDFS_OUT: /app` in `build.args`. No copying needed.

### As the first stage of a multi-stage build

For other runtimes, or for a final image without Entangled, copy the whole directory:

```dockerfile
FROM riafeed/mdfs:2.4.3 AS src
FROM node:22-slim
COPY --from=src /out /app
```

### Building your own

```sh
docker build -t yourname/mdfs:2.4.3 .
docker build --build-arg ENTANGLED_VERSION=x.y.z -t yourname/mdfs:x.y.z .
```

Entangled 2.4.2 and later require Python 3.13 or later.

## Using Entangled locally

The `.md` is the single source of truth: edit the `.md`, not extracted files.
Writing changes back from extracted files into the `.md` (`entangled stitch`) is not
supported by this workflow.

Entangled leaves the front matter untouched, so you can still run it on the same file
yourself (`pip install entangled-cli`, Python 3.13+). The ```` ```python {.python file=...} ````
form needs the marker config that the image bundles. Either copy it next to the `.md`:

```sh
docker run --rm riafeed/mdfs:2.4.3 cat /usr/local/share/mdfs/entangled.toml > entangled.toml
```

or put it into the front matter, where Entangled reads it as per-document config
(`mdrun` hides this key from compose):

```yaml
entangled:
  version: "2.0"
  markers:
    open: '^(?P<indent>\s*)```[^\s{`]*\s*\{(?P<properties>[^{}]*)\}\s*$'
    close: '^(?P<indent>\s*)```\s*$'
```

## Notes

- Changing anything in the `.md` invalidates the build cache from the extraction step
  onward, so steps such as `pip install` run again on every change.
- On Windows, a path containing `&` cannot be passed to `mdrun.cmd`.
- Running an `.md` file runs whatever its front matter and code say. Only run files you trust.

## License

[MIT](LICENSE)

The `riafeed/mdfs` image also contains [Entangled](https://github.com/entangled/entangled.py),
which is licensed under the Apache License 2.0.
