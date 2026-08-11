#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM node:22-bookworm-slim

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION=1.19
RUN set -eux; \
# save list of currently installed packages for later so we can clean up
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
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
# clean up fetch dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true

ENV NODE_ENV=production

# Ghost-CLI is installed from source rather than "npm install -g ghost-cli" so that
# pnpm can resolve the dependency tree from the lockfile committed alongside the tag
# ("npm install -g" ignores lockfiles entirely, so the tree it produces varies by build date)
ENV GHOST_CLI_VERSION=1.30.1
ENV GHOST_CLI_SHA=6c711179d9669c1938aa506f92a82c602d6c202e
ENV GHOST_CLI_INSTALL=/usr/local/lib/ghost-cli
RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates git; \
	\
	corepack enable; \
	\
# corepack's downloads, pnpm's metadata cache and pnpm's store all derive their location
# from these, so pointing them at /tmp keeps every throwaway byte in one place
	export XDG_CACHE_HOME=/tmp/xdg-cache XDG_DATA_HOME=/tmp/xdg-data; \
	\
	mkdir -p "$GHOST_CLI_INSTALL"; \
	cd "$GHOST_CLI_INSTALL"; \
	git init --quiet .; \
	git remote add origin https://github.com/TryGhost/Ghost-CLI.git; \
# fetching the commit by hash means git's own object verification pins the source
# (a moved tag or a re-rolled release tarball cannot change what we get)
	git fetch --quiet --depth 1 origin "$GHOST_CLI_SHA"; \
	git checkout --quiet FETCH_HEAD; \
	[ "$(node -p 'require("./package.json").version')" = "$GHOST_CLI_VERSION" ]; \
	\
# "--frozen-lockfile" is the point of all this: it installs pnpm-lock.yaml exactly, or fails
	pnpm install --prod --frozen-lockfile; \
	\
	ln -s "$GHOST_CLI_INSTALL/bin/ghost" /usr/local/bin/ghost; \
	\
# drop what "npm publish" would not have shipped (see "files" in Ghost-CLI's package.json)
	rm -rf .git test .github; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	rm -rf /tmp/xdg-cache /tmp/xdg-data; \
	npm cache clean --force; \
	\
	ghost --version

ENV GHOST_INSTALL=/var/lib/ghost
ENV GHOST_CONTENT=/var/lib/ghost/content

ENV GHOST_VERSION=6.57.1

RUN set -eux; \
	mkdir -p "$GHOST_INSTALL"; \
	chown node:node "$GHOST_INSTALL"; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends g++ make python3; \
	\
	gosu node ghost install "$GHOST_VERSION" --db mysql --dbhost mysql --no-prompt --no-stack --no-setup --dir "$GHOST_INSTALL"; \
	\
# Tell Ghost to listen on all ips and not prompt for additional configuration
	cd "$GHOST_INSTALL"; \
	gosu node ghost config --no-prompt --ip '::' --port 2368 --url 'http://localhost:2368'; \
	gosu node ghost config paths.contentPath "$GHOST_CONTENT"; \
	\
# make a config.json symlink for NODE_ENV=development (and sanity check that it's correct)
	gosu node ln -s config.production.json "$GHOST_INSTALL/config.development.json"; \
	readlink -f "$GHOST_INSTALL/config.development.json"; \
	\
# need to save initial content for pre-seeding empty volumes
	mv "$GHOST_CONTENT" "$GHOST_INSTALL/content.orig"; \
	mkdir -p "$GHOST_CONTENT"; \
	chown node:node "$GHOST_CONTENT"; \
	chmod 1777 "$GHOST_CONTENT"; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	gosu node pnpm store prune; \
	gosu node npm cache clean --force; \
	npm cache clean --force; \
# none of these are needed to run Ghost: corepack re-downloads pnpm on demand and node-gyp
# only matters while compiling native modules, which is finished by this point
	rm -rf /home/node/.cache/node/corepack /home/node/.cache/node-gyp /home/node/.cache/pnpm; \
	\
	# test that the optional dependencies are installed and loadable
	cd current; \
	gosu node node -e 'require("better-sqlite3"); if (!require("@tryghost/image-transform").canTransformFiles()) throw new Error("sharp not installed");'

WORKDIR $GHOST_INSTALL
VOLUME $GHOST_CONTENT

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 2368
CMD ["node", "current/index.js"]
