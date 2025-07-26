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
    echo "  start, up      - Start all containers (default)"
    echo "  stop, down     - Stop all containers"
    echo "  restart        - Restart all containers"
    echo "  rebuild        - Rebuild and start containers"
    echo "  logs           - Show container logs"
    echo "  shell          - Open Django shell"
    echo "  createsuperuser - Create Django superuser"
    echo "  migrate        - Run Django migrations"
    echo "  collectstatic  - Collect static files"
    echo "  status         - Show container status"
    echo "  resetdb        - Reset database (remove migrations and start fresh)"
    echo "  app <name>     - Create a new Django app"
    echo "  help           - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start containers (default)"
    echo "  $0 restart      # Restart containers"
    echo "  $0 shell        # Open Django shell"
    echo "  $0 logs         # Show logs"
    echo "  $0 resetdb      # Reset database completely"
    echo "  $0 app marketplace # Create marketplace app"
}

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

# Function to load environment variables
load_env() {
    if [ -f ".env.dev" ]; then
        print_status "Loading environment variables from .env.dev..."
        export $(grep -v '^#' .env.dev | xargs)
        print_success "Environment variables loaded"
    else
        print_error ".env.dev file not found"
        exit 1
    fi
}

# Function to run docker-compose with environment
run_docker_compose() {
    local cmd="$1"
    load_env
    docker-compose -f docker-compose.dev.yml $cmd
}

# Function to setup environment file
setup_env_file() {
    if [ ! -f ".env.dev" ]; then
        print_warning ".env.dev file not found"
        
        # Check if example.env.dev exists
        if [ -f "example.env.dev" ]; then
            print_status "Copying example.env.dev to .env.dev..."
            cp example.env.dev .env.dev
            
            if [ $? -eq 0 ]; then
                print_success "Successfully created .env.dev from example.env.dev"
                
                # Prompt user to edit the .env.dev file
                print_warning "Please edit the .env.dev file with your configuration values"
                echo
                read -p "Would you like to edit .env.dev now? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    print_status "Opening .env.dev for editing..."
                    
                    # Try to open with default editor, fallback to nano
                    if command -v code &> /dev/null; then
                        code .env.dev
                    elif command -v vim &> /dev/null; then
                        vim .env.dev
                    elif command -v nano &> /dev/null; then
                        nano .env.dev
                    else
                        print_warning "No suitable editor found. Please manually edit .env.dev"
                    fi
                    
                    # Ask user to confirm they've edited the file
                    echo
                    read -p "Have you finished editing .env.dev? (y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_warning "Please edit .env.dev and run this script again"
                        exit 1
                    fi
                else
                    print_warning "Make sure to edit .env.dev with proper configuration values before starting the application"
                fi
            else
                print_error "Failed to copy example.env.dev to .env.dev"
                exit 1
            fi
        else
            print_error "example.env.dev file not found. Please create .env.dev manually"
            exit 1
        fi
    else
        print_success ".env.dev file already exists"
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

    # Check if docker-compose.dev.yml exists
    if [ ! -f "docker-compose.dev.yml" ]; then
        print_error "docker-compose.dev.yml file not found"
        exit 1
    fi
}

# Function to start containers
start_containers() {
    print_status "Starting Docker containers with docker-compose.dev.yml..."
    
    # Stop any existing containers
    print_status "Stopping existing containers..."
    run_docker_compose "down --remove-orphans"
    
    # Build and start containers
    print_status "Building and starting containers..."
    run_docker_compose "up --build -d"
    
    if [ $? -eq 0 ]; then
        print_success "Development environment deployed successfully!"
        print_status "Services are starting up..."
        print_status "Web application will be available at: http://localhost"
        print_status "Django admin will be available at: http://localhost:8000/admin"
        print_status "Database is accessible on port 5432"
        
        echo
        print_status "Container status:"
        run_docker_compose "ps"
        
        echo
        print_status "To view logs, run: $0 logs"
        print_status "To stop the environment, run: $0 stop"
        print_status "To rebuild containers, run: $0 rebuild"
    else
        print_error "Failed to start Docker containers"
        print_status "Check the logs with: $0 logs"
        exit 1
    fi
}

# Function to stop containers
stop_containers() {
    print_status "Stopping Docker containers..."
    run_docker_compose "down"
    print_success "Containers stopped"
}

# Function to restart containers
restart_containers() {
    print_status "Restarting Docker containers..."
    run_docker_compose "restart"
    print_success "Containers restarted"
}

# Function to rebuild containers
rebuild_containers() {
    print_status "Rebuilding and starting containers..."
    run_docker_compose "down --remove-orphans"
    run_docker_compose "up --build -d"
    print_success "Containers rebuilt and started"
}

# Function to show logs
show_logs() {
    print_status "Showing container logs..."
    run_docker_compose "logs -f"
}

# Function to show status
show_status() {
    print_status "Container status:"
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

# Function to create new Django app
create_django_app() {
    if [ -z "$APP_NAME" ]; then
        print_error "App name is required. Usage: $0 app <app_name>"
        exit 1
    fi
    
    print_status "Creating Django app: $APP_NAME"
    
    # Check if app already exists
    if [ -d "$APP_NAME" ]; then
        print_warning "App directory '$APP_NAME' already exists"
        read -p "Do you want to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "App creation cancelled"
            exit 0
        fi
    fi
    
    # Create the app using Django management command
    print_status "Running Django startapp command..."
    run_docker_compose "exec web python manage.py startapp $APP_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Django app '$APP_NAME' created successfully!"
        print_status "App directory: $APP_NAME/"
        print_status "Don't forget to add '$APP_NAME' to INSTALLED_APPS in settings.py"
        print_status "You can now start adding models, views, and URLs to your app"
    else
        print_error "Failed to create Django app '$APP_NAME'"
        exit 1
    fi
}

# Function to reset database
reset_database() {
    print_warning "This will completely reset the database and remove all migrations!"
    print_warning "All data will be lost!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Database reset cancelled"
        exit 0
    fi
    
    print_status "Stopping containers..."
    run_docker_compose "down"
    
    print_status "Removing database volume..."
    run_docker_compose "down -v"
    
    print_status "Removing all migration files..."
    find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
    find . -path "*/migrations/*.pyc" -delete
    
    print_status "Starting containers..."
    run_docker_compose "up -d"
    
    print_status "Waiting for database to be ready..."
    sleep 10
    
    print_status "Creating fresh migrations..."
    run_docker_compose "exec web python manage.py makemigrations"
    
    print_status "Applying migrations..."
    run_docker_compose "exec web python manage.py migrate"
    
    print_status "Collecting static files..."
    run_docker_compose "exec web python manage.py collectstatic --noinput"
    
    print_success "Database reset completed successfully!"
    print_status "You can now create a superuser with: $0 createsuperuser"
}

# Main execution logic
case $COMMAND in
    "start"|"up")
        setup_env_file
        check_prerequisites
        start_containers
        ;;
    "stop"|"down")
        check_prerequisites
        stop_containers
        ;;
    "restart")
        check_prerequisites
        restart_containers
        ;;
    "rebuild")
        setup_env_file
        check_prerequisites
        rebuild_containers
        ;;
    "logs")
        check_prerequisites
        show_logs
        ;;
    "status")
        check_prerequisites
        show_status
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
        setup_env_file
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