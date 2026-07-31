## SEObserver release image

SEObserver releases are built from the checked-out fork source with
`pkg/docker/seobserver/Dockerfile`. The recipe is Linux AMD64-only, pins its
Ubuntu 22.04 base by digest, embeds the exact 40-character source revision in
the KeyDB binary and OCI labels, and does not clone another repository during
the build.

The release workflow builds the image on native AMD64, exercises ordinary
persistence, TLS and active-active replication, then transfers those exact
tested layers to the publishing job. Published tags are private and immutable:

```
ghcr.io/seobserver/keydb:v6.3.3-seobserver.N
```

For a local development build from a clean checkout:

```
REVISION=$(git rev-parse HEAD)
SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
docker build --platform linux/amd64 \
  --file pkg/docker/seobserver/Dockerfile \
  --build-arg IMAGE_VERSION=development \
  --build-arg SOURCE_REVISION="$REVISION" \
  --build-arg SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  --tag keydb-seobserver:development .
```

Direct local builds are not releases. Only the CI artifact attached to an
annotated `v6.3.3-seobserver.N` tag is publishable.

## Historical upstream image

The root `pkg/docker/Dockerfile` is the historical upstream recipe. It clones
the requested branch from `Snapchat/KeyDB` and therefore must not be used for a
SEObserver release.

This Dockerfile will clone the KeyDB repo, build, and generate a Docker image you can use.

To build, use experimental mode to enable use of build args. Tag the build and specify branch name. The command below will generate your docker image:

```
DOCKER_CLI_EXPERIMENTAL=enabled docker build --build-arg BRANCH=<keydbBranch> -t <yourImageName>
```
