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
    echo "  --domain DOMAIN     - Set the domain name"
    echo "  --email EMAIL       - Set the email for SSL certificates"
    echo "  --staging           - Use Let's Encrypt staging environment (for testing)"
    echo "  --help              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 --domain mydomain.com             # Set domain directly"
    echo "  $0 --domain mydomain.com --email admin@mydomain.com"
    echo "  $0 --domain mydomain.com --staging   # Use staging environment"
}

# Default values
DOMAIN=""
EMAIL=""
STAGING=false

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
        --staging)
            STAGING=true
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

print_status "Starting SSL certificate setup..."
echo

# Function to get domain interactively
get_domain() {
    if [ -z "$DOMAIN" ]; then
        echo
        read -p "Enter your domain name (e.g., example.com or sub.example.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            print_error "Domain name is required"
            exit 1
        fi
    fi
    
    # Validate domain format (supports subdomains)
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $DOMAIN"
        print_error "Domain should be in format: example.com or sub.example.com"
        print_error "Examples of valid domains:"
        print_error "  - example.com"
        print_error "  - sub.example.com"
        print_error "  - books.shreyas.srijansahay05.in"
        exit 1
    fi
    
    print_success "Domain set to: $DOMAIN"
}

# Function to get email interactively
get_email() {
    if [ -z "$EMAIL" ]; then
        echo
        read -p "Enter your email address for SSL certificates: " EMAIL
        if [ -z "$EMAIL" ]; then
            print_error "Email address is required"
            exit 1
        fi
    fi
    
    # Validate email format
    if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_error "Invalid email format: $EMAIL"
        exit 1
    fi
    
    print_success "Email set to: $EMAIL"
}

# Function to install required packages
install_required_packages() {
    print_status "Installing required packages..."
    
    # Update package lists
    apt-get update
    
    # Install certbot (no nginx needed as it runs in container)
    apt-get install -y certbot
    
    # Install additional tools
    apt-get install -y curl wget net-tools docker.io docker-compose
    
    print_success "Required packages installed"
}

