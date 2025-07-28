#!/bin/bash

# Host-based SSL Certificate Setup Script
# This script runs certbot on the host machine to obtain SSL certificates
# and sets up the production environment to use them

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
WEBROOT_PATH="/var/www/certbot"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root directory
cd "$PROJECT_ROOT" || {
    print_error "Failed to change to project root directory"
    exit 1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Host-based SSL Certificate Management"
    echo ""
    echo "Commands:"
    echo "  install        - Install certbot on host machine"
    echo "  obtain         - Obtain SSL certificates (automatically frees ports 80/443)"
    echo "  renew          - Renew existing SSL certificates (automatically frees ports 80/443)"
    echo "  check          - Check certificate status"
    echo "  setup-cron     - Setup automatic renewal cron job"
    echo "  test-renewal   - Test certificate renewal (dry-run)"
    echo "  help           - Show this help message"
    echo ""
    echo "Note: The 'obtain' and 'renew' commands automatically stop web servers"
    echo "      and Docker containers using ports 80/443 before certificate validation."
    echo "      A temporary Python HTTP server is used for ACME challenge validation."
    echo ""
    echo "Examples:"
    echo "  $0 install     # Install certbot on host"
    echo "  $0 obtain      # Get SSL certificates"
    echo "  $0 check       # Check certificate status"
    echo "  $0 renew       # Renew certificates"
}

# Function to check if running as root/sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This command requires sudo privileges"
        print_status "Please run: sudo $0 $1"
        exit 1
    fi
}

# Function to install certbot on host
install_certbot() {
    check_sudo "install"
    
    print_status "Installing certbot on host machine..."
    
    # Detect OS and install certbot
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian
        print_status "Detected Ubuntu/Debian system"
        apt-get update
        apt-get install -y certbot
        
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS
        print_status "Detected RHEL/CentOS system"
        yum install -y epel-release
        yum install -y certbot
        
    elif command -v dnf &> /dev/null; then
        # Fedora
        print_status "Detected Fedora system"
        dnf install -y certbot
        
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        print_status "Detected Arch Linux system"
        pacman -S --noconfirm certbot
        
    elif command -v brew &> /dev/null; then
        # macOS
        print_status "Detected macOS system"
        brew install certbot
        
    else
        print_error "Unsupported operating system"
        print_status "Please install certbot manually and run this script again"
        exit 1
    fi
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot installed successfully!"
        certbot --version
    else
        print_error "Failed to install certbot"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_error "Certbot is not installed on the host machine"
        print_status "Run: sudo $0 install"
        exit 1
    fi
    
    # Check if Python is available (needed for temporary web server)
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        print_status "Python not found. Installing Python3..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y python3
        elif command -v yum &> /dev/null; then
            yum install -y python3
        elif command -v dnf &> /dev/null; then
            dnf install -y python3
        else
            print_warning "Could not install Python. Will try to install nginx instead."
        fi
    fi
    
    # Check if domain resolves to this server
    print_status "Checking domain configuration..."
    DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || nslookup $DOMAIN 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        print_warning "Domain $DOMAIN points to $DOMAIN_IP but server IP is $SERVER_IP"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Please update your DNS records first"
            exit 1
        fi
    else
        print_success "Domain correctly points to this server"
    fi
}

# Function to free up ports 80 and 443
free_ports() {
    print_status "Freeing up ports 80 and 443 for SSL certificate validation..."
    
    # Function to kill processes on specific port
    kill_port_processes() {
        local port=$1
        local pids=$(lsof -ti:$port 2>/dev/null || true)
        
        if [ -n "$pids" ]; then
            print_status "Found processes using port $port: $pids"
            echo "$pids" | while read -r pid; do
                if [ -n "$pid" ]; then
                    local process_name=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
                    print_status "Killing process $pid ($process_name) on port $port"
                    kill -TERM $pid 2>/dev/null || true
                    sleep 2
                    # Force kill if still running
                    if kill -0 $pid 2>/dev/null; then
                        print_status "Force killing process $pid"
                        kill -KILL $pid 2>/dev/null || true
                    fi
                fi
            done
        fi
    }
    
    # Stop common web servers
    print_status "Stopping common web servers..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    systemctl stop lighttpd 2>/dev/null || true
    
    # Stop Docker containers that might be using these ports
    if command -v docker &> /dev/null; then
        print_status "Stopping Docker containers using ports 80/443..."
        docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E ":80->|:443->" | awk '{print $1}' | while read -r container; do
            if [ -n "$container" ] && [ "$container" != "NAMES" ]; then
                print_status "Stopping Docker container: $container"
                docker stop "$container" 2>/dev/null || true
            fi
        done
    fi
    
    # Kill any remaining processes on ports 80 and 443
    kill_port_processes 80
    kill_port_processes 443
    
    # Wait a moment for ports to be freed
    sleep 3
    
    # Verify ports are free
    if lsof -ti:80 >/dev/null 2>&1; then
        print_warning "Port 80 still in use after cleanup attempt"
        lsof -i:80 || true
    else
        print_success "Port 80 is now free"
    fi
    
    if lsof -ti:443 >/dev/null 2>&1; then
        print_warning "Port 443 still in use after cleanup attempt"
        lsof -i:443 || true
    else
        print_success "Port 443 is now free"  
    fi
}

