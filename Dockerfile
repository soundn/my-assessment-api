FROM composer:2 AS vendor

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --no-scripts \
    --optimize-autoloader

FROM dunglas/frankenphp:1-php8.4-alpine

WORKDIR /app

# Pull in OS-level security fixes newer than the base image snapshot.
RUN apk --no-cache upgrade

RUN install-php-extensions pdo_sqlite pdo_mysql opcache

COPY --from=vendor /app/vendor ./vendor
COPY . .
COPY scripts/entrypoint.sh /usr/local/bin/app-entrypoint

RUN mkdir -p /config/caddy /data/caddy database storage/app/private storage/app/public storage/framework/cache storage/framework/sessions storage/framework/testing storage/framework/views storage/logs bootstrap/cache \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data /config/caddy /data/caddy database storage bootstrap/cache \
    && chmod +x /usr/local/bin/app-entrypoint

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/app/database/database.sqlite \
    SERVER_NAME=:8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/api/v1/health || exit 1

USER www-data

ENTRYPOINT ["app-entrypoint"]
CMD ["frankenphp", "php-server", "-r", "public/", "-l", ":8080"]