# Function to check and disable conflicting services
disable_conflicting_services() {
    print_status "Checking for services using ports 80 and 443..."
    
    # Check if ports 80 and 443 are in use
    local port_80_in_use=false
    local port_443_in_use=false
    
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":80 "; then
            port_80_in_use=true
        fi
        if netstat -tuln | grep -q ":443 "; then
            port_443_in_use=true
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":80 "; then
            port_80_in_use=true
        fi
        if ss -tuln | grep -q ":443 "; then
            port_443_in_use=true
        fi
    fi
    
    if [ "$port_80_in_use" = true ] || [ "$port_443_in_use" = true ]; then
        print_warning "Ports 80 and/or 443 are in use by other services"
        
        # Check for common services that might be using these ports
        local services_to_disable=()
        
        # Check for nginx
        if systemctl is-active --quiet nginx 2>/dev/null; then
            services_to_disable+=("nginx")
        fi
        
        # Check for apache2
        if systemctl is-active --quiet apache2 2>/dev/null; then
            services_to_disable+=("apache2")
        fi
        
        # Check for apache
        if systemctl is-active --quiet apache 2>/dev/null; then
            services_to_disable+=("apache")
        fi
        
        # Check for httpd
        if systemctl is-active --quiet httpd 2>/dev/null; then
            services_to_disable+=("httpd")
        fi
        
        # Check for lighttpd
        if systemctl is-active --quiet lighttpd 2>/dev/null; then
            services_to_disable+=("lighttpd")
        fi
        
        # Check for caddy
        if systemctl is-active --quiet caddy 2>/dev/null; then
            services_to_disable+=("caddy")
        fi
        
        if [ ${#services_to_disable[@]} -gt 0 ]; then
            print_warning "Found active services that might conflict: ${services_to_disable[*]}"
            echo
            read -p "Do you want to stop and disable these services? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                for service in "${services_to_disable[@]}"; do
                    print_status "Stopping and disabling $service..."
                    if systemctl stop "$service" 2>/dev/null; then
                        print_success "Stopped $service"
                    fi
                    if systemctl disable "$service" 2>/dev/null; then
                        print_success "Disabled $service"
                    fi
                done
                
                # Wait a moment for ports to be released
                sleep 3
                
                # Check again if ports are free
                if command -v netstat &> /dev/null; then
                    if ! netstat -tuln | grep -q ":80 " && ! netstat -tuln | grep -q ":443 "; then
                        print_success "Ports 80 and 443 are now available"
                    else
                        print_warning "Ports 80 and/or 443 are still in use. You may need to manually stop conflicting services."
                    fi
                elif command -v ss &> /dev/null; then
                    if ! ss -tuln | grep -q ":80 " && ! ss -tuln | grep -q ":443 "; then
                        print_success "Ports 80 and 443 are now available"
                    else
                        print_warning "Ports 80 and/or 443 are still in use. You may need to manually stop conflicting services."
                    fi
                fi
            else
                print_warning "Services not disabled. Make sure ports 80 and 443 are available before continuing."
            fi
        else
            print_warning "Ports 80 and/or 443 are in use but no common services detected."
            print_warning "You may need to manually stop the services using these ports."
        fi
    else
        print_success "Ports 80 and 443 are available"
    fi
}

# Function to setup SSL directories
setup_ssl_directories() {
    print_status "Setting up SSL certificate directories..."
    
    # Create necessary directories
    mkdir -p /etc/letsencrypt
    mkdir -p /var/www/certbot
    mkdir -p certbot-www
    
    # Set proper permissions
    chmod 755 /etc/letsencrypt
    chmod 755 /var/www/certbot
    chmod 755 certbot-www
    
    print_success "SSL certificate directories created"
}

# Function to create temporary nginx configuration for Docker
create_temp_nginx_config() {
    print_status "Creating temporary nginx configuration for SSL verification (Docker compatible)..."
    
    # Create nginx configuration directory
    mkdir -p nginx
    
    # Create temporary nginx configuration for certbot challenge
    tee nginx/nginx.ssl-temp.conf > /dev/null <<EOF
worker_processes 1;
events { worker_connections 1024; }

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 60;

    server {
        listen 80;
        server_name $DOMAIN;
        
        # Certbot challenge
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        # Default location
        location / {
            return 200 "SSL setup in progress for $DOMAIN";
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    print_success "Temporary nginx configuration created for Docker"
}

# Function to obtain SSL certificate using Docker
obtain_ssl_certificate() {
    print_status "Obtaining SSL certificate for $DOMAIN using Docker..."
    
    # Create temporary docker-compose file for SSL setup
    tee docker-compose.ssl-temp.yml > /dev/null <<EOF
services:
  nginx-temp:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.ssl-temp.conf:/etc/nginx/nginx.conf:ro
      - /var/www/certbot:/var/www/certbot:ro
    restart: unless-stopped

  certbot:
    image: certbot/certbot
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt
      - /var/www/certbot:/var/www/certbot
    depends_on:
      - nginx-temp
EOF
    
    # Start temporary nginx container
    print_status "Starting temporary nginx container for SSL verification..."
    docker-compose -f docker-compose.ssl-temp.yml up -d nginx-temp
    
    # Wait for nginx to be ready
    sleep 5
    
    # Build certbot command
    local certbot_cmd="docker-compose -f docker-compose.ssl-temp.yml run --rm certbot certonly"
    certbot_cmd="$certbot_cmd --webroot --webroot-path=/var/www/certbot"
    certbot_cmd="$certbot_cmd --email $EMAIL --agree-tos --no-eff-email"
    certbot_cmd="$certbot_cmd -d $DOMAIN"
    
    # Add staging flag if requested
    if [ "$STAGING" = true ]; then
        certbot_cmd="$certbot_cmd --staging"
        print_warning "Using Let's Encrypt staging environment (test certificates)"
    fi
    
    # Run certbot
    print_status "Running certbot command: $certbot_cmd"
    eval $certbot_cmd
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained successfully!"
        
        # Check if certificate files exist
        if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
            print_success "Certificate files verified"
            
            # Set proper permissions
            chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem
            chmod 600 /etc/letsencrypt/live/$DOMAIN/privkey.pem
            
            print_success "Certificate permissions set correctly"
        else
            print_error "Certificate files not found"
            exit 1
        fi
    else
        print_error "Failed to obtain SSL certificate"
        print_status "Check the error messages above and ensure:"
        print_status "1. Domain is pointing to this server"
        print_status "2. Port 80 is accessible from the internet"
        print_status "3. No firewall is blocking port 80"
        exit 1
    fi
    
    # Stop and remove temporary containers
    print_status "Cleaning up temporary containers..."
    docker-compose -f docker-compose.ssl-temp.yml down
    rm -f docker-compose.ssl-temp.yml
    rm -f nginx/nginx.ssl-temp.conf
    
    print_success "Temporary containers cleaned up"
}

# Function to setup SSL renewal
setup_ssl_renewal() {
    print_status "Setting up SSL certificate renewal..."
    
    # Create renewal script
    tee /opt/bitsbay/scripts/renew-ssl.sh > /dev/null <<EOF
#!/bin/bash
# SSL renewal script for $DOMAIN

# Change to project directory
cd /opt/bitsbay

# Stop production containers temporarily
docker-compose -f docker-compose.prod.yml down

# Renew certificates using Docker
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v /var/www/certbot:/var/www/certbot certbot/certbot renew --quiet

# Start production containers
docker-compose -f docker-compose.prod.yml up -d

# Log renewal
echo "\$(date): SSL renewal completed for $DOMAIN" >> /var/log/ssl-renewal.log
EOF
    
    chmod +x /opt/bitsbay/scripts/renew-ssl.sh
    
    # Add to crontab (run twice daily)
    (crontab -l 2>/dev/null; echo "0 2,14 * * * /opt/bitsbay/scripts/renew-ssl.sh > /var/log/ssl-renewal.log 2>&1") | crontab -
    
    print_success "SSL renewal cron job created"
}

# Function to test SSL certificate
test_ssl_certificate() {
    print_status "Testing SSL certificate..."
    
    # Wait a moment for certificate to be available
    sleep 2
    
    # Test certificate with openssl
    if command -v openssl &> /dev/null; then
        print_status "Certificate details:"
        openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -text -noout | grep -E "(Subject:|Not Before:|Not After:|DNS:)"
    fi
    
    # Test with curl if available
    if command -v curl &> /dev/null; then
        print_status "Testing HTTPS connection..."
        if curl -s -I "https://$DOMAIN" | grep -q "HTTP"; then
            print_success "HTTPS connection test successful"
        else
            print_warning "HTTPS connection test failed (production containers not running yet)"
        fi
    fi
}

# Function to display final instructions
show_final_instructions() {
    echo
    print_success "SSL certificate setup completed successfully!"
    echo
    print_status "Certificate information:"
    echo "- Domain: $DOMAIN"
    echo "- Email: $EMAIL"
    echo "- Certificate location: /etc/letsencrypt/live/$DOMAIN/"
    echo "- Full chain: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    echo "- Private key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo
    print_status "Next steps:"
    echo "1. Update your .env.prod file with the domain: $DOMAIN"
    echo "2. Update your docker-compose.prod.yml certbot service with the correct domain"
    echo "3. Run your deployment script: ./scripts/deploy-prod.sh start"
    echo
    print_status "SSL renewal:"
    echo "- Automatic renewal: Twice daily (2 AM and 2 PM)"
    echo "- Manual renewal: certbot renew"
    echo "- Renewal script: /opt/bitsbay/scripts/renew-ssl.sh"
    echo
    print_warning "Important:"
    echo "- Keep your private key secure"
    echo "- Monitor renewal logs: /var/log/ssl-renewal.log"
    echo "- Test your SSL configuration regularly"
}

# Main execution
main() {
    print_status "Starting SSL certificate setup for domain: $DOMAIN"
    echo
    
    # Get domain and email if not provided
    get_domain
    get_email
    
    # Install required packages
    install_required_packages
    
    # Disable conflicting services
    disable_conflicting_services
    
    # Setup SSL directories
    setup_ssl_directories
    
    # Create temporary nginx configuration
    create_temp_nginx_config
    
    # Obtain SSL certificate
    obtain_ssl_certificate
    
    # Setup SSL renewal
    setup_ssl_renewal
    
    # Test SSL certificate
    test_ssl_certificate
    
    # Show final instructions
    show_final_instructions
}

# Run main function
main 