FROM nginx:1.27-alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy nginx config
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy served content
COPY serve/ /usr/share/nginx/html/

# Copy entrypoint that injects env vars into runtime config
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Generate build metadata (stored outside html so bind-mount doesn't hide it)
ARG GIT_SHA=unknown
ARG GIT_BRANCH=unknown
ARG BUILD_TIME=unknown
RUN mkdir -p /etc/bootstrap && \
    echo "{\"git_sha\":\"${GIT_SHA}\",\"git_branch\":\"${GIT_BRANCH}\",\"build_time\":\"${BUILD_TIME}\"}" \
    > /etc/bootstrap/build-info.json

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO /dev/null http://127.0.0.1/api/health || exit 1

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]

LABEL maintainer="bootstrap-server"
LABEL description="Serves Ansible playbooks and bootstrap scripts for VM/LXC setup"

