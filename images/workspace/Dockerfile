FROM codercom/enterprise-base:ubuntu

ARG TARGETARCH=amd64
ARG CODER_VERSION=
ARG CODER_BINARY_URL=
ARG INSTALL_CODE_SERVER=true
ARG CODE_SERVER_VERSION=4.105.1
ARG INSTALL_CLAUDE_CODE=true

USER root

# The Coder agent.
RUN set -eu; \
	if [ -n "${CODER_BINARY_URL}" ]; then \
		curl -fsSL --retry 5 -o /usr/local/bin/coder "${CODER_BINARY_URL}"; \
	elif [ -n "${CODER_VERSION}" ]; then \
		v="${CODER_VERSION#v}"; \
		curl -fsSL --retry 5 "https://github.com/coder/coder/releases/download/v${v}/coder_${v}_linux_${TARGETARCH}.tar.gz" \
			| tar -xz -C /usr/local/bin ./coder; \
	else \
		echo "Set CODER_VERSION or CODER_BINARY_URL" >&2; exit 1; \
	fi; \
	chmod 755 /usr/local/bin/coder; \
	/usr/local/bin/coder version

# code-server, outside /home so a home volume does not hide it. The
# code-server module uses it with offline = true.
RUN set -eu; \
	if [ "${INSTALL_CODE_SERVER}" = true ]; then \
		curl -fsSL https://code-server.dev/install.sh \
			| sh -s -- --method=standalone --prefix=/opt/code-server --version "${CODE_SERVER_VERSION}"; \
	fi

# Claude Code, outside /home for the same reason. The template runs
# /opt/claude/bin/claude.
RUN set -eu; \
	if [ "${INSTALL_CLAUDE_CODE}" = true ]; then \
		export HOME=/opt/claude; \
		mkdir -p /opt/claude/bin; \
		curl -fsSL https://claude.ai/install.sh | bash; \
		ln -sf "$(readlink -f /opt/claude/.local/bin/claude)" /opt/claude/bin/claude; \
		chmod -R a+rX /opt/claude; \
		/opt/claude/bin/claude --version; \
	fi

# Google Chrome, and the Go and Node.js toolchains.
RUN set -eu; \
	curl -fsSLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; \
	apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/chrome.deb; \
	rm -rf /tmp/chrome.deb /var/lib/apt/lists/*; \
	curl -fsSL https://go.dev/dl/go1.25.4.linux-amd64.tar.gz | tar -xz -C /usr/local; \
	ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
	ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
	curl -fsSL https://nodejs.org/dist/v22.21.1/node-v22.21.1-linux-x64.tar.xz | tar -xJ -C /usr/local --strip-components=1; \
	echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh

# Cloud and Kubernetes CLIs, JavaScript tools, and a browser for
# Playwright, outside /home.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN set -eu; \
	curl -fsSLo /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip; \
	unzip -q /tmp/awscli.zip -d /tmp; \
	/tmp/aws/install; \
	rm -rf /tmp/aws /tmp/awscli.zip; \
	curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.34.2/bin/linux/amd64/kubectl; \
	chmod 755 /usr/local/bin/kubectl; \
	npm install -g pnpm typescript playwright; \
	playwright install chromium; \
	chmod -R a+rX /opt/ms-playwright

USER coder
WORKDIR /home/coder