# Function to setup temporary web server for certificate validation
setup_temp_server() {
    print_status "Setting up temporary web server for certificate validation..."
    
    # Create webroot directory
    mkdir -p $WEBROOT_PATH
    chmod 755 $WEBROOT_PATH
    
    # Start a simple Python HTTP server in the background
    print_status "Starting Python HTTP server on port 80..."
    cd $WEBROOT_PATH
    
    # Use Python3 if available, otherwise Python2
    if command -v python3 &> /dev/null; then
        python3 -m http.server 80 > /tmp/certbot-server.log 2>&1 &
        SERVER_PID=$!
    elif command -v python &> /dev/null; then
        python -m SimpleHTTPServer 80 > /tmp/certbot-server.log 2>&1 &
        SERVER_PID=$!
    else
        print_error "Python is not available. Installing nginx..."
        # Install nginx as fallback
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y nginx
        elif command -v yum &> /dev/null; then
            yum install -y nginx
        elif command -v dnf &> /dev/null; then
            dnf install -y nginx
        else
            print_error "Cannot install nginx. Please install a web server manually."
            exit 1
        fi
        
        # Create nginx config and start it
        setup_nginx_fallback
        return
    fi
    
    # Save the PID for cleanup
    echo $SERVER_PID > /tmp/certbot-server.pid
    
    # Wait a moment for server to start
    sleep 2
    
    # Verify server is running
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_success "Temporary web server started (PID: $SERVER_PID)"
    else
        print_error "Failed to start temporary web server"
        exit 1
    fi
    
    # Go back to project root
    cd "$PROJECT_ROOT"
}

# Function to setup nginx as fallback
setup_nginx_fallback() {
    print_status "Setting up nginx for certificate validation..."
    
    # Create temporary nginx config
    tee /tmp/nginx-certbot.conf > /dev/null << EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name $DOMAIN;
        
        location /.well-known/acme-challenge/ {
            root $WEBROOT_PATH;
            try_files \$uri \$uri/ =404;
        }
        
        location / {
            return 503 "Certificate validation in progress";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    # Start nginx with custom config
    nginx -t -c /tmp/nginx-certbot.conf
    nginx -c /tmp/nginx-certbot.conf
    
    print_success "Nginx started for certificate validation"
}

# Function to cleanup temporary web server
cleanup_temp_server() {
    print_status "Cleaning up temporary web server..."
    
    # Kill Python HTTP server if running
    if [ -f /tmp/certbot-server.pid ]; then
        SERVER_PID=$(cat /tmp/certbot-server.pid)
        if kill -0 $SERVER_PID 2>/dev/null; then
            print_status "Stopping Python HTTP server (PID: $SERVER_PID)"
            kill $SERVER_PID 2>/dev/null || true
            sleep 2
            # Force kill if still running
            if kill -0 $SERVER_PID 2>/dev/null; then
                kill -9 $SERVER_PID 2>/dev/null || true
            fi
        fi
        rm -f /tmp/certbot-server.pid
    fi
    
    # Stop nginx if running
    nginx -s quit 2>/dev/null || killall nginx 2>/dev/null || true
    rm -f /tmp/nginx-certbot.conf
    
    # Clean up log file
    rm -f /tmp/certbot-server.log
    
    print_success "Temporary web server stopped"
}

# Function to obtain SSL certificates
obtain_certificates() {
    check_sudo "obtain"
    check_prerequisites
    
    print_status "Obtaining SSL certificates for $DOMAIN..."
    
    # Check if certificates already exist
    if [ -f "$CERT_PATH/fullchain.pem" ]; then
        print_warning "Certificates already exist for $DOMAIN"
        
        # Check expiry
        DAYS_LEFT=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2 | xargs -I {} date -d {} +%s | xargs -I {} expr \( {} - $(date +%s) \) / 86400)
        
        if [ $DAYS_LEFT -gt 30 ]; then
            print_success "Certificate is valid for $DAYS_LEFT more days"
            read -p "Force renewal anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Certificate renewal skipped"
                return 0
            fi
        fi
    fi
    
    # Free up ports 80 and 443 before certificate validation
    free_ports
    
    # Setup temporary web server for validation
    setup_temp_server
    
    # Obtain certificate
    print_status "Running certbot to obtain certificate..."
    
    if certbot certonly \
        --webroot \
        --webroot-path="$WEBROOT_PATH" \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN" \
        --non-interactive; then
        
        print_success "SSL certificate obtained successfully!"
        
        # Set proper permissions
        chmod -R 755 /etc/letsencrypt/live/
        chmod -R 755 /etc/letsencrypt/archive/
        
        # Show certificate info
        print_status "Certificate information:"
        openssl x509 -in "$CERT_PATH/fullchain.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:)"
        
    else
        print_error "Failed to obtain SSL certificate"
        cleanup_temp_server
        exit 1
    fi
    
    # Cleanup
    cleanup_temp_server
    
    print_success "SSL certificate setup completed!"
    print_status "Certificate files located at: $CERT_PATH"
    print_status "You can now start your production environment with SSL"
}

