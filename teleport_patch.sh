#!/bin/bash

OWNER="All";

while [ "$1" != "" ]; do
	OWNER="$1";
	shift
done

if [ ! -e "/usr/local/bin/yq" ]; then

	if [ -f /etc/redhat-release ] ; then
		yum install wget -y
	elif [ -f /etc/debian_version ] ; then
		apt install wget -y
	else
		echo "Not supported OS";
		exit 1;
	fi

	wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
	chmod a+x /usr/local/bin/yq
	
fi

cat <<EOF > ./teleport_patch.yaml
version: v3
ssh_service:
  labels:
    owner: $OWNER
  commands:
  - name: ipadd
    command: ["/bin/sh", "-c", "hostname -I | tr ' ' '\n' | head -n1"]
    period: 1m0s
  - name: ostype
    command: ["/bin/sh", "-c", "hostnamectl status | grep Operating | awk -F ': ' '{print \$2}'"]
    period: 1m0s
EOF

yq -i ea '. as $item ireduce ({}; . * $item )' /etc/teleport.yaml ./teleport_patch.yaml

systemctl restart teleport.service
