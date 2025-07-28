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
    echo "Usage: $0 [COMMAND] [ARGUMENTS...]"
    echo ""
    echo "Commands:"
    echo "  start, up      - Start production environment (default)"
    echo "  stop, down     - Stop production environment"
    echo "  restart        - Restart production environment"
    echo "  rebuild        - Rebuild and start production containers"
    echo "  fresh-start    - Reset all migrations, start with fresh database (DESTRUCTIVE!)"
    echo "  logs           - Show production logs"
    echo "  status         - Show production container status"
    echo "  ssl            - Setup/renew SSL certificates (container-based)"
    echo "  ssl-status     - Check SSL certificate status and expiry"
    echo "  ssl-host       - Setup SSL using host machine certbot"
    echo "  http-only      - Setup HTTP-only mode (no SSL)"
    echo "  backup         - Backup database"
    echo "  restore        - Restore database from backup"
    echo "  shell          - Open Django shell in production"
    echo "  createsuperuser - Create Django superuser"
    echo "  makemigrations - Create Django migrations"
    echo "  migrate        - Run Django migrations"
    echo "  collectstatic  - Collect static files"
    echo "  domain-check   - Check domain DNS configuration"
    echo "  help           - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start production (default)"
    echo "  $0 restart      # Restart production"
    echo "  $0 fresh-start  # Reset database and start fresh"
    echo "  $0 ssl          # Setup SSL certificates (container)"
    echo "  $0 ssl-host     # Setup SSL using host certbot (recommended)"
    echo "  $0 ssl-status   # Check SSL certificate expiry"
    echo "  $0 http-only    # Setup without SSL (fallback)"
    echo "  $0 domain-check # Check domain configuration"
    echo "  $0 backup       # Backup database"
    echo "  $0 logs         # Show logs"
}

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
COMMAND=${1:-start}

# Change to project root directory
cd "$PROJECT_ROOT" || {
    print_error "Failed to change to project root directory"
    exit 1
}

# Function to load environment variables
load_env() {
    if [ -f ".env.prod" ]; then
        print_status "Loading environment variables from .env.prod..."
        export $(grep -v '^#' .env.prod | xargs)
        print_success "Environment variables loaded"
    else
        print_error ".env.prod file not found"
        exit 1
    fi
}

# Function to run docker-compose with environment
run_docker_compose() {
    local cmd="$1"
    load_env
    docker-compose -f docker-compose.prod.yml $cmd
}

# Function to setup environment file
setup_env_file() {
    if [ ! -f ".env.prod" ]; then
        print_warning ".env.prod file not found"
        
        # Check if example.env.prod exists
        if [ -f "example.env.prod" ]; then
            print_status "Copying example.env.prod to .env.prod..."
            cp example.env.prod .env.prod
            
            if [ $? -eq 0 ]; then
                print_success "Successfully created .env.prod from example.env.prod"
                
                # Prompt user to edit the .env.prod file
                print_warning "Please edit the .env.prod file with your production configuration values"
                echo
                read -p "Would you like to edit .env.prod now? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    print_status "Opening .env.prod for editing..."
                    
                    # Try to open with default editor, fallback to nano
                    if command -v code &> /dev/null; then
                        code .env.prod
                    elif command -v vim &> /dev/null; then
                        vim .env.prod
                    elif command -v nano &> /dev/null; then
                        nano .env.prod
                    else
                        print_warning "No suitable editor found. Please manually edit .env.prod"
                    fi
                    
                    # Ask user to confirm they've edited the file
                    echo
                    read -p "Have you finished editing .env.prod? (y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_warning "Please edit .env.prod and run this script again"
                        exit 1
                    fi
                else
                    print_warning "Make sure to edit .env.prod with proper production configuration values"
                fi
            else
                print_error "Failed to copy example.env.prod to .env.prod"
                exit 1
            fi
        else
            print_error "example.env.prod file not found. Please create .env.prod manually"
            exit 1
        fi
    else
        print_success ".env.prod file already exists"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again"
        exit 1
    fi

    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        print_error "docker-compose is not installed. Please install docker-compose and try again"
        exit 1
    fi

    # Check if docker-compose.prod.yml exists
    if [ ! -f "docker-compose.prod.yml" ]; then
        print_error "docker-compose.prod.yml file not found"
        exit 1
    fi
    
    # Check if user has sudo privileges (needed for stopping system services)
    if ! sudo -n true 2>/dev/null; then
        print_warning "This script may need sudo privileges to stop conflicting services"
        print_warning "You may be prompted for your password"
    fi
}

