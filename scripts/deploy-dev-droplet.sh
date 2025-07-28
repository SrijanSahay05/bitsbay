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
    echo "Deploy development environment to droplet with SSL"
    echo ""
    echo "Commands:"
    echo "  start, up      - Start development environment on droplet (default)"
    echo "  stop, down     - Stop development environment"
    echo "  restart        - Restart development environment"
    echo "  rebuild        - Rebuild and start containers"
    echo "  fresh-start    - Reset database and start fresh (DESTRUCTIVE!)"
    echo "  logs           - Show container logs"
    echo "  status         - Show container status"
    echo "  ssl            - Setup/renew SSL certificates"
    echo "  shell          - Open Django shell"
    echo "  createsuperuser - Create Django superuser"
    echo "  migrate        - Run Django migrations"
    echo "  collectstatic  - Collect static files"
    echo "  resetdb        - Reset database (remove migrations and start fresh)"
    echo "  app <name>     - Create a new Django app"
    echo "  help           - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start development on droplet (default)"
    echo "  $0 restart      # Restart development environment"
    echo "  $0 fresh-start  # Reset database and start fresh"
    echo "  $0 ssl          # Setup SSL certificates"
    echo "  $0 logs         # Show logs"
    echo ""
    echo "Environment Variables:"
    echo "  Required environment variables (set in .env file or export):"
    echo "    GOOGLE_OAUTH2_CLIENT_ID     - Google OAuth client ID"
    echo "    GOOGLE_OAUTH2_CLIENT_SECRET - Google OAuth client secret"
    echo ""
    echo "  Create a .env file from .env.example and set your values:"
    echo "    cp .env.example .env"
    echo "    # Edit .env with your credentials"
}

# Configuration
DOMAIN="shreyas.srijansahay05.in"
EMAIL="srijan05sahay@gmail.com"

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
COMMAND=${1:-start}
APP_NAME=${2:-""}

# Change to project root directory
cd "$PROJECT_ROOT" || {
    print_error "Failed to change to project root directory"
    exit 1
}

# Function to create development droplet environment file
create_dev_droplet_env() {
    print_status "Creating .env.dev.droplet file for staging deployment..."
    
    cat > .env.dev.droplet << EOF
# Django settings for development on droplet
DJANGO_SECRET_KEY=dev-droplet-secret-key-change-in-production
DEBUG=True

# Database settings
POSTGRES_DB=django_dev_droplet
POSTGRES_USER=postgres_user
POSTGRES_PASSWORD=dev_droplet_postgres_password
DB_HOST=db
DB_PORT=5432

# Django allowed hosts - include droplet domain
ALLOWED_HOSTS=$DOMAIN,localhost,127.0.0.1,0.0.0.0,web,nginx

# Security settings for droplet (relaxed for development)
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_SSL_REDIRECT=False
SECURE_HSTS_SECONDS=0
SECURE_HSTS_INCLUDE_SUBDOMAINS=False
SECURE_HSTS_PRELOAD=False
SECURE_CONTENT_TYPE_NOSNIFF=True
SECURE_BROWSER_XSS_FILTER=True
X_FRAME_OPTIONS=SAMEORIGIN

# CORS and CSRF settings
CORS_ALLOW_ALL_ORIGINS=True
CORS_ALLOW_CREDENTIALS=True
CSRF_TRUSTED_ORIGINS=https://$DOMAIN,http://$DOMAIN
CSRF_COOKIE_DOMAIN=$DOMAIN
SESSION_COOKIE_DOMAIN=$DOMAIN

# Development API keys - Set these environment variables before running
# GOOGLE_OAUTH2_CLIENT_ID=your-google-oauth-client-id
# GOOGLE_OAUTH2_CLIENT_SECRET=your-google-oauth-client-secret
GOOGLE_OAUTH2_CLIENT_ID=\${GOOGLE_OAUTH2_CLIENT_ID:-}
GOOGLE_OAUTH2_CLIENT_SECRET=\${GOOGLE_OAUTH2_CLIENT_SECRET:-}
EOF
    
    print_success "Created .env.dev.droplet file"
}

