#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --domain DOMAIN     - Set the domain name (default: books.srijansahay05.in)"
    echo "  --email EMAIL       - Set the email for SSL certificates (default: srijan05sahay@gmail.com)"
    echo "  --skip-ssl          - Skip SSL certificate setup"
    echo "  --help              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Setup with default settings"
    echo "  $0 --domain mydomain.com             # Setup with custom domain"
    echo "  $0 --email admin@mydomain.com        # Setup with custom email"
    echo "  $0 --skip-ssl                        # Setup without SSL certificates"
}

# Default values
DOMAIN="books.srijansahay05.in"
EMAIL="srijan05sahay@gmail.com"
SKIP_SSL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --skip-ssl)
            SKIP_SSL=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script should be run as root user."
    exit 1
fi

print_status "Starting server setup for Digital Ocean droplet..."
print_status "Domain: $DOMAIN"
print_status "Email: $EMAIL"
print_status "Skip SSL: $SKIP_SSL"
echo

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    
    # Update package lists
    apt-get update
    
    # Upgrade existing packages
    apt-get upgrade -y
    
    # Install essential packages
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        htop \
        ufw \
        fail2ban
    
    print_success "System packages updated and essential tools installed"
}

# Function to setup firewall
setup_firewall() {
    print_status "Setting up firewall (UFW)..."
    
    # Reset firewall rules
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (important to keep this!)
    ufw allow ssh
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    print_success "Firewall configured and enabled"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old versions if they exist
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists
    apt-get update
    
    # Install Docker
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed and configured"
}

# Function to install docker-compose
install_docker_compose() {
    print_status "Installing docker-compose..."
    
    # Get the latest version
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    
    # Download and install docker-compose
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make it executable
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "docker-compose installed (version: $DOCKER_COMPOSE_VERSION)"
}

# Function to install Node.js (for potential frontend builds)
install_nodejs() {
    print_status "Installing Node.js..."
    
    # Install Node.js using NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Install npm globally
    npm install -g npm@latest
    
    print_success "Node.js installed"
}

# Function to setup SSL certificates directory
setup_ssl_directories() {
    if [ "$SKIP_SSL" = true ]; then
        print_status "Skipping SSL directory setup"
        return
    fi
    
    print_status "Setting up SSL certificate directories..."
    
    # Create necessary directories
    mkdir -p /etc/letsencrypt
    mkdir -p /var/www/certbot
    
    # Set proper permissions
    chmod 755 /etc/letsencrypt
    chmod 755 /var/www/certbot
    
    # Create certbot-www directory in project
    mkdir -p certbot-www
    
    print_success "SSL certificate directories created"
}

# Function to configure system settings
configure_system() {
    print_status "Configuring system settings..."
    
    # Increase file descriptor limits
    echo "* soft nofile 65536" | tee -a /etc/security/limits.conf
    echo "* hard nofile 65536" | tee -a /etc/security/limits.conf
    
    # Configure sysctl for better performance
    echo "net.core.somaxconn = 65536" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_max_syn_backlog = 65536" | tee -a /etc/sysctl.conf
    echo "net.ipv4.ip_local_port_range = 1024 65535" | tee -a /etc/sysctl.conf
    
    # Apply sysctl changes
    sysctl -p
    
    print_success "System settings configured"
}

# Function to setup fail2ban
setup_fail2ban() {
    print_status "Setting up fail2ban..."
    
    # Create fail2ban configuration
    tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    print_success "fail2ban configured and enabled"
}

# Function to setup root user for Docker (no additional user needed)
setup_root_for_docker() {
    print_status "Setting up root user for Docker..."
    
    # Root user can run Docker commands directly
    print_success "Root user is ready for Docker operations"
}

# Function to setup project directory
setup_project_directory() {
    print_status "Setting up project directory..."
    
    # Create project directory
    mkdir -p /opt/bitsbay
    
    # Create backups directory
    mkdir -p /opt/bitsbay/backups
    
    print_success "Project directory created at /opt/bitsbay"
}

