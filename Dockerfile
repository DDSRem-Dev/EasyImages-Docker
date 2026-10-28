FROM debian:bookworm-slim

ENV S6_SERVICES_GRACETIME=30000 \
    S6_KILL_GRACETIME=60000 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_SYNC_DISKS=1 \
    HOME="/root" \
    TERM="xterm" \
    PATH=${PATH}:/command \
    DEBUG=false \
    TZ="Asia/Shanghai" \
    PUID=0 \
    PGID=0

COPY --from=shinsenter/s6-overlay / /
# PHP 7.4 and 8.1 are EOL and do not receive php2shell fixes.
# Bookworm's own PHP is 8.2 (security support ends 2026-12-31), so install
# PHP 8.3 from deb.sury.org and refuse anything older than 8.3.36
# (CVE-2026-109618, CVE-2026-109619).
RUN set -ex && \
    export DEBIAN_FRONTEND=noninteractive && \
    ln -sf /command/with-contenv /usr/bin/with-contenv && \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    apt-get update -y && \
    apt-get install -y \
        bash \
        curl \
        ca-certificates \
        busybox \
        xz-utils \
        procps && \
    curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb && \
    dpkg -i /tmp/debsuryorg-archive-keyring.deb && \
    . /etc/os-release && \
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/php.list && \
    apt-get update -y && \
    cand=$(apt-cache policy php8.3-fpm | awk '/Candidate:/ {print $2; exit}') && \
    dpkg --compare-versions "$cand" ge 8.3.36 || { echo "php8.3-fpm candidate ${cand:-<none>} is older than 8.3.36 (CVE-2026-109618 / CVE-2026-109619)"; exit 1; } && \
    apt-get install -y \
        nginx \
        systemd-standalone-tmpfiles \
        php8.3-cli \
        php8.3-common \
        php8.3-curl \
        php8.3-fpm \
        php8.3-xml \
        php8.3-zip \
        php8.3-gd \
        php8.3-mbstring \
        php8.3-bcmath \
        php8.3-opcache && \
    php -r 'if (version_compare(PHP_VERSION, "8.3.36", "<") || version_compare(PHP_VERSION, "8.4.0", ">=")) { fwrite(STDERR, "PHP ".PHP_VERSION." is not a patched 8.3 release (need >= 8.3.36 for CVE-2026-109618 and CVE-2026-109619)\n"); exit(1); }' && \
    php -m | grep -qx curl && \
    php -m | grep -qx fileinfo && \
    php -m | grep -qx gd && \
    php -m | grep -qx iconv && \
    php -m | grep -qx mbstring && \
    php -m | grep -qx openssl && \
    php -m | grep -qx zip && \
    php -m | grep -qx bcmath && \
    php -m | grep -qx xml && \
    php -m | grep -qx json && \
    php -m | grep -q '^Zend OPcache$' && \
    rm -rf \
        /etc/nginx/sites-enabled/default \
        /etc/nginx/sites-available/default \
        /etc/php/8.3/fpm/pool.d/www.conf && \
    # Set size
    echo "max_execution_time = 6000" > /etc/php/8.3/mods-available/web_size.ini && \
    echo "max_input_time = 6000" >> /etc/php/8.3/mods-available/web_size.ini && \
    echo "memory_limit = 512m" >> /etc/php/8.3/mods-available/web_size.ini && \
    echo "file_uploads = on" >> /etc/php/8.3/mods-available/web_size.ini && \
    echo "upload_tmp_dir = /tmp" >> /etc/php/8.3/mods-available/web_size.ini && \
    echo "upload_max_filesize = 512m" >> /etc/php/8.3/mods-available/web_size.ini && \
    echo "post_max_size = 512m" >> /etc/php/8.3/mods-available/web_size.ini && \
    ln -sf /etc/php/8.3/mods-available/web_size.ini /etc/php/8.3/cli/conf.d/10-web_size.ini && \
    ln -sf /etc/php/8.3/mods-available/web_size.ini /etc/php/8.3/fpm/conf.d/10-web_size.ini && \
    # Set opcache. PHP 8.3 comments enable_cli as 0; the previous image forced it on.
    sed -i "s#;opcache.enable=1#opcache.enable=1#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.enable_cli=0#opcache.enable_cli=1#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.memory_consumption=128#opcache.memory_consumption=128#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.interned_strings_buffer=8#opcache.interned_strings_buffer=8#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.max_accelerated_files=10000#opcache.max_accelerated_files=4000#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.revalidate_freq=2#opcache.revalidate_freq=60#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.validate_timestamps=1#opcache.validate_timestamps=0#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    sed -i "s#;opcache.lockfile_path=/tmp#opcache.lockfile_path=/tmp#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    for ini in /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini; do \
        grep -q '^opcache.enable=1$' "$ini" || exit 1; \
        grep -q '^opcache.enable_cli=1$' "$ini" || exit 1; \
        grep -q '^opcache.memory_consumption=128$' "$ini" || exit 1; \
        grep -q '^opcache.interned_strings_buffer=8$' "$ini" || exit 1; \
        grep -q '^opcache.max_accelerated_files=4000$' "$ini" || exit 1; \
        grep -q '^opcache.revalidate_freq=60$' "$ini" || exit 1; \
        grep -q '^opcache.validate_timestamps=0$' "$ini" || exit 1; \
        grep -q '^opcache.lockfile_path=/tmp$' "$ini" || exit 1; \
    done && \
    # Set php pid
    mkdir -p /run/php && \
    # Set user
    usermod www-data --home /app/web && \
    # Set logs
    sed -i "s#;error_log = php_errors.log#error_log = /logs/php_errors.log#g" /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini && \
    mkdir /logs && \
    touch /logs/nginx_access.log && \
    touch /logs/nginx_error.log && \
    touch /logs/php8.3-fpm.log && \
    touch /logs/php_errors.log && \
    grep -q '^error_log = /logs/php_errors.log$' /etc/php/8.3/fpm/php.ini && \
    grep -q '^error_log = /logs/php_errors.log$' /etc/php/8.3/cli/php.ini && \
    # Clear
    rm -f /usr/sbin/policy-rc.d && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*

ARG EASYIMAGES_VERSION

RUN mkdir -p /app && \
    curl -L https://github.com/icret/EasyImages2.0/archive/refs/tags/${EASYIMAGES_VERSION}.zip | busybox unzip -qd /app - && \
    mv /app/EasyImages2.0-${EASYIMAGES_VERSION} /app/web && \
    curl -L https://github.com/lionsoul2014/ip2region/raw/master/data/ip2region.xdb -o /app/web/app/ip2region/ip2region.xdb && \
    cp -r /app/web/config / && \
    cp -r /app/web/i /

COPY --chmod=755 ./rootfs /

ENTRYPOINT [ "/init" ]

EXPOSE 80
