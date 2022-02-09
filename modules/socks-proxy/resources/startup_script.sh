#! /bin/bash

# Install SOCKS5 proxy
sudo apt-get -y update
sudo apt-get -y install dante-server

cat <<EOF | sudo tee /etc/danted.conf >/dev/null
logoutput: stdout
errorlog: stderr
user.privileged: root
user.unprivileged: nobody

internal: 0.0.0.0 port=1080
external: ens4

socksmethod: none
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

sudo systemctl restart danted.service


# Allow health checking using a web server on this instance
mkdir -p /app/www
echo "OK" > /app/www/health.html
python3 -m http.server -d /app/www 8080 &> /dev/null &