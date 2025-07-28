#!/bin/bash

# Fresh Droplet Setup Script for BitsBay Production
# This script sets up a fresh Ubuntu droplet for BitsBay deployment

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

# Configuration
DOMAIN="books.enspire2025.in"
EMAIL="srijan05sahay@gmail.com"
PROJECT_NAME="bitsbay"

print_status "🚀 Starting Fresh Droplet Setup for BitsBay"
print_status "Domain: $DOMAIN"
print_status "Email: $EMAIL"
echo

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        print_status "Please run: sudo $0"
        exit 1
    fi
}

# Function to update system
update_system() {
    print_status "📦 Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git vim htop ufw fail2ban
    print_success "System updated successfully"
}

# Function to install Docker
install_docker() {
    print_status "🐳 Installing Docker..."
    
    # Remove old Docker versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Install docker-compose standalone
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker $SUDO_USER
        print_status "Added $SUDO_USER to docker group"
    fi
    
    # Test Docker installation
    if docker --version && docker-compose --version; then
        print_success "Docker installed successfully"
    else
        print_error "Failed to install Docker"
        exit 1
    fi
}

# Function to install Python and certbot
install_certbot() {
    print_status "🔐 Installing certbot for SSL certificates..."
    
    # Install Python3 and pip
    apt-get install -y python3 python3-pip
    
    # Install certbot
    apt-get install -y certbot
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot installed successfully"
        certbot --version
    else
        print_error "Failed to install certbot"
        exit 1
    fi
}

# Function to setup firewall
setup_firewall() {
    print_status "🔥 Setting up firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (important - don't lock yourself out!)
    ufw allow ssh
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable UFW
    ufw --force enable
    
    print_success "Firewall configured"
    ufw status
}

# Function to setup fail2ban
setup_fail2ban() {
    print_status "🛡️  Setting up fail2ban..."
    
    # Create jail.local config
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = false

[nginx-limit-req]
enabled = false
EOF
    
    # Start and enable fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    print_success "Fail2ban configured"
}

# Function to create application user
create_app_user() {
    print_status "👤 Creating application user..."
    
    # Create user if not exists
    if ! id "$PROJECT_NAME" &>/dev/null; then
        useradd -m -s /bin/bash $PROJECT_NAME
        usermod -aG docker $PROJECT_NAME
        print_success "Created user: $PROJECT_NAME"
    else
        print_warning "User $PROJECT_NAME already exists"
    fi
    
    # Create project directory
    mkdir -p /opt/$PROJECT_NAME
    chown $PROJECT_NAME:$PROJECT_NAME /opt/$PROJECT_NAME
    
    print_success "Application user setup complete"
}

# Function to setup SSH key (optional)
setup_ssh_key() {
    print_status "🔑 SSH Key Setup (Optional)"
    echo "If you have an SSH public key, you can add it now for secure access."
    read -p "Do you want to add an SSH public key? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your SSH public key: " ssh_key
        
        if [ -n "$ssh_key" ]; then
            # Setup SSH key for root
            mkdir -p /root/.ssh
            echo "$ssh_key" >> /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            chmod 700 /root/.ssh
            
            # Setup SSH key for app user
            mkdir -p /home/$PROJECT_NAME/.ssh
            echo "$ssh_key" >> /home/$PROJECT_NAME/.ssh/authorized_keys
            chmod 600 /home/$PROJECT_NAME/.ssh/authorized_keys
            chmod 700 /home/$PROJECT_NAME/.ssh
            chown -R $PROJECT_NAME:$PROJECT_NAME /home/$PROJECT_NAME/.ssh
            
            print_success "SSH key added for root and $PROJECT_NAME user"
        fi
    fi
}

# Function to display deployment instructions
show_deployment_instructions() {
    print_success "🎉 Fresh Droplet Setup Complete!"
    echo
    print_status "Next Steps for Deployment:"
    echo "1. Clone your repository:"
    echo "   git clone https://github.com/SrijanSahay05/bitsbay.git /opt/$PROJECT_NAME/"
    echo
    echo "2. Change to project directory:"
    echo "   cd /opt/$PROJECT_NAME"
    echo
    echo "3. Copy your environment file:"
    echo "   cp example.env.prod .env.prod"
    echo "   # Edit .env.prod with your actual values"
    echo
    echo "4. Setup SSL certificates:"
    echo "   sudo ./scripts/setup-host-ssl.sh obtain"
    echo
    echo "5. Deploy the application:"
    echo "   ./scripts/deploy-prod.sh ssl-host"
    echo
    echo "6. Create superuser:"
    echo "   ./scripts/deploy-prod.sh createsuperuser"
    echo
    print_warning "Important Notes:"
    echo "• Make sure your domain '$DOMAIN' points to this server's IP"
    echo "• Update .env.prod with your actual database passwords and secret keys"
    echo "• The application will be available at: https://$DOMAIN"
    echo "• Admin panel: https://$DOMAIN/admin"
    echo
    print_status "System Information:"
    echo "• Server IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unable to detect')"
    echo "• Domain: $DOMAIN"
    echo "• Project path: /opt/$PROJECT_NAME"
    echo "• App user: $PROJECT_NAME"
}

# Function to check domain DNS
check_domain_dns() {
    print_status "🌐 Checking domain DNS configuration..."
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || echo "unknown")
    
    print_status "Server IP: $SERVER_IP"
    print_status "Domain IP: $DOMAIN_IP"
    
    if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
        print_success "✅ Domain correctly points to this server"
    else
        print_warning "⚠️  Domain does not point to this server"
        print_status "Please update your DNS records:"
        print_status "  Type: A"
        print_status "  Name: books.enspire2025.in"
        print_status "  Value: $SERVER_IP"
        print_status "  TTL: 300 (or lowest available)"
    fi
}

# Main execution
main() {
    print_status "Starting fresh droplet setup..."
    
    check_root
    update_system
    install_docker
    install_certbot
    setup_firewall
    setup_fail2ban
    create_app_user
    setup_ssh_key
    check_domain_dns
    
    show_deployment_instructions
}

# Run main function
main "$@"