# Function to create systemd service for auto-restart
create_systemd_service() {
    print_status "Creating systemd service for auto-restart..."
    
    tee /etc/systemd/system/bitsbay.service > /dev/null <<EOF
[Unit]
Description=BitsBay Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/bitsbay
ExecStart=/opt/bitsbay/scripts/deploy-prod.sh start
ExecStop=/opt/bitsbay/scripts/deploy-prod.sh stop
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable bitsbay.service
    
    print_success "Systemd service created and enabled"
}

# Function to create SSL renewal cron job
setup_ssl_renewal() {
    if [ "$SKIP_SSL" = true ]; then
        print_status "Skipping SSL renewal setup"
        return
    fi
    
    print_status "Setting up SSL certificate renewal..."
    
    # Create renewal script
    tee /opt/bitsbay/scripts/renew-ssl.sh > /dev/null <<EOF
#!/bin/bash
cd /opt/bitsbay
./scripts/deploy-prod.sh ssl
EOF
    
    chmod +x /opt/bitsbay/scripts/renew-ssl.sh
    
    # Add to crontab (run twice daily)
    (crontab -l 2>/dev/null; echo "0 2,14 * * * /opt/bitsbay/scripts/renew-ssl.sh > /var/log/ssl-renewal.log 2>&1") | crontab -
    
    print_success "SSL renewal cron job created"
}

# Function to create backup cron job
setup_backup_cron() {
    print_status "Setting up automated backups..."
    
    # Create backup script
    tee /opt/bitsbay/scripts/backup.sh > /dev/null <<EOF
#!/bin/bash
cd /opt/bitsbay
./scripts/deploy-prod.sh backup
EOF
    
    chmod +x /opt/bitsbay/scripts/backup.sh
    
    # Add to crontab (daily backup at 3 AM)
    (crontab -l 2>/dev/null; echo "0 3 * * * /opt/bitsbay/scripts/backup.sh > /var/log/backup.log 2>&1") | crontab -
    
    print_success "Automated backup cron job created"
}

# Function to display final instructions
show_final_instructions() {
    echo
    print_success "Server setup completed successfully!"
    echo
    print_status "Next steps:"
    echo "1. Clone your project to /opt/bitsbay"
    echo "2. Copy your .env.prod file to /opt/bitsbay/"
    echo "3. Run: cd /opt/bitsbay && ./scripts/deploy-prod.sh start"
    echo
    print_status "Important information:"
    echo "- Domain: $DOMAIN"
    echo "- Email: $EMAIL"
    echo "- Project directory: /opt/bitsbay"
    echo "- Running as: root user"
    echo "- Firewall: UFW enabled (ports 22, 80, 443 open)"
    echo "- SSL renewal: Automatic (twice daily)"
    echo "- Backups: Automatic (daily at 3 AM)"
    echo
    print_warning "Security reminders:"
    echo "- Update SSH configuration"
    echo "- Review firewall rules"
    echo "- Monitor fail2ban logs"
    echo "- Consider using SSH keys instead of passwords"
    echo
    print_status "Useful commands:"
    echo "- Check status: ./scripts/deploy-prod.sh status"
    echo "- View logs: ./scripts/deploy-prod.sh logs"
    echo "- Setup SSL: ./scripts/deploy-prod.sh ssl"
    echo "- Backup DB: ./scripts/deploy-prod.sh backup"
}

# Main execution
main() {
    print_status "Starting Digital Ocean server setup..."
    echo
    
    # Update system
    update_system
    
    # Setup firewall
    setup_firewall
    
    # Install Docker
    install_docker
    
    # Install docker-compose
    install_docker_compose
    
    # Install Node.js
    install_nodejs
    
    # Setup SSL directories
    setup_ssl_directories
    
    # Configure system
    configure_system
    
    # Setup fail2ban
    setup_fail2ban
    
    # Setup root user for Docker
    setup_root_for_docker
    
    # Setup project directory
    setup_project_directory
    
    # Create systemd service
    create_systemd_service
    
    # Setup SSL renewal
    setup_ssl_renewal
    
    # Setup backup cron
    setup_backup_cron
    
    # Show final instructions
    show_final_instructions
}

# Run main function
main 