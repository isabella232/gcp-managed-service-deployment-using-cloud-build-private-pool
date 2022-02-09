#! /bin/bash

# Allow health checking using a web server on this instance
mkdir -p /app/www
echo "OK" > /app/www/health.html
python3 -m http.server -d /app/www 8080 &> /dev/null &

# Forward source traffic and replace the source IP
iptables -F
iptables -t nat -A POSTROUTING -j MASQUERADE

# Enable IP forward
echo 1 > /proc/sys/net/ipv4/ip_forward