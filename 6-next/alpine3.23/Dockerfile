#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

# ---- build: fetch Ghost, resolve its dependency tree, compile native modules ----
FROM node:22-alpine3.23 AS build

# nothing here reaches the runtime stage, so there is no cleanup to do
RUN set -eux; \
	apk add --no-cache dpkg gnupg

# grab gosu for easy step-down from root (ahead of the Ghost install so it stays cached)
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION=1.19
RUN set -eux; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

ENV GHOST_INSTALL=/home/ghost
ENV GHOST_VERSION=6.61.0

# resolved by "versions.sh" so a build cannot pick up a different tarball than the one reviewed
ENV GHOST_TARBALL=https://github.com/TryGhost/Ghost/releases/download/v6.61.0/ghost-6.61.0.tgz
ENV GHOST_SHA256=d7a4de32641979fd57fa98bd29c128e406aa5421f3dadc04ffe28cb96507e69c

RUN set -eux; \
	mkdir -p "$GHOST_INSTALL"; \
	cd "$GHOST_INSTALL"; \
	\
	wget -O ghost.tgz "$GHOST_TARBALL"; \
	echo "$GHOST_SHA256  ghost.tgz" | sha256sum -c -; \
# the release tarball has no leading "package/" component, unlike an npm pack
	tar --extract --file ghost.tgz; \
	rm ghost.tgz; \
	\
# Ghost pins its pnpm by hash in "packageManager", so corepack fetches exactly that one
	corepack enable; \
	\
# corepack downloads and pnpm's cache/store derive their location from these; /tmp keeps them
# out of the copied tree
	export XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data; \
	\
# the tarball ships a pruned lockfile, so the tree is installed exactly, not re-solved per build
	pnpm install --prod --frozen-lockfile; \
	\
# install-time inputs only: package.json points 18 deps at "file:components/*.tgz", but pnpm
# extracts them into its virtual store and nothing resolves back here afterwards
	rm -rf "$GHOST_INSTALL/components"; \
	\
# Ghost's own pruner, as used by its production image: drops dependency TypeScript, sourcemaps,
# READMEs and vendored C/C++ (keeping licences and prebuilt .node). The tarball already has the
# "archive" profile applied, so this is mostly node_modules. Node 22 strips the .mts types itself.
	node scripts/prune.mts "$GHOST_INSTALL" --profile=image; \
	\
# make a config.json symlink for NODE_ENV=development (config.production.json is copied in below)
	ln -s config.production.json "$GHOST_INSTALL/config.development.json"; \
	\
# need to save initial content for pre-seeding empty volumes
	mv "$GHOST_INSTALL/content" "$GHOST_INSTALL/content.orig"; \
	mkdir -p "$GHOST_INSTALL/content"; \
	\
# test that the optional dependencies are installed and loadable
	node -e 'require("better-sqlite3"); if (!require("@tryghost/image-transform").canTransformFiles()) throw new Error("sharp not installed");'

# ---- runtime ----
FROM alpine:3.23

RUN set -eux; \
# libstdc++ is what node itself links against, plus better-sqlite3 and sharp
	apk add --no-cache ca-certificates libstdc++; \
	\
# uid 1000 is unclaimed on this base and matches what the CLI-based image ran as, so existing bind
# mounts keep working. No home dir: the COPY below creates it, without /etc/skel's dotfiles
	addgroup -g 1000 ghost; \
	adduser -u 1000 -G ghost -h /home/ghost -s /bin/sh -H -D ghost

# node, npm, npx, corepack and gosu all live here. "corepack enable" in the build stage repointed
# the yarn symlinks at corepack instead of the standalone yarn under /opt, so this tree resolves on
# its own. Keeping npm/corepack matches the tooling the Ghost-CLI image exposed.
# (node's own docker-entrypoint.sh tags along; ours is copied over it below.)
COPY --from=build /usr/local /usr/local

ENV NODE_ENV=production

ENV GHOST_INSTALL=/home/ghost
ENV GHOST_CONTENT=/home/ghost/content

ENV GHOST_VERSION=6.61.0

COPY --from=build --chown=ghost:ghost /home/ghost /home/ghost

# Ghost-CLI used to generate this. Everything in it is overridable via Ghost's "__" env vars, and
# "process" is deliberately absent -- it only ever told Ghost-CLI which process manager to use
COPY --chown=ghost:ghost config.production.json $GHOST_INSTALL/

RUN set -eux; \
# a mount point, so it stays writable whatever uid ends up owning what gets mounted over it
	chmod 1777 "$GHOST_CONTENT"; \
	\
# node --version catches a missing libstdc++/libatomic; the module loads prove the copied tree
# still resolves outside the build stage
	node --version; \
	cd "$GHOST_INSTALL"; \
	node -e 'JSON.parse(require("fs").readFileSync("config.production.json"))'; \
	[ "$(readlink -f config.development.json)" = "$GHOST_INSTALL/config.production.json" ]; \
	gosu ghost node -e 'require("better-sqlite3"); if (!require("@tryghost/image-transform").canTransformFiles()) throw new Error("sharp not installed");'

WORKDIR $GHOST_INSTALL
VOLUME $GHOST_CONTENT

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 2368
CMD ["node", "index.js"]
