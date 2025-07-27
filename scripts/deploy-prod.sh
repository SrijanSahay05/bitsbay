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
    echo "  logs           - Show production logs"
    echo "  status         - Show production container status"
    echo "  ssl            - Setup/renew SSL certificates"
    echo "  backup         - Backup database"
    echo "  restore        - Restore database from backup"
    echo "  shell          - Open Django shell in production"
    echo "  createsuperuser - Create Django superuser"
    echo "  makemigrations - Create Django migrations"
    echo "  migrate        - Run Django migrations"
    echo "  collectstatic  - Collect static files"
    echo "  help           - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start production (default)"
    echo "  $0 restart      # Restart production"
    echo "  $0 ssl          # Setup SSL certificates"
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
    
    # Stop any existing containers
    print_status "Stopping existing containers..."
    run_docker_compose "down"
    
    # Build and start containers
    print_status "Building and starting production containers..."
    run_docker_compose "up --build -d"
    
    if [ $? -eq 0 ]; then
        print_success "Production environment started successfully!"
        print_status "Services are starting up..."
        print_status "Web application will be available at: https://books.shreyas.srijansahay05.in"
        print_status "Admin panel will be available at: https://books.shreyas.srijansahay05.in/admin"
        
        echo
        print_status "Container status:"
        run_docker_compose "ps"
        
        echo
        print_status "To view logs, run: $0 logs"
        print_status "To stop the environment, run: $0 stop"
        print_status "To setup SSL certificates, run: $0 ssl"
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
    if ! grep -q "books.shreyas.srijansahay05.in" .env.prod; then
        print_error "Domain not configured in .env.prod. Please update ALLOWED_HOSTS and CSRF_TRUSTED_ORIGINS"
        exit 1
    fi
    
    # Check and disable conflicting services before SSL setup
    check_and_disable_conflicting_services
    
    # Create necessary directories
    mkdir -p certbot-www
    mkdir -p /etc/letsencrypt
    
    # Ensure proper permissions
    if [ -d "/etc/letsencrypt" ]; then
        sudo chmod 755 /etc/letsencrypt
    fi
    
    # Run certbot to obtain certificates
    print_status "Obtaining SSL certificates from Let's Encrypt..."
    run_docker_compose "run --rm certbot"
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates obtained successfully!"
        print_status "Restarting nginx to use new certificates..."
        run_docker_compose "restart nginx"
        print_success "SSL setup completed!"
    else
        print_error "Failed to obtain SSL certificates"
        print_status "Check the logs and ensure your domain is pointing to this server"
        exit 1
    fi
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