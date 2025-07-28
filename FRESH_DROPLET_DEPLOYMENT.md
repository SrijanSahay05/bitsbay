# Fresh Droplet Deployment Guide for BitsBay

This guide will walk you through deploying BitsBay on a fresh Ubuntu droplet from scratch.

## Prerequisites

- Fresh Ubuntu 20.04/22.04 droplet (minimum 2GB RAM, 2 vCPUs recommended)
- Domain name (`books.enspire2025.in`) pointing to your droplet's IP
- SSH access to your droplet
- Your Google OAuth2 credentials

## Deployment Scripts and Order

### Phase 1: Server Setup (Run on Droplet)

**1. Initial Server Setup**
```bash
# Run the fresh droplet setup script
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/SrijanSahay05/bitsbay/prodworking/scripts/fresh-droplet-setup.sh)"
```

Or manually:
```bash
# Copy and run the setup script
wget https://raw.githubusercontent.com/SrijanSahay05/bitsbay/prodworking/scripts/fresh-droplet-setup.sh
chmod +x fresh-droplet-setup.sh
sudo ./fresh-droplet-setup.sh
```

This script will:
- Update system packages
- Install Docker and Docker Compose
- Install certbot for SSL certificates
- Setup firewall (UFW) with proper ports
- Configure fail2ban for security
- Create application user
- Setup SSH keys (optional)

### Phase 2: Application Deployment

**2. Clone Repository**
```bash
cd /opt
sudo git clone https://github.com/SrijanSahay05/bitsbay.git
sudo chown -R bitsbay:bitsbay /opt/bitsbay
cd /opt/bitsbay
```

**3. Environment Configuration**
```bash
# Copy and edit environment file
cp example.env.prod .env.prod
sudo nano .env.prod
```

Update these critical values in `.env.prod`:
```bash
# Change this to a secure random key
DJANGO_SECRET_KEY=your-super-secret-production-key-change-this-immediately

# Database credentials (change these!)
POSTGRES_PASSWORD=your-secure-database-password
POSTGRES_USER=postgres_user

# Your Google OAuth2 credentials (replace with your actual values)
GOOGLE_OAUTH2_CLIENT_ID=your-google-oauth2-client-id-here
GOOGLE_OAUTH2_CLIENT_SECRET=your-google-oauth2-client-secret-here
```

**4. DNS Configuration Check**
```bash
# Verify domain points to your server
./scripts/deploy-prod.sh domain-check
```

**5. SSL Certificate Setup**
```bash
# Install certbot (if not already done)
sudo ./scripts/setup-host-ssl.sh install

# Obtain SSL certificates
sudo ./scripts/setup-host-ssl.sh obtain
```

**6. Deploy Application**
```bash
# Deploy with SSL
./scripts/deploy-prod.sh ssl-host
```

**7. Create Superuser**
```bash
# Create Django admin user
./scripts/deploy-prod.sh createsuperuser
```

**8. Setup Automatic SSL Renewal**
```bash
# Setup cron job for certificate renewal
sudo ./scripts/setup-host-ssl.sh setup-cron
```

## Script Files Needed (in order)

### Required Scripts:
1. **`scripts/fresh-droplet-setup.sh`** - Server initialization
2. **`scripts/setup-host-ssl.sh`** - SSL certificate management
3. **`scripts/deploy-prod.sh`** - Application deployment
4. **`example.env.prod`** - Environment template

### Optional Scripts:
- **`scripts/deploy-dev.sh`** - Development deployment (not needed for production)
- **`scripts/server-setup.sh`** - Alternative server setup (not needed if using fresh-droplet-setup.sh)

## Complete Deployment Commands (Copy-Paste Ready)

```bash
# === PHASE 1: SERVER SETUP ===
# Run as root on fresh droplet
curl -fsSL https://raw.githubusercontent.com/SrijanSahay05/bitsbay/prodworking/scripts/fresh-droplet-setup.sh | sudo bash

# === PHASE 2: APPLICATION DEPLOYMENT ===
# Clone repository
cd /opt
sudo git clone https://github.com/SrijanSahay05/bitsbay.git
sudo chown -R bitsbay:bitsbay /opt/bitsbay
cd /opt/bitsbay

# Setup environment
cp example.env.prod .env.prod
# Edit .env.prod with your values
sudo nano .env.prod

# Check DNS
./scripts/deploy-prod.sh domain-check

# Get SSL certificates
sudo ./scripts/setup-host-ssl.sh obtain

# Deploy application
./scripts/deploy-prod.sh ssl-host

# Create admin user
./scripts/deploy-prod.sh createsuperuser

# Setup auto-renewal
sudo ./scripts/setup-host-ssl.sh setup-cron
```

## Verification Commands

```bash
# Check container status
./scripts/deploy-prod.sh status

# Check SSL certificate
./scripts/deploy-prod.sh ssl-status

# View logs
./scripts/deploy-prod.sh logs

# Test website
curl -I https://books.enspire2025.in
```

## Troubleshooting

### If SSL fails:
```bash
# Check domain DNS
dig books.enspire2025.in

# Try HTTP-only deployment
./scripts/deploy-prod.sh http-only

# Check certificate logs
sudo ./scripts/setup-host-ssl.sh check
```

### If containers fail to start:
```bash
# Check Docker
sudo systemctl status docker

# Check logs
./scripts/deploy-prod.sh logs

# Restart deployment
./scripts/deploy-prod.sh restart
```

### Fresh start (if needed):
```bash
# Reset everything and start fresh
./scripts/deploy-prod.sh fresh-start
```

## Security Notes

1. **Change default passwords** in `.env.prod`
2. **Setup SSH key authentication** (disable password auth)
3. **Keep system updated**: `sudo apt update && sudo apt upgrade`
4. **Monitor logs**: `./scripts/deploy-prod.sh logs`
5. **SSL auto-renewal** is setup via cron

## Access Points

- **Website**: https://books.enspire2025.in
- **Admin Panel**: https://books.enspire2025.in/admin
- **API Docs**: https://books.enspire2025.in/api/docs/ (if implemented)

## Support

For issues:
1. Check logs: `./scripts/deploy-prod.sh logs`
2. Check status: `./scripts/deploy-prod.sh status`
3. Verify SSL: `./scripts/deploy-prod.sh ssl-status`
4. Check domain: `./scripts/deploy-prod.sh domain-check`
