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

# Function to check if SSL certificates exist
check_ssl_certificates() {
    local cert_path="./certbot/conf/live/$DOMAIN/fullchain.pem"
    local key_path="./certbot/conf/live/$DOMAIN/privkey.pem"
    
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        return 0  # Certificates exist
    else
        return 1  # Certificates don't exist
    fi
}

# Function to use HTTP-only nginx configuration
use_http_only_config() {
    print_status "Using HTTP-only nginx configuration..."
    
    # Create HTTP-only nginx config
    cat > nginx/nginx.http-only.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    upstream web {
        server web:8000;
    }

    server {
        listen 80;
        server_name books.shreyas.srijansahay05.in;

        # Certbot challenge
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Health check
        location /health/ {
            return 200 "OK";
            add_header Content-Type text/plain;
        }

        # All other requests
        location / {
            proxy_pass http://web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # CORS headers
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            
            if ($request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin *;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type 'text/plain; charset=utf-8';
                add_header Content-Length 0;
                return 204;
            }
        }

        # Static files
        location /static/ {
            alias /app/staticfiles/;
        }

        # Media files
        location /media/ {
            alias /app/media/;
        }
    }
}
EOF

    # Copy HTTP-only config to be used
    cp nginx/nginx.http-only.conf nginx/nginx.current.conf
    
    print_success "HTTP-only configuration ready"
}

# Function to setup SSL certificates
setup_ssl_certificates() {
    print_status "Setting up SSL certificates..."
    
    # Create directories
    mkdir -p certbot/conf
    mkdir -p certbot/www
    
    # Start services with HTTP-only first
    print_status "Starting services in HTTP-only mode..."
    docker-compose -f docker-compose.prod.yml up -d db web
    sleep 10
    
    # Start nginx with HTTP-only config
    docker-compose -f docker-compose.prod.yml up -d nginx
    sleep 15
    
    # Test if the site is accessible
    print_status "Testing HTTP connectivity..."
    if curl -f -s "http://$DOMAIN/health/" > /dev/null; then
        print_success "HTTP site is accessible"
    else
        print_warning "HTTP site might not be accessible yet"
    fi
    
    # Request SSL certificate
    print_status "Requesting SSL certificate from Let's Encrypt..."
    docker-compose -f docker-compose.prod.yml run --rm --entrypoint "\
        certbot certonly --webroot -w /var/www/certbot \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d $DOMAIN" certbot
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained successfully"
        
        # Switch to HTTPS configuration
        print_status "Switching to HTTPS configuration..."
        cp nginx/nginx.prod.conf nginx/nginx.current.conf
        
        # Reload nginx
        docker-compose -f docker-compose.prod.yml exec nginx nginx -s reload
        
        if [ $? -eq 0 ]; then
            print_success "Nginx reloaded with SSL configuration"
            print_success "Your site is now available at: https://$DOMAIN"
        else
            print_error "Failed to reload nginx with SSL configuration"
            return 1
        fi
    else
        print_error "Failed to obtain SSL certificate"
        print_warning "Continuing with HTTP-only mode"
        print_status "Your site is available at: http://$DOMAIN"
        return 1
    fi
}

# Function to start application
start_application() {
    print_status "Starting BitsBay application..."
    
    # Create necessary directories
    mkdir -p certbot/conf
    mkdir -p certbot/www
    
    if check_ssl_certificates; then
        print_status "SSL certificates found - starting with HTTPS"
        cp nginx/nginx.prod.conf nginx/nginx.current.conf
    else
        print_status "No SSL certificates found - starting with HTTP only"
        use_http_only_config
    fi
    
    # Update docker-compose to use current config
    sed -i.bak 's|nginx/nginx\.prod\.conf|nginx/nginx.current.conf|g' docker-compose.prod.yml
    
    # Start all services
    docker-compose -f docker-compose.prod.yml up -d
    
    # Wait for services to start
    sleep 20
    
    # If no SSL certificates, try to set them up
    if ! check_ssl_certificates; then
        print_status "Attempting to set up SSL certificates..."
        setup_ssl_certificates
    fi
    
    print_success "Application startup completed"
}

# Function to show status
show_status() {
    print_status "Service Status:"
    docker-compose -f docker-compose.prod.yml ps
    
    echo
    print_status "SSL Certificate Status:"
    if check_ssl_certificates; then
        print_success "SSL certificates are present"
        if docker-compose -f docker-compose.prod.yml exec nginx openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -dates 2>/dev/null; then
            print_success "SSL certificate details retrieved"
        fi
    else
        print_warning "No SSL certificates found"
    fi
    
    echo
    print_status "Site availability:"
    print_status "HTTP: http://$DOMAIN"
    if check_ssl_certificates; then
        print_status "HTTPS: https://$DOMAIN"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start       - Start the application (default)"
    echo "  stop        - Stop the application"
    echo "  restart     - Restart the application"
    echo "  ssl         - Set up SSL certificates"
    echo "  status      - Show application status"
    echo "  logs        - Show application logs"
    echo "  help        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start    # Start the application"
    echo "  $0 ssl      # Set up SSL certificates"
    echo "  $0 status   # Check status"
}

# Main execution
case "${1:-start}" in
    "start")
        start_application
        ;;
    "stop")
        print_status "Stopping application..."
        docker-compose -f docker-compose.prod.yml down
        ;;
    "restart")
        print_status "Restarting application..."
        docker-compose -f docker-compose.prod.yml down
        start_application
        ;;
    "ssl")
        setup_ssl_certificates
        ;;
    "status")
        show_status
        ;;
    "logs")
        docker-compose -f docker-compose.prod.yml logs -f
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