# Function to create development droplet docker-compose file
create_dev_droplet_compose() {
    print_status "Creating docker-compose.dev.droplet.yml..."
    
    cat > docker-compose.dev.droplet.yml << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data_dev_droplet:/var/lib/postgresql/data/
    ports:
      - "5433:5432"  # Different port to avoid conflicts
    restart: unless-stopped

  web:
    build:
      context: .
      dockerfile: dockerfile.dev
    command: >
      sh -c "python manage.py migrate &&
             python manage.py collectstatic --noinput &&
             gunicorn core.wsgi:application --bind 0.0.0.0:8000 --workers 2 --reload"
    volumes:
      - .:/app
      - static_volume_dev:/app/staticfiles
      - media_volume_dev:/app/media
    ports:
      - "8001:8000"  # Different port for development
    env_file:
      - .env.dev.droplet
    depends_on:
      - db
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.dev.droplet.conf:/etc/nginx/nginx.conf
      - static_volume_dev:/app/staticfiles
      - media_volume_dev:/app/media
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
    depends_on:
      - web
    restart: unless-stopped

  certbot:
    image: certbot/certbot
    volumes:
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
    command: certonly --webroot --webroot-path=/var/www/certbot --email srijan05sahay@gmail.com --agree-tos --no-eff-email --force-renewal -d shreyas.srijansahay05.in

volumes:
  postgres_data_dev_droplet:
  static_volume_dev:
  media_volume_dev:
  certbot_conf:
  certbot_www:
EOF
    
    print_success "Created docker-compose.dev.droplet.yml"
}

# Function to create nginx configuration for development droplet
create_dev_droplet_nginx() {
    print_status "Creating nginx configuration for development droplet..."
    
    mkdir -p nginx
    
    cat > nginx/nginx.dev.droplet.conf << EOF
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    upstream web {
        server web:8000;
    }

    # HTTP server - redirect to HTTPS and handle certbot
    server {
        listen 80;
        server_name $DOMAIN;

        # Certbot challenge
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Health check endpoint (allow HTTP for development)
        location /health/ {
            return 200 "Development OK";
            add_header Content-Type text/plain;
        }

        # For development, allow both HTTP and HTTPS
        location / {
            # Check if SSL certificate exists
            if (-f /etc/letsencrypt/live/$DOMAIN/fullchain.pem) {
                return 301 https://\$host\$request_uri;
            }
            
            # Serve directly over HTTP if no SSL certificate
            proxy_pass http://web;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # CORS headers for development
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            
            if (\$request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin *;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type 'text/plain; charset=utf-8';
                add_header Content-Length 0;
                return 204;
            }
        }
    }

    # HTTPS server - only if certificates exist
    server {
        listen 443 ssl;
        server_name $DOMAIN;

        # SSL certificates
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

        # SSL configuration (relaxed for development)
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

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
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # CORS headers for development
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            
            if (\$request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin *;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type 'text/plain; charset=utf-8';
                add_header Content-Length 0;
                return 204;
            }
        }
    }
}
EOF
    
    print_success "Created nginx configuration for development droplet"
}

# Function to load environment variables
load_env() {
    # First load from root .env file if it exists
    if [ -f ".env" ]; then
        print_status "Loading environment variables from .env..."
        export $(grep -v '^#' .env | xargs)
    fi
    
    if [ -f ".env.dev.droplet" ]; then
        print_status "Loading environment variables from .env.dev.droplet..."
        export $(grep -v '^#' .env.dev.droplet | xargs)
        print_success "Environment variables loaded"
    else
        print_error ".env.dev.droplet file not found"
        create_dev_droplet_env
        load_env
    fi
}

# Function to run docker-compose with environment
run_docker_compose() {
    local cmd="$1"
    load_env
    docker-compose -f docker-compose.dev.droplet.yml $cmd
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
}