# Function to check and disable conflicting services
check_and_disable_conflicting_services() {
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
                    if sudo systemctl stop "$service" 2>/dev/null; then
                        print_success "Stopped $service"
                    fi
                    if sudo systemctl disable "$service" 2>/dev/null; then
                        print_success "Disabled $service"
                    fi
                done
                
                # Wait a moment for ports to be released
                sleep 2
                
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

# Function to start production environment
start_production() {
    print_status "Starting production environment..."
    
    # Check and disable conflicting services
    check_and_disable_conflicting_services
    
    # Check if SSL certificates exist
    CERT_PATH="certbot-conf/live/books.enspire2025.in/fullchain.pem"
    HAS_SSL=false
    
    if [ -f "$CERT_PATH" ]; then
        # Check if certificate is valid
        if openssl x509 -checkend 86400 -noout -in "$CERT_PATH" >/dev/null 2>&1; then
            HAS_SSL=true
            print_success "Valid SSL certificates found"
        else
            print_warning "SSL certificates exist but are expired or invalid"
        fi
    else
        print_warning "No SSL certificates found"
    fi
    
    # Stop any existing containers
    print_status "Stopping existing containers..."
    run_docker_compose "down"
    
    # Build and start containers
    print_status "Building and starting production containers..."
    run_docker_compose "up --build -d"
    
    if [ $? -eq 0 ]; then
        print_success "Production environment started successfully!"
        print_status "Services are starting up..."
        
        if [ "$HAS_SSL" = true ]; then
            print_status "Web application will be available at: https://books.enspire2025.in"
            print_status "Admin panel will be available at: https://books.enspire2025.in/admin"
        else
            print_status "Web application will be available at: http://books.enspire2025.in"
            print_status "Admin panel will be available at: http://books.enspire2025.in/admin"
            print_warning "⚠️  Running without SSL certificates!"
            print_status "To setup SSL certificates, run: $0 ssl"
        fi
        
        echo
        print_status "Container status:"
        run_docker_compose "ps"
        
        echo
        print_status "Useful commands:"
        print_status "  View logs: $0 logs"
        print_status "  Stop environment: $0 stop"
        print_status "  Check SSL status: $0 ssl-status"
        print_status "  Check domain config: $0 domain-check"
        if [ "$HAS_SSL" = false ]; then
            print_status "  Setup SSL certificates: $0 ssl"
        fi
    else
        print_error "Failed to start production containers"
        print_status "Check the logs with: $0 logs"
        exit 1
    fi
}

# Function to stop production environment
stop_production() {
    print_status "Stopping production environment..."
    run_docker_compose "down"
    print_success "Production environment stopped"
}

# Function to restart production environment
restart_production() {
    print_status "Restarting production environment..."
    run_docker_compose "restart"
    print_success "Production environment restarted"
}

# Function to rebuild production environment
rebuild_production() {
    print_status "Rebuilding and starting production containers..."
    
    # Check and disable conflicting services
    check_and_disable_conflicting_services
    
    run_docker_compose "down"
    run_docker_compose "up --build -d"
    print_success "Production containers rebuilt and started"
}

# Function to fresh start with clean database and migrations
fresh_start_production() {
    print_warning "🚨 DESTRUCTIVE OPERATION: This will completely reset your database and migrations!"
    print_warning "All existing data will be permanently lost!"
    echo
    print_status "This operation will:"
    echo "  1. Stop all containers"
    echo "  2. Remove all migration files"
    echo "  3. Delete the database volume"
    echo "  4. Create fresh migrations"
    echo "  5. Start with a clean database"
    echo
    
    # Double confirmation for destructive operation
    read -p "Are you absolutely sure you want to continue? Type 'YES' to confirm: " -r
    if [[ ! $REPLY = "YES" ]]; then
        print_status "Fresh start cancelled"
        exit 0
    fi
    
    read -p "Last chance! This will destroy all data. Type 'DESTROY' to proceed: " -r
    if [[ ! $REPLY = "DESTROY" ]]; then
        print_status "Fresh start cancelled"
        exit 0
    fi
    
    # Create automatic backup before destroying data
    print_status "Creating automatic backup before fresh start..."
    mkdir -p backups
    BACKUP_FILE="backups/pre_fresh_start_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Try to create backup if database is running
    if run_docker_compose "exec -T db pg_dump -U $POSTGRES_USER $POSTGRES_DB" > "$BACKUP_FILE" 2>/dev/null; then
        print_success "Backup created: $BACKUP_FILE"
    else
        print_warning "Could not create backup (database may not be running)"
        rm -f "$BACKUP_FILE" 2>/dev/null || true
    fi
    
    print_status "Starting fresh database setup..."
    
    # Check and disable conflicting services
    check_and_disable_conflicting_services
    
    # Stop and remove all containers and volumes
    print_status "Stopping containers and removing volumes..."
    run_docker_compose "down -v"
    
    # Remove migration files (keep __init__.py)
    print_status "Removing existing migration files..."
    find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
    find . -path "*/migrations/*.pyc" -delete
    
    # Remove __pycache__ directories in migrations
    find . -path "*/migrations/__pycache__" -exec rm -rf {} + 2>/dev/null || true
    
    print_success "Migration files removed"
    
    # Build and start containers
    print_status "Building and starting fresh containers..."
    run_docker_compose "up --build -d db"
    
    # Wait for database to be ready
    print_status "Waiting for database to be ready..."
    sleep 10
    
    # Create fresh migrations
    print_status "Creating fresh migrations..."
    run_docker_compose "exec web python manage.py makemigrations core_users"
    run_docker_compose "exec web python manage.py makemigrations marketplace"
    run_docker_compose "exec web python manage.py makemigrations"
    
    # Apply migrations
    print_status "Applying fresh migrations..."
    run_docker_compose "exec web python manage.py migrate"
    
    # Collect static files
    print_status "Collecting static files..."
    run_docker_compose "exec web python manage.py collectstatic --noinput"
    
    # Start all services
    print_status "Starting all services..."
    run_docker_compose "up -d"
    
    print_success "🎉 Fresh start completed successfully!"
    print_status "Your application is now running with a clean database"
    print_warning "Don't forget to create a superuser: $0 createsuperuser"
    print_status "Web application: https://books.enspire2025.in"
    print_status "Admin panel: https://books.enspire2025.in/admin"
}

# Function to show logs
show_logs() {
    print_status "Showing production logs..."
    run_docker_compose "logs -f"
}

# Function to show status
show_status() {
    print_status "Production container status:"
    run_docker_compose "ps"
}

# Function to setup SSL certificates
setup_ssl() {
    print_status "Setting up SSL certificates..."
    
    # Check if domain is configured
    if ! grep -q "books.enspire2025.in" .env.prod; then
        print_error "Domain not configured in .env.prod. Please update ALLOWED_HOSTS and CSRF_TRUSTED_ORIGINS"
        exit 1
    fi
    
    # Check and disable conflicting services before SSL setup
    check_and_disable_conflicting_services
    
    # Create necessary directories
    mkdir -p certbot-www
    mkdir -p certbot-conf
    
    # Check if certificates already exist
    if [ -f "certbot-conf/live/books.enspire2025.in/fullchain.pem" ]; then
        print_success "SSL certificates already exist!"
        
        # Check certificate expiry
        CERT_EXPIRY=$(openssl x509 -enddate -noout -in certbot-conf/live/books.enspire2025.in/fullchain.pem | cut -d= -f2)
        EXPIRY_DATE=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$CERT_EXPIRY" +%s 2>/dev/null || echo "0")
        CURRENT_DATE=$(date +%s)
        DAYS_UNTIL_EXPIRY=$(( (EXPIRY_DATE - CURRENT_DATE) / 86400 ))
        
        if [ $DAYS_UNTIL_EXPIRY -gt 30 ]; then
            print_success "Certificate is valid for $DAYS_UNTIL_EXPIRY more days"
            print_status "Restarting nginx to use existing certificates..."
            run_docker_compose "restart nginx"
            return 0
        else
            print_warning "Certificate expires in $DAYS_UNTIL_EXPIRY days, attempting renewal..."
        fi
    fi
    
    # Ensure proper permissions
    if [ -d "/etc/letsencrypt" ]; then
        sudo chmod 755 /etc/letsencrypt
    fi
    
    # First, try to start nginx without SSL to handle ACME challenge
    print_status "Starting nginx in HTTP-only mode for certificate verification..."
    
    # Create temporary nginx config for HTTP only
    NGINX_TEMP_CONFIG="nginx/nginx.temp.conf"
    cat > "$NGINX_TEMP_CONFIG" << 'EOF'
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
        server_name books.enspire2025.in;

        # ACME challenge for Let's Encrypt
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            try_files $uri $uri/ =404;
        }

        # Temporary redirect all other traffic to a maintenance page
        location / {
            return 503 "Site is being set up. Please try again in a few minutes.";
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Backup original nginx config
    if [ -f "nginx/nginx.prod.conf" ]; then
        cp nginx/nginx.prod.conf nginx/nginx.prod.conf.backup
    fi
    
    # Use temporary config
    cp "$NGINX_TEMP_CONFIG" nginx/nginx.prod.conf
    
    # Start containers with temporary config
    print_status "Starting containers with HTTP-only configuration..."
    run_docker_compose "up -d nginx"
    
    # Wait for nginx to be ready
    sleep 5
    
    # Check if we're hitting rate limits by testing with dry-run first
    print_status "Testing certificate request (dry-run)..."
    DRY_RUN_RESULT=$(run_docker_compose "run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email srijan05sahay@gmail.com --agree-tos --no-eff-email --dry-run -d books.enspire2025.in" 2>&1)
    
    if echo "$DRY_RUN_RESULT" | grep -q "too many certificates"; then
        print_error "Rate limit hit! Too many certificates issued for this domain."
        print_warning "Let's Encrypt has rate limits. You may need to:"
        print_warning "1. Wait up to a week before requesting new certificates"
        print_warning "2. Use existing certificates if available"
        print_warning "3. Consider using a different subdomain temporarily"
        
        # Restore original nginx config if it exists
        if [ -f "nginx/nginx.prod.conf.backup" ]; then
            mv nginx/nginx.prod.conf.backup nginx/nginx.prod.conf
        fi
        
        # Ask user if they want to continue without SSL
        echo
        read -p "Do you want to continue with HTTP-only setup? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Continuing with HTTP-only setup..."
            setup_http_only_fallback
            return 0
        else
            print_status "SSL setup cancelled"
            exit 1
        fi
    elif echo "$DRY_RUN_RESULT" | grep -q "Congratulations"; then
        print_success "Dry-run successful! Proceeding with actual certificate request..."
        
        # Run actual certificate request
        print_status "Obtaining SSL certificates from Let's Encrypt..."
        CERT_RESULT=$(run_docker_compose "run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email srijan05sahay@gmail.com --agree-tos --no-eff-email --force-renewal -d books.enspire2025.in" 2>&1)
        
        if echo "$CERT_RESULT" | grep -q "Congratulations"; then
            print_success "SSL certificates obtained successfully!"
            
            # Restore original nginx config
            if [ -f "nginx/nginx.prod.conf.backup" ]; then
                mv nginx/nginx.prod.conf.backup nginx/nginx.prod.conf
            fi
            
            print_status "Restarting nginx with SSL configuration..."
            run_docker_compose "restart nginx"
            print_success "SSL setup completed!"
            
            # Clean up temporary files
            rm -f "$NGINX_TEMP_CONFIG"
            
        else
            print_error "Failed to obtain SSL certificates"
            print_error "Certificate request output:"
            echo "$CERT_RESULT"
            
            # Restore original nginx config
            if [ -f "nginx/nginx.prod.conf.backup" ]; then
                mv nginx/nginx.prod.conf.backup nginx/nginx.prod.conf
            fi
            
            # Offer fallback option
            echo
            read -p "Do you want to continue with HTTP-only setup? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_http_only_fallback
                return 0
            else
                exit 1
            fi
        fi
    else
        print_error "Dry-run failed. Check domain configuration and DNS settings."
        print_error "Dry-run output:"
        echo "$DRY_RUN_RESULT"
        
        # Restore original nginx config
        if [ -f "nginx/nginx.prod.conf.backup" ]; then
            mv nginx/nginx.prod.conf.backup nginx/nginx.prod.conf
        fi
        
        # Offer fallback option
        echo
        read -p "Do you want to continue with HTTP-only setup? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_http_only_fallback
            return 0
        else
            exit 1
        fi
    fi
}

# Function to setup HTTP-only fallback
setup_http_only_fallback() {
    print_warning "Setting up HTTP-only configuration as fallback..."
    
    # Create HTTP-only nginx configuration
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
        server_name books.enspire2025.in;

        # Security headers (even for HTTP)
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Static files
        location /static/ {
            alias /app/staticfiles/;
            expires 1d;
            add_header Cache-Control "public, no-transform";
        }

        # Media files
        location /media/ {
            alias /app/media/;
            expires 1d;
            add_header Cache-Control "public, no-transform";
        }

        # API and admin routes
        location / {
            proxy_pass http://web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Add security warning header
            add_header X-Security-Warning "This site is running over HTTP. Upgrade to HTTPS recommended." always;
        }
    }
}
EOF
    
    # Use HTTP-only configuration
    cp nginx/nginx.http-only.conf nginx/nginx.prod.conf
    
    print_status "Restarting nginx with HTTP-only configuration..."
    run_docker_compose "restart nginx"
    
    print_success "HTTP-only setup completed!"
    print_warning "⚠️  Your site is running over HTTP only at: http://books.enspire2025.in"
    print_warning "⚠️  This is not secure for production use!"
    print_status "To add SSL later, run: $0 ssl"
}