# Function to renew certificates
renew_certificates() {
    check_sudo "renew"
    
    print_status "Renewing SSL certificates..."
    
    # Free up ports 80 and 443 before certificate validation
    free_ports
    
    # Setup temporary web server for validation
    setup_temp_server
    
    if certbot renew --webroot --webroot-path="$WEBROOT_PATH" --quiet; then
        print_success "Certificate renewal completed!"
        
        # Restart nginx in docker if running
        if docker-compose -f docker-compose.prod.yml ps nginx | grep -q "Up"; then
            print_status "Restarting nginx container to use new certificates..."
            docker-compose -f docker-compose.prod.yml restart nginx
        fi
        
    else
        print_error "Certificate renewal failed"
        cleanup_temp_server
        exit 1
    fi
    
    cleanup_temp_server
}

# Function to check certificate status
check_certificate_status() {
    print_status "Checking SSL certificate status for $DOMAIN..."
    
    if [ ! -f "$CERT_PATH/fullchain.pem" ]; then
        print_error "No certificate found for $DOMAIN"
        print_status "Run: sudo $0 obtain"
        exit 1
    fi
    
    # Certificate details
    print_success "Certificate found!"
    echo
    print_status "Certificate Details:"
    openssl x509 -in "$CERT_PATH/fullchain.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:)"
    
    # Days until expiry
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2)
    DAYS_LEFT=$(date -d "$EXPIRY_DATE" +%s | xargs -I {} expr \( {} - $(date +%s) \) / 86400)
    
    echo
    if [ $DAYS_LEFT -gt 30 ]; then
        print_success "Certificate expires in $DAYS_LEFT days"
    elif [ $DAYS_LEFT -gt 0 ]; then
        print_warning "Certificate expires in $DAYS_LEFT days - renewal recommended"
    else
        print_error "Certificate has expired!"
        print_status "Run: sudo $0 renew"
    fi
}

# Function to setup cron job for automatic renewal
setup_cron() {
    check_sudo "setup-cron"
    
    print_status "Setting up automatic certificate renewal..."
    
    CRON_JOB="0 2 * * 0 $SCRIPT_DIR/setup-host-ssl.sh renew >> /var/log/certbot-renewal.log 2>&1"
    
    # Add cron job if it doesn't exist
    if ! crontab -l 2>/dev/null | grep -q "setup-host-ssl.sh renew"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        print_success "Automatic renewal cron job added"
        print_status "Certificates will be renewed automatically every Sunday at 2 AM"
        print_status "Logs will be written to /var/log/certbot-renewal.log"
    else
        print_warning "Cron job already exists"
    fi
    
    # Show current cron jobs
    print_status "Current cron jobs:"
    crontab -l | grep certbot || echo "No certbot cron jobs found"
}

# Function to test renewal
test_renewal() {
    check_sudo "test-renewal"
    
    print_status "Testing certificate renewal (dry-run)..."
    
    setup_temp_server
    
    if certbot renew --webroot --webroot-path="$WEBROOT_PATH" --dry-run; then
        print_success "Certificate renewal test passed!"
    else
        print_error "Certificate renewal test failed"
        cleanup_temp_server
        exit 1
    fi
    
    cleanup_temp_server
}

# Main execution logic
COMMAND=${1:-help}

case $COMMAND in
    "install")
        install_certbot
        ;;
    "obtain")
        obtain_certificates
        ;;
    "renew")
        renew_certificates
        ;;
    "check")
        check_certificate_status
        ;;
    "setup-cron")
        setup_cron
        ;;
    "test-renewal")
        test_renewal
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo
        show_usage
        exit 1
        ;;
esac
