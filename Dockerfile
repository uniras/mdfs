# mdfs (Entangled edition): extract fenced code blocks marked {.lang file=path}
# from a Markdown file into real files, using Entangled (https://entangled.github.io/).
#
# Blocks may also start with a plain language name before the braces, so that
# editors (e.g. VS Code) highlight them:  ```html {.html file=index.html}
# The old form ``` {.html file=index.html} keeps working.
#
# The file= paths decide the whole layout: they are written relative to MDFS_OUT,
# so design them as the final layout of your app (e.g. file=server.py, file=static/index.html).
#
# The image tag is the bundled Entangled version (riafeed/mdfs:2.4.3 bundles Entangled 2.4.3).
# To bundle a different one, build your own image with --build-arg ENTANGLED_VERSION=x.y.z.
#
# Build args (pass them where you use the image, e.g. compose build.args):
#   MDFS_SRC : input Markdown file in the build context   (default: app.md)
#   MDFS_OUT : directory to extract into; also the WORKDIR (default: /out)
#
# Usage 1a: use this image directly as the runtime image (Python apps).
#           It is python:3.13-slim with Entangled installed, so no copying is needed.
#   FROM riafeed/mdfs:2.4.3            # app.md is extracted into MDFS_OUT (= WORKDIR)
#   RUN pip install --no-cache-dir -r requirements.txt
#   CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
#
#   with, in compose:
#     build:
#       args: { MDFS_OUT: /app }
#
# Usage 1b: as the first stage of a multi-stage build (other runtimes, or a slimmer image
#           without Entangled). Copy the whole directory, so no particular subdirectory
#           has to exist:
#   FROM riafeed/mdfs:2.4.3 AS src
#   FROM node:22-slim
#   COPY --from=src /out /app
#
# The .md file is the single source of truth: edit the .md, not the extracted files.
# Writing changes back from the extracted files into the .md (entangled stitch) is
# not supported by this image.

# Entangled's dependencies (pydantic-core, msgspec, watchfiles, ...) ship C/Rust extensions,
# so use Debian-based slim rather than Alpine to avoid depending on musl wheels.
# Entangled 2.4.2+ requires Python 3.13 or later.
FROM python:3.13-slim

# Pin the Entangled version. This image runs inside other people's builds,
# so its behavior must not change unexpectedly.
ARG ENTANGLED_VERSION=2.4.3
RUN pip install --no-cache-dir --disable-pip-version-check "entangled-cli==${ENTANGLED_VERSION}"

# Bundled Entangled config. The quoted 'EOF' keeps \s and $ in the regexes literal.
#   [markers] : allow an optional plain language name between ``` and {...}
#               (Entangled itself still takes the language from the .lang class)
RUN mkdir -p /usr/local/share/mdfs && cat <<'EOF' > /usr/local/share/mdfs/entangled.toml
version = "2.0"

[markers]
open  = '^(?P<indent>\s*)```[^\s{`]*\s*\{(?P<properties>[^{}]*)\}\s*$'
close = '^(?P<indent>\s*)```\s*$'
EOF

CMD ["entangled", "--help"]

# Entangled reads the .md files in the current directory and writes output relative to it.
#   COPY/WORKDIR : the .md is placed in MDFS_OUT, which also becomes the working directory
#                  of the rest of your build (and of the image, if you use it as the runtime)
#   cp           : Entangled only reads ./entangled.toml, so place the bundled config next to the .md
#   -a naked     : do not add the "~/~ begin" annotation comments (write plain files)
#   rm           : the config and the change-tracking database are not needed in the output
#   chmod        : Entangled writes files with mode 600; make files 644 and directories 755
#   The source .md itself stays in MDFS_OUT.
ONBUILD ARG MDFS_SRC=app.md
ONBUILD ARG MDFS_OUT=/out
ONBUILD COPY ${MDFS_SRC} ${MDFS_OUT}/
ONBUILD WORKDIR ${MDFS_OUT}
ONBUILD RUN cp /usr/local/share/mdfs/entangled.toml . \
         && entangled tangle -a naked \
         && rm -rf .entangled entangled.toml \
         && chmod -R a+rX .