# Function to backup database
backup_database() {
    print_status "Creating database backup..."
    
    # Create backups directory
    mkdir -p backups
    
    # Generate backup filename with timestamp
    BACKUP_FILE="backups/bitsbay_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Create backup
    run_docker_compose "exec -T db pg_dump -U $POSTGRES_USER $POSTGRES_DB" > "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
        print_success "Database backup created: $BACKUP_FILE"
    else
        print_error "Failed to create database backup"
        exit 1
    fi
}

# Function to restore database
restore_database() {
    if [ -z "$2" ]; then
        print_error "Backup file required. Usage: $0 restore <backup_file>"
        exit 1
    fi
    
    BACKUP_FILE="$2"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    print_warning "This will overwrite the current database!"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Database restore cancelled"
        exit 0
    fi
    
    print_status "Restoring database from: $BACKUP_FILE"
    
    # Restore database
    run_docker_compose "exec -T db psql -U $POSTGRES_USER $POSTGRES_DB" < "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
        print_success "Database restored successfully!"
    else
        print_error "Failed to restore database"
        exit 1
    fi
}

# Function to run Django shell
run_django_shell() {
    print_status "Opening Django shell in production..."
    run_docker_compose "exec web python manage.py shell"
}

# Function to run migrations
run_migrations() {
    print_status "Running Django migrations..."
    run_docker_compose "exec web python manage.py migrate"
}

