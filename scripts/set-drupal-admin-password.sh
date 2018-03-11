#!/bin/bash
if [[ $# != 1 ]] ; then
  echo "Usage: $0 <password>"
  exit 1
fi

export PWHASH=`docker exec -it uog-drupal-web scripts/password-hash.sh $1|grep 'hash: '|sed -e 's/.*hash: //' -e 's/\s.*//'`
docker exec -i uog-drupal-mysql mysql -udrupal -p`cat ../env/mysql.override.env|grep MYSQL_PASSWORD|sed -e 's/.*=//'` `cat ../env/mysql.override.env|grep MYSQL_DATABASE|sed -e 's/.*=//'` -e "update users set pass = '${PWHASH}' where uid='1';"

