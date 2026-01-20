sudo openssl req -x509 -keyout /etc/ssl/certs/3x-ui.key -out /etc/ssl/certs/3x-ui.pem -newkey rsa:4096 -sha256 -days 3650 -nodes -new -addext "subjectAltName=DNS:*.domen.com"
sudo openssl x509 -noout -sha256 -fingerprint -in /etc/ssl/certs/3x-ui.pem
