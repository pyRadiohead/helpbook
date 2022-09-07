#!/usr/bin/env bash

if [ $# -lt 1 ] ; then
  echo "usage: $0 domain";
  exit
fi
domain=${1#www.}
vhost_ip=$(grep " $domain" /etc/ip_lista | cut -d' ' -f1)
ip=$(dig +short $domain | head -1)
ip_www=$(dig +short www.$domain | head -1)
sa=/etc/apache2/sites-available
vhost_wpmu=000-wordpress.conf

if [[ ! -f $sa/$domain.conf ]]; then
  wpmu_blog=$(sudo -u www-data wp site list --domain=$domain --field=blog_id --path=/home/www/wordpress 2>/dev/null)
  if [[ -z $wpmu_blog ]]; then
    error_msg="$domain does not exist as either single-site or in Wordpress Network"
  else
    if [[ ! -f $sa/$vhost_wpmu ]]; then
      error_msg="$domain exist in Wordpress Network but $sa/$vhost_wpmu is missing."
    else
      docroot=/home/www/wordpress
      servername=$domain
    fi
  fi
else
  docroot=$(grep -E 'DocumentRoot (.*)$' $sa/$domain.conf 2>/dev/null| awk '{print $NF}')
  servername=$(grep -E 'ServerName (.*)$' $sa/$domain.conf 2>/dev/null| awk '{print $NF}')
fi

if [[ -f $sa/${domain}_ssl.conf ]]; then
  error_msg="$sa/${domain}_ssl.conf exists"
fi

if [ -f $sa/$domain.conf ] && [ -z $docroot ]; then
  error_msg="DocumentRoot not set"
fi

if [ -f $sa/$domain.conf ] && [ -z $servername ]; then
  error_msg="ServerName not set"
fi

if [[ -z $ip ]]; then
  error_msg="$domain does not resolve in DNS"
fi

if [[ -n $error_msg ]]; then
  echo $error_msg
  exit 1
fi

if [[ -z $ip_www ]]; then
  echo "
NOTE: www.$domain does not resolve in DNS. Certificate will only be valid for $domain.
  "
fi

echo -n "Generate cert for $domain on $docroot (y/n): "
read n

if [[ $n != "y" ]];then
  echo "got $n, exptected y"
  exit 1
fi

# Generate a sslcert
if [[ -n $ip_www ]]; then
  certbot certonly --webroot -w $docroot -d $domain -d www.$domain
else
  certbot certonly --webroot -w $docroot -d $domain
fi

if [[ $? > 0 ]]; then
  echo
  echo "Letsencrypt returned errors. Check output above or debug log in /var/log/letsencrypt/letsencrypt.log. Aborting."
  exit 1
fi
# Make a copy of the default site to _ssl. If Wordpress Network site then first create a new vhost-conf.
if [[ -n $wpmu_blog ]]; then
  echo "<VirtualHost *:80>
        ServerAdmin serveradmin@$domain
        DocumentRoot /home/www/wordpress
        ServerName $domain
        ServerAlias www.$domain
        ErrorLog /home/logs/$domain-error.log
        CustomLog /home/logs/$domain-access.log combined

        <Directory / >
                Options FollowSymLinks
                AllowOverride None
        </Directory>

        <Directory /home/www/wordpress>
                Options -Indexes +FollowSymLinks +MultiViews
                AllowOverride All
                Order allow,deny
                allow from all
                Require all granted
        </Directory>
#
#
#
# check the php version on the server
# if php -v <=5 then comment out the Files match section
        <FilesMatch "\.php$">
          SetHandler \"proxy:unix:///var/run/php7.3-fpm-wordpress.sock|fcgi://php5-fpm/\"
        </FilesMatch>



        <IfModule mod_alias.c>
                RedirectMatch 403 /xmlrpc.php
        </IfModule>
</VirtualHost>" > $sa/$domain.conf
a2ensite $domain.conf
fi

cp $sa/$domain.conf $sa/${domain}_ssl.conf

# fix :80 => :443
sed -i -E 's/^<VirtualHost ((([0-9]){1,3}\.){3}([0-9]){1,3}|\*):80/<VirtualHost '${vhost_ip}':443/g' $sa/${domain}_ssl.conf

# Add SSL config above </virtualhost>
sed -i '/<\/VirtualHost>/i \
        SSLEngine on \
        SSLProtocol TLSv1.2 \
        SSLHonorCipherOrder on \
        SSLCipherSuite "HIGH:!aNULL:!MD5:!3DES:!CAMELLIA:!AES128" \
        SSLCertificateFile /etc/letsencrypt/live/'${domain}'/fullchain.pem \
        SSLCertificateKeyFile /etc/letsencrypt/live/'${domain}'/privkey.pem' $sa/${domain}_ssl.conf

# Add 301 from 80 => 443
echo -n "Add 301 to 443 (y/n): "
read f

if [ $f == "y" ]; then
sed -i '/<\/VirtualHost>/i \
        RewriteEngine on \
        RewriteRule ^(.*)$ https://'${servername}'$1 [R=301,L]' $sa/$domain.conf
fi

echo -n "Cert for $domain generated, enable? (y/n): "
read p

if [ $p != "y" ]; then
  echo "got $p, exptected y. You will need to reload Apache manually."
  exit 0
fi

# Test the config
a2ensite ${domain}_ssl
apache2ctl configtest
if [[ $? > 0 ]]; then
  echo "
Error in the Apache-config. See output above. Aborting Apache reload.
  "
  exit 1
fi
apache2ctl graceful
