#!/bin/bash
TEMP_REDIS_PASS="";
OLD_REDIS_PASS="";
MAIL_REDIS_PASS="";
IO_REDIS_PASS="";
DS_REDIS_PASS="";

## Edit these Variables
REDIS_PASS="";
DS_DB_PWD="";
## END Variables


# DocumentServer prepare4shutdown
	bash /usr/bin/documentserver-prepare4shutdown.sh

# Check Redis password
	if [ -z "$REDIS_PASS" ]; then
		OLD_REDIS_PASS="$(grep ^requirepass /etc/redis/redis.conf | cut -d' ' -f2)";
		if [ -z "$OLD_REDIS_PASS" ]; then
			REDIS_PASS="$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)";
		else
			REDIS_PASS="$(grep ^requirepass /etc/redis/redis.conf | cut -d' ' -f2)";
		fi
	fi
# Change Redis password
	echo Change Redis password;

	if [ -e /etc/redis/redis.conf ]; then
		sed -i 's/# requirepass/requirepass/g' /etc/redis/redis.conf;
		sed -i 's/^requirepass .*/requirepass '$REDIS_PASS'/g' /etc/redis/redis.conf;
		
		echo Restart Redis service;
		systemctl restart redis;
	fi


# Change Redis password in CommunityServer
	echo Change Redis password in CommunityServer;

	TEMP_REDIS_PASS=$(cat /var/www/onlyoffice/WebStudio/Web.config | grep 'database="0" password' |  cut -d"=" -f6 | cut -d">" -f1);
	sed -i '/password/s/database="0" password='$TEMP_REDIS_PASS'/database="0" password="'$REDIS_PASS'"/g' /var/www/onlyoffice/WebStudio/Web.config;

	TEMP_REDIS_PASS=$(cat /var/www/onlyoffice/Services/TeamLabSvc/TeamLabSvc.exe.config | grep 'database="0" password' |  cut -d"=" -f6 | cut -d">" -f1);
	sed -i '/password/s/database="0" password='$TEMP_REDIS_PASS'/database="0" password="'$REDIS_PASS'"/g' /var/www/onlyoffice/Services/TeamLabSvc/TeamLabSvc.exe.config;

	TEMP_REDIS_PASS=$(cat /var/www/onlyoffice/Services/Jabber/ASC.Xmpp.Server.Launcher.exe.config | grep 'database="0" password' |  cut -d"=" -f5 | cut -d">" -f1);
	sed -i '/password/s/database="0" password='$TEMP_REDIS_PASS'/database="0" password="'$REDIS_PASS'"/g' /var/www/onlyoffice/Services/Jabber/ASC.Xmpp.Server.Launcher.exe.config;
	
	MAIL_REDIS_PASS=$(grep "Password" /etc/onlyoffice/communityserver/mail.json);
		if [ -z "$MAIL_REDIS_PASS" ]; then
			sed -i '/Database/a"Password": "'$REDIS_PASS'",' /etc/onlyoffice/communityserver/mail.json;
		else
			sed -i 's/"Password".*/"Password": "'$REDIS_PASS'",/g' /etc/onlyoffice/communityserver/mail.json;
		fi
	
	IO_REDIS_PASS=$(grep "password:" /var/www/onlyoffice/Services/ASC.Socket.IO/app.js);
		if [ -z "$IO_REDIS_PASS" ]; then
			sed -i '/redis:port/a password: "'$REDIS_PASS'",' /var/www/onlyoffice/Services/ASC.Socket.IO/app.js;
		else
			sed -i 's/password.*/password: "'$REDIS_PASS'",/g' /var/www/onlyoffice/Services/ASC.Socket.IO/app.js;	
		fi
		
		
# Restart services CommunityServer
	echo Restart services CommunityServer;
	
	systemctl restart monoserve monoserveApiSystem
	systemctl restart onlyofficeBackup onlyofficeJabber onlyofficeNotify onlyofficeStorageMigrate onlyofficeWebDav onlyofficeControlPanel onlyofficeMailAggregator onlyofficeRadicale onlyofficeTelegram onlyofficeFeed onlyofficeMailCleaner onlyofficeSocketIO onlyofficeThumbnailBuilder onlyofficeFilesTrashCleaner onlyofficeMailImap onlyofficeSsoAuth onlyofficeThumb onlyofficeIndex onlyofficeMailWatchdog onlyofficeStorageEncryption onlyofficeUrlShortener 

# Change Redis password in DocumentServer
	echo Change Redis password in DocumentServer;

	if [ -e /etc/onlyoffice/documentserver/local-production-linux.json ]; then

		DS_REDIS_PASS="$(cat /etc/onlyoffice/documentserver/local-production-linux.json | jq .services.CoAuthoring.redis.options.password -r)";

		if [ -z "$DS_REDIS_PASS" ] ||  [ "$DS_REDIS_PASS" == null ]; then
			echo "Warning! Config local-production-linux.json exists. But does not contain a parameter: CoAuthoring.redis.options";
			exit 1;
		else
			sed -i 's/"password": "'${DS_REDIS_PASS}'"/"password": "'${REDIS_PASS}'"/g' /etc/onlyoffice/documentserver/local-production-linux.json;
		fi
	else
	
echo Create config local-production-linux.json;
cat > /etc/onlyoffice/documentserver/local-production-linux.json <<END
{
	"services": {
                "CoAuthoring": {
			"redis": {
                                "options": {
                                	"password": "$REDIS_PASS"
                                	}
				}
			}
		}
}   
END

	chown onlyoffice:onlyoffice /etc/onlyoffice/documentserver/local-production-linux.json

	fi


# Change PostgreSQL in DocumentServer
	echo Change password in PostgreSQL;
	
	if [ -z "$DS_DB_PWD" ]; then
			OLD_DS_DB_PWD="$(cat /etc/onlyoffice/documentserver/local.json | jq .services.CoAuthoring.sql.dbPass -r)";
			if [ "$OLD_DS_DB_PWD" == "onlyoffice" ]; then
				declare -x DS_DB_PWD="$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)";
			else
				declare -x DS_DB_PWD="$(cat /etc/onlyoffice/documentserver/local.json | jq .services.CoAuthoring.sql.dbPass -r)";
				fi
		fi

	su - postgres -s /bin/bash -c "psql -c \"ALTER USER onlyoffice WITH PASSWORD '${DS_DB_PWD}';\""	

	sed -i 's/"dbPass".*/"dbPass": "'${DS_DB_PWD}'",/g' /etc/onlyoffice/documentserver/local.json;
			
	sed "/host\s*all\s*all\s*127\.0\.0\.1\/32\s*trust$/s|trust$|password|" -i /var/lib/pgsql/data/pg_hba.conf;
	sed "/host\s*all\s*all\s*::1\/128\s*trust$/s|trust$|password|" -i /var/lib/pgsql/data/pg_hba.conf;
	
	echo Restart PostgreSQL service
	systemctl restart postgresql;
	
# Restart services DocumentServer
	echo Restart DocumentServer service
	systemctl restart ds-converter ds-docservice ds-metrics