# Function to check required environment variables
check_environment_variables() {
    local missing_vars=()
    
    if [ -z "$GOOGLE_OAUTH2_CLIENT_ID" ]; then
        missing_vars+=("GOOGLE_OAUTH2_CLIENT_ID")
    fi
    
    if [ -z "$GOOGLE_OAUTH2_CLIENT_SECRET" ]; then
        missing_vars+=("GOOGLE_OAUTH2_CLIENT_SECRET")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            print_error "  - $var"
        done
        echo
        print_status "Please set these environment variables before running the script:"
        print_status "  export GOOGLE_OAUTH2_CLIENT_ID='your-client-id'"
        print_status "  export GOOGLE_OAUTH2_CLIENT_SECRET='your-client-secret'"
        echo
        print_status "Or create a .env file in the project root with these variables"
        exit 1
    fi
}

# Function to setup environment files
setup_env_files() {
    if [ ! -f ".env.dev.droplet" ]; then
        create_dev_droplet_env
    fi
    
    if [ ! -f "docker-compose.dev.droplet.yml" ]; then
        create_dev_droplet_compose
    fi
    
    if [ ! -f "nginx/nginx.dev.droplet.conf" ]; then
        create_dev_droplet_nginx
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
        print_warning "This may conflict with the development environment"
        
        # Ask if user wants to continue
        read -p "Do you want to continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled"
            exit 0
        fi
    else
        print_success "Ports 80 and 443 are available"
    fi
}

# Function to start development environment on droplet
start_dev_droplet() {
    print_status "Starting development environment on droplet..."
    
    # Setup configuration files
    setup_env_files
    
    # Check for conflicting services
    check_and_disable_conflicting_services
    
    # Stop any existing containers
    print_status "Stopping existing containers..."
    run_docker_compose "down --remove-orphans"
    
    # Create necessary directories
    mkdir -p certbot/conf
    mkdir -p certbot/www
    
    # Build and start containers
    print_status "Building and starting containers..."
    run_docker_compose "up --build -d"
    
    if [ $? -eq 0 ]; then
        print_success "Development environment started on droplet!"
        print_status "Services are starting up..."
        print_status "Web application will be available at:"
        print_status "  HTTP:  http://$DOMAIN"
        print_status "  HTTPS: https://$DOMAIN (after SSL setup)"
        print_status "  Admin: http://$DOMAIN/admin"
        
        echo
        print_status "Container status:"
        run_docker_compose "ps"
        
        echo
        print_status "Next steps:"
        print_status "1. Setup SSL certificates: $0 ssl"
        print_status "2. Create superuser: $0 createsuperuser"
        print_status "3. View logs: $0 logs"
    else
        print_error "Failed to start development environment"
        exit 1
    fi
}

# Function to setup SSL certificates
setup_ssl() {
    print_status "Setting up SSL certificates for development environment..."
    
    # Create necessary directories
    mkdir -p certbot/conf
    mkdir -p certbot/www
    
    # Run certbot to obtain certificates
    print_status "Obtaining SSL certificates from Let's Encrypt..."
    run_docker_compose "run --rm certbot"
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates obtained successfully!"
        print_status "Restarting nginx to use new certificates..."
        run_docker_compose "restart nginx"
        print_success "SSL setup completed!"
        print_status "Your site is now available at: https://$DOMAIN"
    else
        print_error "Failed to obtain SSL certificates"
        print_status "Check that your domain points to this server"
        print_status "Site is still available at: http://$DOMAIN"
    fi
}

