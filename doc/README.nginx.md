# Install nginx as Reverse proxy
```bash
sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring
```
Import the official Nginx signing key so apt can verify package integrity.
```bash
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
```
Verify that the downloaded key has the correct fingerprint
```bash
gpg --dry-run --quiet --no-keyring --import --import-options import-show \
    /usr/share/keyrings/nginx-archive-keyring.gpg
```
Add the repo.
```bash
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list
```
Pin the official repository so that packages from nginx.org always take priority over distribution packages.
```bash
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx
```
Install Nginx
```bash
sudo apt update && sudo apt install nginx -y
```
Enable the service so it starts automatically on boot, then start it and confirm the process is running.
```bash
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl status nginx
```
You should see active (running) in the output. Verify the installed version to confirm the official repo build.
`nginx -v`

Open a browser and navigate to http://your_server_ip. The default Nginx welcome page confirms the installation is working.

# Configuration nginx
The official Nginx repo packages use /etc/nginx/conf.d/ as the primary drop-in directory. If you prefer the sites-available / sites-enabled pattern, create both directories and add an include directive in nginx.conf.
```bash
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
```
Then add this line inside the http {} block in /etc/nginx/nginx.conf.
```bash
include /etc/nginx/sites-enabled/*;
```

# Sample Configuration
```nginx
server {
    listen 80;
    server_name <SERVERNAME>;

    # Allgemeine Komprimierung (Gzip)
    gzip on;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript text/xml text/event-stream; # text/event-stream ist wichtig für SSE
    gzip_min_length 1000;

    location / {
        proxy_pass http://127.0.0.1:3000; # Port Ihrer Mummy-Instanz
        proxy_http_version 1.1;
        proxy_set_header Connection ""; # Wichtig für Keep-Alive
        
        # SSE-spezifische Einstellungen
        proxy_buffering off;             # Deaktiviert das Puffern; Daten werden sofort gesendet
        proxy_cache off;                 # Verhindert Caching des Streams
        chunked_transfer_encoding off;   # Optional, oft hilfreich für SSE-Stabilität
        proxy_read_timeout 24h;          # Verhindert Verbindungsabbrüche bei langen Streams
        
        # Header für den Backend-Server
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```
and copy to /etc/nginx/conf.d/datastar.conf