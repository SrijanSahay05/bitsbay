#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🔍 BitsBay Debug Script"
echo "======================"
echo

# Check if containers are running
print_status "Checking container status..."
docker-compose -f docker-compose.prod.yml ps

echo
print_status "Checking web application logs (last 20 lines)..."
docker-compose -f docker-compose.prod.yml logs web --tail=20

echo
print_status "Checking nginx logs (last 10 lines)..."
docker-compose -f docker-compose.prod.yml logs nginx --tail=10

echo
print_status "Testing container connectivity..."

# Test if web container is responding
if docker-compose -f docker-compose.prod.yml exec web curl -f http://localhost:8000/ > /dev/null 2>&1; then
    print_success "Web container is responding internally"
else
    print_error "Web container is NOT responding internally"
fi

# Check if nginx can reach web
if docker-compose -f docker-compose.prod.yml exec nginx curl -f http://web:8000/ > /dev/null 2>&1; then
    print_success "Nginx can reach web container"
else
    print_error "Nginx CANNOT reach web container"
fi

echo
print_status "Checking Django settings..."
docker-compose -f docker-compose.prod.yml exec web python manage.py check --deploy

echo
print_status "Testing direct API access..."
echo "Trying to access the home endpoint directly..."
docker-compose -f docker-compose.prod.yml exec web curl -v http://localhost:8000/

echo
print_status "Checking environment variables..."
docker-compose -f docker-compose.prod.yml exec web env | grep -E "(DEBUG|ALLOWED_HOSTS|DJANGO_SECRET_KEY)"

echo
print_status "Checking static files..."
docker-compose -f docker-compose.prod.yml exec web python manage.py collectstatic --dry-run

echo
print_success "Debug information collected!"
echo
print_warning "Common 500 Error Causes:"
echo "1. DEBUG=True with empty ALLOWED_HOSTS in production"
echo "2. Missing environment variables"
echo "3. Database connection issues"
echo "4. Static files configuration problems"
echo "5. Missing SECRET_KEY"
echo
print_status "Next steps:"
echo "1. Check the web logs above for specific error messages"
echo "2. Verify your .env.prod file has all required variables"
echo "3. Make sure DEBUG=False in production"
echo "4. Restart the application: docker-compose -f docker-compose.prod.yml restart web"
