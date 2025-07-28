# Host-Based SSL Certificate Setup

This document explains how to set up SSL certificates using certbot on the host machine instead of inside Docker containers. This approach is more reliable and avoids Let's Encrypt rate limiting issues.

## 🚀 Quick Start

### Option 1: Automated Host-Based SSL (Recommended)
```bash
# Use the integrated command in deploy script
./scripts/deploy-prod.sh ssl-host
```

### Option 2: Manual Host-Based SSL Setup
```bash
# 1. Install certbot on host machine
sudo ./scripts/setup-host-ssl.sh install

# 2. Obtain SSL certificates
sudo ./scripts/setup-host-ssl.sh obtain

# 3. Start production with host SSL
docker-compose -f docker-compose.prod.hostssl.yml up -d

# 4. Setup automatic renewal (optional)
sudo ./scripts/setup-host-ssl.sh setup-cron
```

## 📋 Available Commands

### Host SSL Script Commands
```bash
./scripts/setup-host-ssl.sh [COMMAND]

Commands:
  install        - Install certbot on host machine
  obtain         - Obtain SSL certificates using host certbot
  renew          - Renew existing SSL certificates
  check          - Check certificate status
  setup-cron     - Setup automatic renewal cron job
  test-renewal   - Test certificate renewal (dry-run)
  help           - Show this help message
```

### Production Deploy Script Commands
```bash
./scripts/deploy-prod.sh [COMMAND]

SSL-related commands:
  ssl            - Setup SSL certificates (container-based)
  ssl-host       - Setup SSL using host certbot (recommended)
  ssl-status     - Check SSL certificate status and expiry
  http-only      - Setup HTTP-only mode (fallback)
  domain-check   - Check domain DNS configuration
```

## 🔄 Comparison: Container vs Host SSL

| Feature | Container SSL | Host SSL |
|---------|---------------|----------|
| **Rate Limits** | ❌ Prone to hitting limits | ✅ Better handling |
| **Renewal** | ❌ Manual container restarts | ✅ Automatic via cron |
| **Setup Complexity** | ❌ More complex | ✅ Straightforward |
| **Certificate Management** | ❌ Tied to containers | ✅ Independent |
| **Debugging** | ❌ Container logs | ✅ Host system logs |
| **Performance** | ❌ Extra container overhead | ✅ Direct host access |

## 📁 File Structure

### Docker Compose Files
- `docker-compose.prod.yml` - Original with certbot container
- `docker-compose.prod.hostssl.yml` - Simplified without certbot container

### Nginx Configurations
- `nginx/nginx.prod.conf` - Original nginx config
- `nginx/nginx.prod.hostssl.conf` - Optimized for host SSL

### Scripts
- `scripts/setup-host-ssl.sh` - Host-based SSL management
- `scripts/deploy-prod.sh` - Main deployment script (updated)

## 🛠️ Technical Details

### Certificate Locations
- **Host certificates**: `/etc/letsencrypt/live/books.enspire2025.in/`
- **Docker mount**: Mounted as read-only volume in nginx container

### Automatic Renewal
The cron job runs weekly (Sundays at 2 AM):
```bash
0 2 * * 0 /path/to/setup-host-ssl.sh renew >> /var/log/certbot-renewal.log 2>&1
```

### Security Features
- HTTP/2 support
- Modern TLS protocols (1.2, 1.3)
- Security headers (HSTS, XSS protection, etc.)
- Optimized SSL ciphers

## 🔧 Troubleshooting

### Common Issues

1. **Domain not pointing to server**
   ```bash
   ./scripts/deploy-prod.sh domain-check
   ```

2. **Certbot not installed**
   ```bash
   sudo ./scripts/setup-host-ssl.sh install
   ```

3. **Certificate expired**
   ```bash
   sudo ./scripts/setup-host-ssl.sh renew
   ```

4. **Check certificate status**
   ```bash
   ./scripts/setup-host-ssl.sh check
   ```

### Logs
- **Certbot logs**: `/var/log/letsencrypt/`
- **Renewal logs**: `/var/log/certbot-renewal.log`
- **Nginx logs**: `docker-compose logs nginx`

## 📝 Migration Guide

### From Container SSL to Host SSL

1. **Stop current environment**
   ```bash
   docker-compose -f docker-compose.prod.yml down
   ```

2. **Setup host SSL**
   ```bash
   ./scripts/deploy-prod.sh ssl-host
   ```

3. **Verify setup**
   ```bash
   ./scripts/setup-host-ssl.sh check
   curl -I https://books.enspire2025.in
   ```

### From Host SSL back to Container SSL

1. **Stop host SSL environment**
   ```bash
   docker-compose -f docker-compose.prod.hostssl.yml down
   ```

2. **Start container SSL environment**
   ```bash
   ./scripts/deploy-prod.sh start
   ./scripts/deploy-prod.sh ssl
   ```

## 🎯 Best Practices

1. **Use host-based SSL for production** - More reliable and manageable
2. **Setup automatic renewal** - Avoid certificate expiration
3. **Monitor certificate expiry** - Check status regularly
4. **Test renewal process** - Run dry-run tests periodically
5. **Keep backups** - Backup `/etc/letsencrypt/` directory

## 🚨 Important Notes

- **Requires sudo**: Host SSL setup needs root privileges
- **DNS must be configured**: Domain must point to your server
- **Firewall rules**: Ensure ports 80 and 443 are open
- **Backup certificates**: Keep `/etc/letsencrypt/` backed up

## 🎉 Benefits of Host-Based SSL

1. **No Rate Limiting Issues** - Direct certbot control
2. **Better Performance** - No container overhead
3. **Easier Debugging** - Host system logs
4. **Automatic Renewal** - Set-and-forget cron jobs
5. **Independent Management** - Not tied to container lifecycle