# Function to collect static files
collect_static() {
    print_status "Collecting static files..."
    run_docker_compose "exec web python manage.py collectstatic --noinput"
}

# Function to create superuser
create_superuser() {
    print_status "Creating Django superuser..."
    run_docker_compose "exec web python manage.py createsuperuser"
}

# Function to create migrations
create_migrations() {
    print_status "Creating Django migrations..."
    if [ -n "$2" ]; then
        # If app name is provided
        run_docker_compose "exec web python manage.py makemigrations $2"
    else
        # Create migrations for all apps
        run_docker_compose "exec web python manage.py makemigrations"
    fi
}

# Function to check SSL certificate status
check_ssl_status() {
    print_status "Checking SSL certificate status..."
    
    CERT_PATH="certbot-conf/live/books.enspire2025.in/fullchain.pem"
    
    if [ ! -f "$CERT_PATH" ]; then
        print_warning "No SSL certificate found at: $CERT_PATH"
        print_status "Run '$0 ssl' to obtain SSL certificates"
        return 1
    fi
    
    # Check certificate details
    print_status "Certificate found, checking details..."
    
    CERT_SUBJECT=$(openssl x509 -subject -noout -in "$CERT_PATH" | sed 's/subject=//')
    CERT_ISSUER=$(openssl x509 -issuer -noout -in "$CERT_PATH" | sed 's/issuer=//')
    CERT_START=$(openssl x509 -startdate -noout -in "$CERT_PATH" | sed 's/notBefore=//')
    CERT_END=$(openssl x509 -enddate -noout -in "$CERT_PATH" | sed 's/notAfter=//')
    
    print_success "SSL Certificate Details:"
    echo "  Subject: $CERT_SUBJECT"
    echo "  Issuer: $CERT_ISSUER"
    echo "  Valid from: $CERT_START"
    echo "  Valid until: $CERT_END"
    
    # Calculate days until expiry
    EXPIRY_DATE=$(date -d "$CERT_END" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$CERT_END" +%s 2>/dev/null || echo "0")
    CURRENT_DATE=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( (EXPIRY_DATE - CURRENT_DATE) / 86400 ))
    
    if [ $DAYS_UNTIL_EXPIRY -gt 30 ]; then
        print_success "Certificate is valid for $DAYS_UNTIL_EXPIRY more days"
    elif [ $DAYS_UNTIL_EXPIRY -gt 0 ]; then
        print_warning "Certificate expires in $DAYS_UNTIL_EXPIRY days - consider renewal"
    else
        print_error "Certificate has expired!"
        print_status "Run '$0 ssl' to renew certificates"
    fi
}

