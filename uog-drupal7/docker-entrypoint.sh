#!/bin/bash

set -e

if [[ ! -f /root/first_run ]] ; then
  if [[ ! -z "${MYSQL_HOST}" && \
        ! -z "${MYSQL_USER}" && \
        ! -z "${MYSQL_PASSWORD}" && \
        ! -z "${MYSQL_DBNAME}" && \
        -f /restore/settings.php.template \
     ]]
  then
    cp /restore/settings.php.template /var/www/html/sites/default/settings.php
    chown www-data:www-data /var/www/html/sites/default/settings.php
    sed -i "s/%MYSQLHOST%/${MYSQL_HOST}/" /var/www/html/sites/default/settings.php
    sed -i "s/%USER%/${MYSQL_USER}/" /var/www/html/sites/default/settings.php
    sed -i "s/%PASSWORD%/${MYSQL_PASSWORD}/" /var/www/html/sites/default/settings.php
    sed -i "s/%DBNAME%/${MYSQL_DBNAME}/" /var/www/html/sites/default/settings.php
  fi
  
  if [[ ! -z "${DRUPAL_RESTORE_ARCHIVE}" && -f "${DRUPAL_RESTORE_ARCHIVE}"  ]]
  then
    mkdir -p /var/www/html/sites/default/files/{private,public}
    tar xpf ${DRUPAL_RESTORE_ARCHIVE} -C /var/www/html/sites/default/files/public
    chown -R www-data:www-data /var/www/html/sites/default/files
    if [[  ! -z "${DRUPAL_RESTORE_SITENAME}" ]] ; then
      ln -s /var/www/html/sites/default /var/www/html/sites/${DRUPAL_RESTORE_SITENAME}
    fi
  fi
fi
touch /root/first_run


# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
        set -- apache2-foreground "$@"
fi

exec "$@"
