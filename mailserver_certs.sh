#!/bin/bash

cat <<EOF > /usr/bin/MailServer-copy-letsencrypt-cert
#!/bin/bash
diff /app/onlyoffice/CommunityServer/data/certs/onlyoffice.crt /app/onlyoffice/MailServer/data/certs/mail.onlyoffice.crt;
if [ \$? -eq 0 ]
then
  echo "The certificate has not been changed";
  exit 0
else
  echo "The certificate has been changed" >&2
  cp -f /app/onlyoffice/CommunityServer/data/certs/onlyoffice.key /app/onlyoffice/MailServer/data/certs/mail.onlyoffice.key;
  cp -f /app/onlyoffice/CommunityServer/data/certs/onlyoffice.crt /app/onlyoffice/MailServer/data/certs/mail.onlyoffice.crt;
  cp -f /app/onlyoffice/CommunityServer/data/certs/stapling.trusted.crt /app/onlyoffice/MailServer/data/certs/mail.onlyoffice.ca-bundle;
  docker restart onlyoffice-mail-server;
  exit 0
fi
EOF
chmod a+x /usr/bin/MailServer-copy-letsencrypt-cert

if [ -d /etc/cron.d ]; then
  echo -e "@weekly root /usr/bin/MailServer-copy-letsencrypt-cert" | tee /etc/cron.d/MailServer-cert
fi

source /usr/bin/MailServer-copy-letsencrypt-cert