# Function to fresh start with clean database
fresh_start_dev_droplet() {
    print_warning "🚨 DESTRUCTIVE OPERATION: This will reset your development database!"
    print_warning "All development data will be permanently lost!"
    echo
    
    read -p "Are you sure you want to continue? Type 'YES' to confirm: " -r
    if [[ ! $REPLY = "YES" ]]; then
        print_status "Fresh start cancelled"
        exit 0
    fi
    
    print_status "Starting fresh development setup..."
    
    # Stop and remove containers and volumes
    print_status "Stopping containers and removing volumes..."
    run_docker_compose "down -v"
    
    # Remove migration files
    print_status "Removing existing migration files..."
    find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
    find . -path "*/migrations/*.pyc" -delete
    find . -path "*/migrations/__pycache__" -exec rm -rf {} + 2>/dev/null || true
    
    # Setup environment files
    setup_env_files
    
    # Start containers
    print_status "Starting fresh containers..."
    run_docker_compose "up --build -d db"
    
    # Wait for database
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
    
    print_success "🎉 Fresh development environment ready!"
    print_status "Create a superuser: $0 createsuperuser"
    print_status "Setup SSL: $0 ssl"
    print_status "Site: http://$DOMAIN"
}

# Function to stop development environment
stop_dev_droplet() {
    print_status "Stopping development environment..."
    run_docker_compose "down"
    print_success "Development environment stopped"
}

# Function to restart development environment
restart_dev_droplet() {
    print_status "Restarting development environment..."
    run_docker_compose "restart"
    print_success "Development environment restarted"
}

# Function to rebuild development environment
rebuild_dev_droplet() {
    print_status "Rebuilding development environment..."
    setup_env_files
    run_docker_compose "down --remove-orphans"
    run_docker_compose "up --build -d"
    print_success "Development environment rebuilt"
}

# Function to show logs
show_logs() {
    print_status "Showing development environment logs..."
    run_docker_compose "logs -f"
}

# Function to show status
show_status() {
    print_status "Development environment status:"
    run_docker_compose "ps"
}

# Function to run Django shell
run_django_shell() {
    print_status "Opening Django shell..."
    run_docker_compose "exec web python manage.py shell"
}

# Function to create superuser
create_superuser() {
    print_status "Creating Django superuser..."
    run_docker_compose "exec web python manage.py createsuperuser"
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

# Function to reset database
reset_database() {
    print_warning "This will reset the development database!"
    print_warning "All development data will be lost!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Database reset cancelled"
        exit 0
    fi
    
    print_status "Resetting development database..."
    run_docker_compose "down -v"
    
    # Remove migration files
    find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
    find . -path "*/migrations/*.pyc" -delete
    
    # Start containers and setup database
    run_docker_compose "up -d"
    sleep 10
    
    run_docker_compose "exec web python manage.py makemigrations"
    run_docker_compose "exec web python manage.py migrate"
    run_docker_compose "exec web python manage.py collectstatic --noinput"
    
    print_success "Development database reset completed!"
}

# Function to create Django app
create_django_app() {
    if [ -z "$APP_NAME" ]; then
        print_error "App name is required. Usage: $0 app <app_name>"
        exit 1
    fi
    
    print_status "Creating Django app: $APP_NAME"
    run_docker_compose "exec web python manage.py startapp $APP_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Django app '$APP_NAME' created successfully!"
        print_status "Don't forget to add '$APP_NAME' to INSTALLED_APPS in settings.py"
    else
        print_error "Failed to create Django app '$APP_NAME'"
        exit 1
    fi
}

# Load environment variables from .env file if available
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Main execution logic
case $COMMAND in
    "start"|"up")
        check_prerequisites
        check_environment_variables
        start_dev_droplet
        ;;
    "stop"|"down")
        check_prerequisites
        stop_dev_droplet
        ;;
    "restart")
        check_prerequisites
        restart_dev_droplet
        ;;
    "rebuild")
        check_prerequisites
        check_environment_variables
        rebuild_dev_droplet
        ;;
    "fresh-start")
        check_prerequisites
        check_environment_variables
        fresh_start_dev_droplet
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
        check_prerequisites
        setup_ssl
        ;;
    "shell")
        check_prerequisites
        run_django_shell
        ;;
    "createsuperuser")
        check_prerequisites
        create_superuser
        ;;
    "migrate")
        check_prerequisites
        run_migrations
        ;;
    "collectstatic")
        check_prerequisites
        collect_static
        ;;
    "resetdb")
        check_prerequisites
        reset_database
        ;;
    "app")
        check_prerequisites
        create_django_app
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
