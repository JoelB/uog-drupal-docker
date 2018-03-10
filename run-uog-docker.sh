#!/bin/bash

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ $# != 3 ]] ; then
  echo "Usage: $0 <gzipped mysql backup> <tar.gz drupal files backup> <settings template file>"
  exit 1
fi

MYSQL_BACKUP_FILENAME=$1
DRUPAL_FILES_BACKUP_FILENAME=$2
SETTINGS_TEMPLATE_FILENAME=$3

if [[ ! -f ${MYSQL_BACKUP_FILENAME} ]] ; then
  echo "MySQL backup file not found: $1"
  exit 1
fi

if [[ ! -f ${DRUPAL_FILES_BACKUP_FILENAME} ]] ; then
  echo "Drupal files backup file not found: $2"
  exit 1
fi

if [[ ! -f ${SETTINGS_TEMPLATE_FILENAME} ]] ; then
  echo "Settings template file not found: $3"
  exit 1
fi

# Generate a random root password for the DB server
#MYSQL_DBNAME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_DBNAME="engineering"
MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
MYSQL_DRUPAL_USER="drupal"
MYSQL_DRUPAL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
DRUPAL_ADMIN_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

# Start the MySQL container
MYSQL_CONTAINER_ID=`docker run -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} -e MYSQL_DATABASE=${MYSQL_DBNAME} -e MYSQL_USER=${MYSQL_DRUPAL_USER} -e MYSQL_PASSWORD=${MYSQL_DRUPAL_PASSWORD} -d mysql:5`
if [ "$?" -ne 0 ] ; then
  echo "Failed to create MySQL container. Exiting..."
  exit 1
fi
MYSQL_CONTAINER_NAME=`docker inspect --format='{{.Name}}' ${MYSQL_CONTAINER_ID}`

echo "Database server container successfully created as ${MYSQL_CONTAINER_NAME}."

WEB_CONTAINER_ID=`docker run --detach --link ${MYSQL_CONTAINER_ID}:mysql joelb/uog-drupal7`
if [ "$?" -ne 0 ] ; then
  echo "Failed to create Drupal container. Exiting..."
  exit 1
fi
WEB_CONTAINER_NAME=`docker inspect --format='{{.Name}}' ${WEB_CONTAINER_ID}`
IP_ADDRESS=`docker inspect --format='{{.NetworkSettings.Networks.bridge.IPAddress}}' ${WEB_CONTAINER_ID}`
echo "Drupal web server container successfully created as ${WEB_CONTAINER_NAME} with IP address ${IP_ADDRESS}."

echo "Creating the settings file..."
(docker exec -i ${WEB_CONTAINER_NAME} bash -c "cat > /var/www/html/sites/default/settings.php") < \
    <(cat dockervol/settings.php.template | sed -e "s/%DBNAME%/${MYSQL_DBNAME}/" \
                                                -e "s/%USER%/${MYSQL_DRUPAL_USER}/" \
                                                -e "s/%PASSWORD%/${MYSQL_DRUPAL_PASSWORD}/" \
                                                -e "s/%MYSQLHOST%/${MYSQL_CONTAINER_NAME/\//}/")

if [ "$?" -ne 0 ] ; then
  echo "Failed to populate settings file."
fi

echo "Extracting the drupal files from backup..."
docker exec -i ${WEB_CONTAINER_NAME} ln -s /var/www/html/sites/default /var/www/html/sites/uoguelph.ca.engineering && \
docker exec -i ${WEB_CONTAINER_NAME} mkdir -p /var/www/html/sites/uoguelph.ca.engineering/files/{private,public} && \
(docker exec -i ${WEB_CONTAINER_NAME} tar xzpf - -C /var/www/html/sites/uoguelph.ca.engineering/files/public) < ${DRUPAL_FILES_BACKUP_FILENAME} && \
docker exec -i ${WEB_CONTAINER_NAME} chown -R www-data:www-data /var/www/html/sites/uoguelph.ca.engineering/files && \
docker exec -i ${WEB_CONTAINER_NAME} mkdir /var/www/html/sites/all/libraries/tcpdf/images && \
docker exec -i ${WEB_CONTAINER_NAME} chown www-data:www-data /var/www/html/sites/all/libraries/tcpdf/images

if [ "$?" -ne 0 ] ; then
  echo "Failed to extract files."
fi

# It takes some time for MySQL to come up and docker to create the user and DB so we sleep...
echo -n "Sleeping until MySQL is ready..."
while ! docker exec -i ${MYSQL_CONTAINER_NAME} mysqlshow -u${MYSQL_DRUPAL_USER} -p${MYSQL_DRUPAL_PASSWORD} ${MYSQL_DBNAME} &> /dev/null; do
  echo -n "."
  sleep 1
done
echo ""

echo "Populating the MySQL database from backup..."
docker exec -i ${MYSQL_CONTAINER_NAME} mysql -u${MYSQL_DRUPAL_USER} -p${MYSQL_DRUPAL_PASSWORD} ${MYSQL_DBNAME} <  <(cat ${MYSQL_BACKUP_FILENAME}|gunzip) &> /dev/null

if [ "$?" -ne 0 ] ; then
  echo "Failed to populate database."
fi

echo "Setting the drupal admin password..."
DRUPAL_PWHASH=`docker exec -i ${WEB_CONTAINER_NAME} scripts/password-hash.sh ${DRUPAL_ADMIN_PASSWORD}|grep "hash: "|sed -e 's/.*hash: //'`
#echo "DEBUG: hash: ${DRUPAL_PWHASH}"
docker exec -i ${MYSQL_CONTAINER_NAME} mysql -u${MYSQL_DRUPAL_USER} -p${MYSQL_DRUPAL_PASSWORD} ${MYSQL_DBNAME} -e "update users set pass = '${DRUPAL_PWHASH}' where uid='1';" &>/dev/null
if [ "$?" -ne 0 ] ; then
  echo "Failed to set admin password!"
fi
echo "Done!"

echo "MySQL hostname will be ${MYSQL_CONTAINER_NAME} and the DB name is ${MYSQL_DBNAME}."
echo "MySQL credentials are:"
echo "  Root:        root:${MYSQL_ROOT_PASSWORD}"
echo "  Drupal user: ${MYSQL_DRUPAL_USER}:${MYSQL_DRUPAL_PASSWORD}"
echo ""
echo "You can access the drupal container at http://${IP_ADDRESS}"
echo "  and login with wbsadmin:${DRUPAL_ADMIN_PASSWORD}"
echo ""
echo "To get shell in the Drupal container, run:"
echo " docker exec -it ${WEB_CONTAINER_NAME} /bin/bash"
echo ""
echo "To destroy this set of containers, run:"
echo " docker stop ${MYSQL_CONTAINER_NAME} ${WEB_CONTAINER_NAME} && docker rm ${MYSQL_CONTAINER_NAME} ${WEB_CONTAINER_NAME}"
echo ""

# ln -s /var/www/html/sites/default /var/www/html/sites/uoguelph.ca.engineering
# mkdir -p /var/www/html/sites/uoguelph.ca.engineering/files/{private,public}
# tar xvzpf /host/Engineering-2018-03-09T10-05-11.tar.gz -C /var/www/html/sites/uoguelph.ca.engineering/files/public
# chown -R www-data:www-data /var/www/html/sites/uoguelph.ca.engineering/files
