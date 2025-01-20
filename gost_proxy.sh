#!/bin/bash

# Edit this variables
PROXY_ADDR="http://login:password@domain.name:port";
PROXY_CLIENT_ADDR="127.0.0.1";
PROXY_CLIENT_PORT="8888";

GOST_SERVICE="";
CHANGE_ENV="";
ELASTIC_INSTALL="";
ELASTIC_VERSION="7.16.3";
ELASTIC_DIST=$(echo $ELASTIC_VERSION | awk '{ print int($1) }');

root_checking () {
	if [ ! $( id -u ) -eq 0 ]; then
		echo "To perform this action you must be logged in with root rights"
		exit 1;
	fi
}

root_checking

if [ -f /etc/redhat-release ] ; then
	yum install curl -y
elif [ -f /etc/debian_version ] ; then
	apt install gnupg2 curl -y
else
	echo "Not supported OS";
	exit 1;
fi

while [ "$1" != "" ]; do
	case $1 in
		-p | --proxy )
			if [ "$2" != "" ]; then
				PROXY_ADDR="$2";
				shift
			fi
		;;
		-d | --disable )
			systemctl disable --now gost.service;
			kill -9 $(ps -aux | grep 'gost -L' | head -n1 | awk '{print $2}');
			sed -i '/export http.*/d' /etc/environment
			source /etc/environment
			echo 'Run "source /etc/environment" to reload env';
			export http_proxy='';
			export https_proxy='';
			
			echo ' ';
			echo 'Edit proxy variables config:';
			echo 'export http_proxy=""';
			echo 'export https_proxy=""';
			echo 'Or do logout';
			exit 1;
		;;
		-g | --gost )
			if [ "$2" == "i" ] || [ "$2" == "install" ]; then
				if [ ! -e /usr/local/bin/gost ] ; then
					bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install;
				fi
				shift
			fi
		;;
		-s | --service )
			if [ "$2" == "i" ] || [ "$2" == "install" ]; then
				GOST_SERVICE="true";
				shift
			fi
		;;
		-e | --elastic )
			if [ "$2" == "i" ] || [ "$2" == "install" ]; then
				ELASTIC_INSTALL="true";
				shift
			elif [ "$2" == "d" ] || [ "$2" == "delete" ]; then
				if [ -e /etc/default/elasticsearch ]; then
					sed -i 's/^ES_JAVA_OPTS/#ES_JAVA_OPTS/g' /etc/default/elasticsearch;
				elif [ -e /etc/sysconfig/elasticsearch ]; then
					sed -i 's/^ES_JAVA_OPTS/#ES_JAVA_OPTS/g' /etc/sysconfig/elasticsearch;
				fi
				systemctl daemon-reload
				systemctl restart elasticsearch
				exit 1;
			fi
		;;
		-y | --yes )
			if [ "$2" == "i" ] || [ "$2" == "install" ]; then
				CHANGE_ENV="true";
				shift
			fi
		;;
		"-?" | -h | --help )
			echo "Created by grigalste";
			echo " ";
			echo "Usage: $0 [OPTIONS] [PARAM]";
			echo "-g i or --gost install = install GoST"
			echo "-s i or --service install = install service GoST"
			echo "-e i or --elastic install = install ElasticSearch"
			echo "-p i or --proxy http2://login:password@domain.name:port"
			echo "-y i or --yes = Add proxy in /etc/environment"
			echo "-d i or --disable = Disable GoST service and process, delete proxy in /etc/environment"
			echo " ";
			echo "Example:";
			echo "bash $0 -g i -s i -e i -y i -p http2://login:password@domain.name:port";
			exit 1;
		;;
	esac
	shift
done

if [ "$GOST_SERVICE" == "true" ]; then

cat > /etc/systemd/system/gost.service <<END
[Unit]
Description=GO Simple Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L http://${PROXY_CLIENT_ADDR}:${PROXY_CLIENT_PORT} -F "${PROXY_ADDR}" 2>&1 /var/log/gost_log.txt
Restart=always

[Install]
WantedBy=multi-user.target
END

	systemctl daemon-reload
	systemctl enable --now gost.service
fi

if [ ! -e /etc/systemd/system/gost.service ] ; then
	gost -L http://${PROXY_CLIENT_ADDR}:${PROXY_CLIENT_PORT} -F "${PROXY_ADDR}" 2>&1 gost_log.txt &
	GOST_SERVICE="process";
fi