# Function to setup HTTP-only mode
setup_http_only() {
    print_warning "Setting up HTTP-only mode..."
    print_warning "This will disable SSL and serve content over HTTP only"
    
    read -p "Are you sure you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "HTTP-only setup cancelled"
        exit 0
    fi
    
    setup_http_only_fallback
}

# Function to check domain configuration
check_domain_config() {
    print_status "Checking domain configuration for books.enspire2025.in..."
    
    # Check if domain resolves to current server
    DOMAIN_IP=$(dig +short books.enspire2025.in 2>/dev/null || nslookup books.enspire2025.in 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    
    if [ -z "$DOMAIN_IP" ]; then
        print_error "Could not resolve domain books.enspire2025.in"
        print_status "Please check your DNS configuration"
        return 1
    fi
    
    print_success "Domain resolves to: $DOMAIN_IP"
    
    # Get current server's public IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    
    if [ "$SERVER_IP" = "unknown" ]; then
        print_warning "Could not determine server's public IP"
        print_status "Please manually verify that $DOMAIN_IP points to this server"
    elif [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
        print_success "✅ Domain correctly points to this server ($SERVER_IP)"
    else
        print_error "❌ Domain points to $DOMAIN_IP but server IP is $SERVER_IP"
        print_warning "Please update your DNS records to point to $SERVER_IP"
        return 1
    fi
    
    # Test HTTP connectivity
    print_status "Testing HTTP connectivity..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://books.enspire2025.in --connect-timeout 10 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "301" ] || [ "$HTTP_STATUS" = "302" ]; then
        print_success "✅ HTTP connectivity working (status: $HTTP_STATUS)"
    else
        print_warning "⚠️  HTTP connectivity issue (status: $HTTP_STATUS)"
    fi
    
    # Test HTTPS connectivity
    print_status "Testing HTTPS connectivity..."
    HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://books.enspire2025.in --connect-timeout 10 2>/dev/null || echo "000")
    
    if [ "$HTTPS_STATUS" = "200" ] || [ "$HTTPS_STATUS" = "301" ] || [ "$HTTPS_STATUS" = "302" ]; then
        print_success "✅ HTTPS connectivity working (status: $HTTPS_STATUS)"
    else
        print_warning "⚠️  HTTPS connectivity issue (status: $HTTPS_STATUS)"
        print_status "This is normal if SSL certificates are not yet configured"
    fi
}

# Function to setup SSL using host machine certbot
setup_host_ssl() {
    print_status "Setting up SSL using host machine certbot..."
    
    # Check if host SSL script exists
    if [ ! -f "$SCRIPT_DIR/setup-host-ssl.sh" ]; then
        print_error "Host SSL script not found: $SCRIPT_DIR/setup-host-ssl.sh"
        exit 1
    fi
    
    # Make the script executable
    chmod +x "$SCRIPT_DIR/setup-host-ssl.sh"
    
    print_status "This will use host-based SSL with the following benefits:"
    print_status "  ✅ No rate limiting issues"
    print_status "  ✅ Better certificate management"
    print_status "  ✅ Automatic renewal via cron"
    print_status "  ✅ No container restarts needed"
    echo
    
    read -p "Continue with host-based SSL setup? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Host SSL setup cancelled"
        exit 0
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_warning "Certbot not found on host machine"
        read -p "Install certbot now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installing certbot..."
            sudo "$SCRIPT_DIR/setup-host-ssl.sh" install
        else
            print_status "Please install certbot manually and run this command again"
            exit 1
        fi
    fi
    
    # Obtain certificates
    print_status "Obtaining SSL certificates..."
    sudo "$SCRIPT_DIR/setup-host-ssl.sh" obtain
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates obtained successfully!"
        
        # Switch to host SSL docker-compose
        print_status "Switching to host-based SSL configuration..."
        
        # Stop current containers
        if [ -f "docker-compose.prod.yml" ]; then
            docker-compose -f docker-compose.prod.yml down 2>/dev/null || true
        fi
        
        # Start with host SSL configuration
        docker-compose -f docker-compose.prod.hostssl.yml up --build -d
        
        if [ $? -eq 0 ]; then
            print_success "Production environment started with host-based SSL!"
            print_status "Your site is now available at: https://books.enspire2025.in"
            
            # Setup automatic renewal
            read -p "Setup automatic certificate renewal? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo "$SCRIPT_DIR/setup-host-ssl.sh" setup-cron
                print_success "Automatic renewal configured!"
            fi
            
        else
            print_error "Failed to start production environment with SSL"
            exit 1
        fi
        
    else
        print_error "Failed to obtain SSL certificates"
        exit 1
    fi
}

# Main execution logic
case $COMMAND in
    "start"|"up")
        setup_env_file
        check_prerequisites
        start_production
        ;;
    "stop"|"down")
        check_prerequisites
        stop_production
        ;;
    "restart")
        check_prerequisites
        restart_production
        ;;
    "rebuild")
        setup_env_file
        check_prerequisites
        rebuild_production
        ;;
    "fresh-start")
        setup_env_file
        check_prerequisites
        fresh_start_production
        ;;
    "logs")
        check_prerequisites
        show_logs
        ;;
    "status")
        check_prerequisites
        show_status
        ;;
    "ssl")
        setup_env_file
        check_prerequisites
        setup_ssl
        ;;
    "ssl-host")
        setup_env_file
        check_prerequisites
        setup_host_ssl
        ;;
    "ssl-status")
        check_ssl_status
        ;;
    "http-only")
        setup_env_file
        check_prerequisites
        setup_http_only
        ;;
    "domain-check")
        check_domain_config
        ;;
    "backup")
        setup_env_file
        check_prerequisites
        backup_database
        ;;
    "restore")
        setup_env_file
        check_prerequisites
        restore_database "$@"
        ;;
    "shell")
        check_prerequisites
        run_django_shell
        ;;
    "createsuperuser")
        check_prerequisites
        create_superuser
        ;;
    "makemigrations")
        check_prerequisites
        create_migrations "$@"
        ;;
    "migrate")
        check_prerequisites
        run_migrations
        ;;
    "collectstatic")
        check_prerequisites
        collect_static
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