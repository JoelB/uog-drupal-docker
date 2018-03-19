# from https://www.drupal.org/requirements/php#drupalversions
FROM drupal:7

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh","apache2-foreground"]

RUN set -ex; \
  apt-get update; \
  apt-get install -y --no-install-recommends git;

# Set up self-signed SSL
RUN set -ex; \
  apt-get install -y ssl-cert; \
  make-ssl-cert generate-default-snakeoil --force-overwrite; \
  a2enmod ssl; \
  a2ensite default-ssl; \
  service apache2 restart

# Add the php LDAP extension and then clean up the dependencies
RUN set -ex; \
  savedAptMark="$(apt-mark showmanual)"; \
  apt-get install -y --no-install-recommends libldap2-dev; \
  docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu; \
  docker-php-ext-install ldap; \
  \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
  apt-mark auto '.*' > /dev/null; \
  apt-mark manual $savedAptMark; \
  ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
    | awk '/=>/ { print $3 }' \
    | sort -u \
    | xargs -r dpkg-query -S \
    | cut -d: -f1 \
    | sort -u \
    | xargs -rt apt-mark manual; \
  \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# Clean out the original Drupal install and put in our own
RUN rm -rf /var/www/html \
  && mkdir /var/www/html \
  && chown www-data:www-data /var/www/html \
  && cd /var/www/html \
  && git clone https://github.com/ccswbs/hjckrrh.git \
  && mv hjckrrh/* hjckrrh/.[a-zA-Z]* . \
  && rm -r hjckrrh \
  && chown -R www-data:www-data sites modules themes

# vim:set ft=dockerfile:
