#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM node:22-alpine3.23

# grab gosu for easy step-down from root (ahead of the Ghost install so it stays cached)
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION=1.19
RUN set -eux; \
	apk add --no-cache --virtual .gosu-deps ca-certificates dpkg gnupg; \
	\
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
	apk del --no-network .gosu-deps; \
	\
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

# the node image claims uid/gid 1000; hand it to Ghost instead, keeping the uid the CLI-based image
# ran as so existing bind mounts still work. "deluser" exists on both bases, so this needs neither
# usermod/groupmod (absent on Alpine) nor a home dir -- the install below creates it.
RUN set -eux; \
	deluser node; \
	rm -rf /home/node; \
	addgroup -g 1000 ghost; \
	adduser -u 1000 -G ghost -h /home/ghost -s /bin/sh -H -D ghost

ENV NODE_ENV=production

ENV GHOST_INSTALL=/home/ghost
ENV GHOST_CONTENT=/home/ghost/content

ENV GHOST_VERSION=6.62.0

# resolved by "versions.sh" so a build cannot pick up a different tarball than the one reviewed
ENV GHOST_TARBALL=https://github.com/TryGhost/Ghost/releases/download/v6.62.0/ghost-6.62.0.tgz
ENV GHOST_SHA256=3f81079d07e2f6fd0365fbc0846b134c12b202dc5fe62b3252cb6ee34fa5c9e3

RUN set -eux; \
# Ghost pins its pnpm by hash in "packageManager", so corepack fetches exactly that one
	corepack enable; \
	\
# everything under the install dir is created by "ghost" rather than chowned afterwards: a recursive
# chown would copy the whole tree into a new layer
	mkdir -p "$GHOST_INSTALL"; \
	chown ghost:ghost "$GHOST_INSTALL"; \
	cd "$GHOST_INSTALL"; \
	\
# corepack downloads and pnpm's cache/store derive their location from these; /tmp keeps them out of
# the install dir, and they are removed below
	export XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data; \
	\
	gosu ghost wget -O ghost.tgz "$GHOST_TARBALL"; \
	echo "$GHOST_SHA256  ghost.tgz" | sha256sum -c -; \
# the release tarball has no leading "package/" component, unlike an npm pack
	gosu ghost tar --extract --file ghost.tgz; \
	rm ghost.tgz; \
	\
# the tarball ships a pruned lockfile, so the tree is installed exactly, not re-solved per build
	gosu ghost pnpm install --prod --frozen-lockfile; \
	\
# install-time inputs only: package.json points 18 deps at "file:components/*.tgz", but pnpm
# extracts them into its virtual store and nothing resolves back here afterwards
	gosu ghost rm -rf "$GHOST_INSTALL/components"; \
	\
# Ghost's own pruner, as used by its production image: drops dependency TypeScript, sourcemaps,
# READMEs and vendored C/C++ (keeping licences and prebuilt .node). The tarball already has the
# "archive" profile applied, so this is mostly node_modules. Node 22 strips the .mts types itself.
	gosu ghost node scripts/prune.mts "$GHOST_INSTALL" --profile=image; \
	\
# make a config.json symlink for NODE_ENV=development (config.production.json is copied in below)
	gosu ghost ln -s config.production.json "$GHOST_INSTALL/config.development.json"; \
	\
# need to save initial content for pre-seeding empty volumes
	gosu ghost mv "$GHOST_INSTALL/content" "$GHOST_INSTALL/content.orig"; \
	gosu ghost mkdir -p "$GHOST_INSTALL/content"; \
	\
# "corepack enable" above repointed the yarn symlinks at corepack, orphaning the standalone copy.
# This does not shrink the image -- those bytes live in a base layer and only get whited out -- but
# it keeps a dead tree out of the runtime filesystem
	rm -rf /opt/yarn-*; \
	rm -rf /tmp/xdg-cache /tmp/xdg-data; \
	npm cache clean --force; \
	\
# test that the optional dependencies are installed and loadable
	node --version; \
	gosu ghost node -e 'require("better-sqlite3"); if (!require("@tryghost/image-transform").canTransformFiles()) throw new Error("sharp not installed");'

# Ghost-CLI used to generate this. Everything in it is overridable via Ghost's "__" env vars, and
# "process" is deliberately absent -- it only ever told Ghost-CLI which process manager to use
COPY --chown=ghost:ghost config.production.json $GHOST_INSTALL/

RUN set -eux; \
# a mount point, so it stays writable whatever uid ends up owning what gets mounted over it
	chmod 1777 "$GHOST_CONTENT"; \
	cd "$GHOST_INSTALL"; \
	node -e 'JSON.parse(require("fs").readFileSync("config.production.json"))'; \
	[ "$(readlink -f config.development.json)" = "$GHOST_INSTALL/config.production.json" ]

WORKDIR $GHOST_INSTALL
VOLUME $GHOST_CONTENT

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 2368
CMD ["node", "index.js"]