export http_proxy="http://${PROXY_CLIENT_ADDR}:${PROXY_CLIENT_PORT}/";
export https_proxy="http://${PROXY_CLIENT_ADDR}:${PROXY_CLIENT_PORT}/";

sleep 3;

if [ "$ELASTIC_INSTALL" == "true" ]; then

	if [ -f /etc/redhat-release ] ; then

		rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

cat > /etc/yum.repos.d/elasticsearch.repo <<END
[elasticsearch]
name=Elasticsearch repository for ${ELASTIC_DIST}.x packages
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_DIST}.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=0
autorefresh=1
type=rpm-md
proxy=http://${PROXY_CLIENT_ADDR}:${PROXY_CLIENT_PORT}
END
		yum -y check-update
		yum -y install elasticsearch-${ELASTIC_VERSION} --enablerepo=elasticsearch

	elif [ -f /etc/debian_version ] ; then

		curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/elastic-${ELASTIC_DIST}.x.gpg --import
		echo "deb [signed-by=/usr/share/keyrings/elastic-${ELASTIC_DIST}.x.gpg] https://artifacts.elastic.co/packages/${ELASTIC_DIST}.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-${ELASTIC_DIST}.x.list
		chmod 644 /usr/share/keyrings/elastic-${ELASTIC_DIST}.x.gpg

		apt-get -y update
		
		if ! dpkg -l | grep -q "elasticsearch"; then
			apt-get install -yq elasticsearch=${ELASTIC_VERSION}
		fi

	else
			echo "Not supported OS";
			exit 1;
	fi

	if [ -e /etc/default/elasticsearch ]; then
		sed -i 's/#ES_JAVA_OPTS/ES_JAVA_OPTS/g' /etc/default/elasticsearch;
		sed -i 's/^ES_JAVA_OPTS=.*/ES_JAVA_OPTS=" -Dhttp.proxyHost='${PROXY_CLIENT_ADDR}' -Dhttp.proxyPort='${PROXY_CLIENT_PORT}' -Dhttps.proxyHost='${PROXY_CLIENT_ADDR}' -Dhttps.proxyPort='${PROXY_CLIENT_PORT}'"/g' /etc/default/elasticsearch;
		systemctl daemon-reload
		systemctl restart elasticsearch
	elif [ -e /etc/sysconfig/elasticsearch ]; then
		sed -i 's/#ES_JAVA_OPTS/ES_JAVA_OPTS/g' /etc/sysconfig/elasticsearch;
		sed -i 's/^ES_JAVA_OPTS=.*/ES_JAVA_OPTS=" -Dhttp.proxyHost='${PROXY_CLIENT_ADDR}' -Dhttp.proxyPort='${PROXY_CLIENT_PORT}' -Dhttps.proxyHost='${PROXY_CLIENT_ADDR}' -Dhttps.proxyPort='${PROXY_CLIENT_PORT}'"/g' /etc/sysconfig/elasticsearch;
		systemctl daemon-reload
		systemctl restart elasticsearch
	fi
	
	echo ' ';
	echo "Done. Elastisearch installed.";
fi

if [ "$GOST_SERVICE" == "true" ]; then
	echo ' ';
	echo "GoST Service installed and started.";
elif [ "$GOST_SERVICE" == "process" ]; then
	echo ' ';
	echo 'Use GoST proxy.';
	echo 'Start client:';
	echo 'gost -L http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}' -F "'${PROXY_ADDR}'" 2>&1 gost_log.txt &';
	echo ' ';
	echo "Kill GoST process";
	kill -9 $(ps -aux | grep 'gost -L' | head -n1 | awk '{print $2}');
fi

echo ' ';
echo 'Edit proxy variables config:';
echo 'export http_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"';
echo 'export https_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"';

if [ "$CHANGE_ENV" == "true" ]; then
	sed -i '/export http.*/s/^/#/' /etc/environment
	echo 'export http_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"' >> /etc/environment
	echo 'export https_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"' >> /etc/environment
	source /etc/environment
	echo 'Run "source /etc/environment" to reload env';
else
	echo "Add http_proxy to /etc/environment?";
	echo 'Input "y" or "yes":';
	read YESORNO

	if [ "$YESORNO" == "y" ]  || [ "$YESORNO" == "yes" ]; then
		sed -i '/export http.*/s/^/#/' /etc/environment
		echo 'export http_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"' >> /etc/environment
		echo 'export https_proxy="http://'${PROXY_CLIENT_ADDR}':'${PROXY_CLIENT_PORT}'/"' >> /etc/environment
		source /etc/environment
		echo 'Run "source /etc/environment" to reload env';
	fi
fi
