#!/bin/bash
# Signbank Docker Setup Script
# This script helps set up Signbank with Docker

set -e

echo "🏗️  Signbank Docker Setup"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Determine Docker Compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

print_status "Using Docker Compose: $DOCKER_COMPOSE"

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p docker/nginx docker/postgres media static logs

# Create postgres init script
cat > docker/postgres/init.sql << 'EOF'
-- Initialize PostgreSQL for Signbank
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Set UTF-8 encoding
UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';
DROP DATABASE template1;
CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';
UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';
EOF

# Create nginx main configuration
cat > docker/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript 
               application/javascript application/xml+rss 
               application/json image/svg+xml;
    
    # Include server configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create environment file
if [ ! -f .env ]; then
    print_status "Creating environment file..."
    cat > .env << EOF
# Signbank Environment Configuration

# Django settings
DEBUG=false
SECRET_KEY=$(openssl rand -hex 32)
ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0

# Database settings
DB_NAME=signbank
DB_USER=signbank
DB_PASSWORD=$(openssl rand -hex 16)
DB_HOST=db
DB_PORT=5432

# Redis settings
REDIS_HOST=redis
REDIS_PORT=6379

# Superuser settings (change these!)
DJANGO_SUPERUSER_USERNAME=admin
DJANGO_SUPERUSER_EMAIL=admin@example.com
DJANGO_SUPERUSER_PASSWORD=admin123

# Domain settings (change for production)
DOMAIN=localhost
EOF
    print_warning "Created .env file with default settings. Please review and modify as needed!"
else
    print_status ".env file already exists, skipping creation."
fi

# Function to clone repository if needed
clone_signbank() {
    local repo_url="$1"
    local repo_name="$2"
    
    if [ ! -f "manage.py" ] && [ ! -d ".git" ]; then
        print_status "Cloning $repo_name repository..."
        git clone "$repo_url" temp_repo
        mv temp_repo/* .
        mv temp_repo/.* . 2>/dev/null || true
        rm -rf temp_repo
    else
        print_status "Signbank source code already present."
    fi
}

# Ask user which Signbank version to use
echo
echo "Which Signbank version would you like to install?"
echo "1) Global-signbank (General purpose)"
echo "2) FinSL-signbank (Finnish Sign Language)"
echo "3) BSL-signbank (British Sign Language)"
echo "4) Auslan-signbank (Australian Sign Language)"
echo "5) Skip cloning (use existing code)"
echo

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        clone_signbank "https://github.com/Signbank/Global-signbank.git" "Global-signbank"
        ;;
    2)
        clone_signbank "https://github.com/Signbank/FinSL-signbank.git" "FinSL-signbank"
        ;;
    3)
        clone_signbank "https://github.com/Signbank/BSL-signbank.git" "BSL-signbank"
        ;;
    4)
        clone_signbank "https://github.com/Signbank/Auslan-signbank.git" "Auslan-signbank"
        ;;
    5)
        print_status "Skipping repository cloning."
        ;;
    *)
        print_warning "Invalid choice, skipping repository cloning."
        ;;
esac

# Set proper permissions
print_status "Setting proper permissions..."
chmod -R 755 media static logs
sudo chown -R 1000:1000 media static logs 2>/dev/null || true

# Build and start services
print_status "Building Docker images..."
$DOCKER_COMPOSE build

print_status "Starting services..."
$DOCKER_COMPOSE up -d db redis

# TODO Wait for database to be ready
print_status "Waiting for database to be ready..."
sleep 10

# Start web services
$DOCKER_COMPOSE up -d web worker scheduler

# TODO Wait for web service to be ready
print_status "Waiting for web service to be ready..."
sleep 20

# Check if services are running
print_status "Checking service status..."
$DOCKER_COMPOSE ps

# Print success message and next steps
echo
echo -e "${GREEN}🎉 Signbank setup completed successfully!${NC}"
echo
echo "Next steps:"
echo "1. Access Signbank at: http://localhost:8000"
echo "2. Admin interface at: http://localhost:8000/admin/"
echo "3. Default admin credentials:"
echo "   - Username: admin"
echo "   - Password: admin123"
echo "   (Change these in production!)"
echo
echo "Useful commands:"
echo "  - View logs: $DOCKER_COMPOSE logs -f"
echo "  - Stop services: $DOCKER_COMPOSE down"
echo "  - Restart services: $DOCKER_COMPOSE restart"
echo "  - Access Django shell: $DOCKER_COMPOSE exec web python manage.py shell"
echo "  - Run migrations: $DOCKER_COMPOSE exec web python manage.py migrate"
echo
echo "For production deployment:"
echo "  - Update .env file with secure values"
echo "  - Configure SSL certificates"
echo "  - Start with nginx: $DOCKER_COMPOSE --profile production up -d"
echo
print_warning "Remember to change default passwords and configure your domain settings!"

# Optionally start nginx for production
read -p "Would you like to start with Nginx reverse proxy? (y/N): " start_nginx
if [[ $start_nginx =~ ^[Yy]$ ]]; then
    print_status "Starting with Nginx..."
    $DOCKER_COMPOSE --profile production up -d nginx
    echo "Nginx is now running on port 80"
fi

print_status "Setup complete! 🚀"
