FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# System dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    tmux \
    git \
    ca-certificates \
    openssh-client \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ttyd - web-based terminal (WebSocket, works with browsers + Node.js WS clients)
RUN TTYD_VERSION=$(curl -s https://api.github.com/repos/tsl0922/ttyd/releases/latest | jq -r '.tag_name') \
    && wget -qO /usr/local/bin/ttyd \
    "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
    && chmod +x /usr/local/bin/ttyd

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# tmux config: larger scrollback, mouse, stable window size
RUN printf '%s\n' \
    'set -g history-limit 100000' \
    'set -g mouse on' \
    'set -g default-terminal "xterm-256color"' \
    'set -ga terminal-overrides ",xterm-256color:Tc"' \
    'setw -g aggressive-resize on' \
    'set-option -g allow-rename off' \
    > /root/.tmux.conf

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ttyd WebSocket port
EXPOSE 7681

ENTRYPOINT ["/entrypoint.sh"]
