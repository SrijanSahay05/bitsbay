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

# Configuration
DOMAIN="books.shreyas.srijansahay05.in"
EMAIL="srijan05sahay@gmail.com"
COMPOSE_FILE="docker-compose.prod.yml"

# Function to create dummy certificates
create_dummy_certificates() {
    print_status "Creating dummy SSL certificates for initial setup..."
    
    # Create the certificates directory
    mkdir -p certbot/conf/live/$DOMAIN
    
    # Create dummy certificate files
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout certbot/conf/live/$DOMAIN/privkey.pem \
        -out certbot/conf/live/$DOMAIN/fullchain.pem \
        -subj "/CN=$DOMAIN"
    
    print_success "Dummy certificates created"
}

# Function to start nginx with dummy certificates
start_nginx_with_dummy_certs() {
    print_status "Starting Nginx with dummy certificates..."
    
    # Start only nginx and web services
    docker-compose -f $COMPOSE_FILE up -d nginx web db
    
    # Wait for nginx to be ready
    sleep 10
    
    print_success "Nginx started with dummy certificates"
}

# Function to request real certificates
request_real_certificates() {
    print_status "Requesting real SSL certificates from Let's Encrypt..."
    
    # Remove dummy certificates
    rm -rf certbot/conf/live/$DOMAIN
    
    # Request real certificates
    docker-compose -f $COMPOSE_FILE run --rm --entrypoint "\
        certbot certonly --webroot -w /var/www/certbot \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d $DOMAIN" certbot
    
    if [ $? -eq 0 ]; then
        print_success "Real SSL certificates obtained successfully"
    else
        print_error "Failed to obtain SSL certificates"
        return 1
    fi
}

# Function to reload nginx with real certificates
reload_nginx() {
    print_status "Reloading Nginx with real certificates..."
    
    # Reload nginx configuration
    docker-compose -f $COMPOSE_FILE exec nginx nginx -s reload
    
    if [ $? -eq 0 ]; then
        print_success "Nginx reloaded with real certificates"
    else
        print_error "Failed to reload Nginx"
        return 1
    fi
}

# Function to verify SSL setup
verify_ssl() {
    print_status "Verifying SSL certificate setup..."
    
    # Test the certificate
    if docker-compose -f $COMPOSE_FILE exec nginx nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration has errors"
        return 1
    fi
    
    # Check if certificate files exist
    if docker-compose -f $COMPOSE_FILE exec nginx test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
        print_success "SSL certificate files are accessible"
    else
        print_error "SSL certificate files are not accessible"
        return 1
    fi
}

# Main function
main() {
    print_status "Initializing SSL certificates for $DOMAIN..."
    echo
    
    # Check if docker-compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Docker compose file $COMPOSE_FILE not found!"
        exit 1
    fi
    
    # Create necessary directories
    mkdir -p certbot/conf
    mkdir -p certbot/www
    
    # Step 1: Create dummy certificates
    create_dummy_certificates
    
    # Step 2: Start nginx with dummy certificates
    start_nginx_with_dummy_certs
    
    # Wait a bit for services to stabilize
    sleep 15
    
    # Step 3: Request real certificates
    if request_real_certificates; then
        # Step 4: Reload nginx with real certificates
        reload_nginx
        
        # Step 5: Verify the setup
        verify_ssl
        
        print_success "SSL initialization completed successfully!"
        print_status "Your site should now be accessible at: https://$DOMAIN"
    else
        print_error "SSL initialization failed!"
        print_warning "Your site is running with dummy certificates"
        print_status "Site accessible at: http://$DOMAIN (HTTP only)"
        exit 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Initialize SSL certificates for the application"
    echo ""
    echo "Options:"
    echo "  --domain DOMAIN     - Set the domain name (default: $DOMAIN)"
    echo "  --email EMAIL       - Set the email for SSL certificates (default: $EMAIL)"
    echo "  --help              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Initialize with default settings"
    echo "  $0 --domain mydomain.com             # Initialize with custom domain"
    echo "  $0 --email admin@mydomain.com        # Initialize with custom email"
}

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

# Run main function
main
