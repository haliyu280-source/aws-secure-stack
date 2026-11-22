#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo "<h1>Secure stack: web-2</h1><p>Served from $(hostname)</p>" > /var/www/html/index.html
systemctl enable --now nginx
