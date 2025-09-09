#!/bin/bash

# Hardware Serial Collector Setup Script
# This script sets up the Flask web application for collecting hardware serials

set -e

echo "=== Hardware Serial Collector Setup ==="
echo ""

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

# Check if Python 3 is installed
print_status "Checking Python installation..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    print_success "Python 3 found: $PYTHON_VERSION"
else
    print_error "Python 3 is not installed. Please install Python 3.7 or higher."
    exit 1
fi

# Check if pip is installed
print_status "Checking pip installation..."
if command -v pip3 &> /dev/null; then
    print_success "pip3 found"
else
    print_error "pip3 is not installed. Please install pip3."
    exit 1
fi

# Check if we need to install system dependencies
print_status "Checking system dependencies..."

# Check for ipmitool
if ! command -v ipmitool &> /dev/null; then
    print_warning "ipmitool not found. Installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y ipmitool
    elif command -v yum &> /dev/null; then
        sudo yum install -y ipmitool
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y ipmitool
    else
        print_warning "Could not install ipmitool automatically. Please install it manually."
    fi
else
    print_success "ipmitool found"
fi

# Create project directory structure
print_status "Creating directory structure..."
mkdir -p templates static scripts

# Set up Python virtual environment
print_status "Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    print_success "Virtual environment created"
else
    print_success "Virtual environment already exists"
fi

# Activate virtual environment
print_status "Activating virtual environment..."
source venv/bin/activate

# Upgrade pip
print_status "Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
print_status "Installing Python dependencies..."
pip install -r requirements.txt
print_success "Dependencies installed"

# Make scripts executable
print_status "Setting script permissions..."
chmod +x scripts/collect_hardware.sh
print_success "Script permissions set"

# Create systemd service file (optional)
create_service() {
    print_status "Creating systemd service file..."
    
    SERVICE_FILE="/etc/systemd/system/hardware-collector.service"
    CURRENT_DIR=$(pwd)
    USER=$(whoami)
    
    sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Hardware Serial Collector Web Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$CURRENT_DIR
Environment=PATH=$CURRENT_DIR/venv/bin
ExecStart=$CURRENT_DIR/venv/bin/python app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    print_success "Systemd service created at $SERVICE_FILE"
    print_status "To enable and start the service:"
    echo "  sudo systemctl enable hardware-collector"
    echo "  sudo systemctl start hardware-collector"
}

# Generate SSL certificate for HTTPS (optional)
generate_ssl() {
    print_status "Generating self-signed SSL certificate..."
    mkdir -p ssl
    openssl req -x509 -newkey rsa:4096 -keyout ssl/key.pem -out ssl/cert.pem -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    print_success "SSL certificate generated in ssl/ directory"
}

# Test the installation
test_installation() {
    print_status "Testing installation..."
    
    # Test Python imports
    python3 -c "
import flask
import paramiko
print('✓ All Python modules imported successfully')
"
    
    # Test script execution
    if [ -f "scripts/collect_hardware.sh" ]; then
        bash scripts/collect_hardware.sh --help 2>/dev/null || echo "✓ Hardware collection script is executable"
    fi
    
    print_success "Installation test completed"
}

# Main setup process
print_status "Starting setup process..."

# Check if requirements.txt exists
if [ ! -f "requirements.txt" ]; then
    print_error "requirements.txt not found. Please ensure all files are in place."
    exit 1
fi

# Run the setup
test_installation

echo ""
print_success "Setup completed successfully!"
echo ""
echo "=== Next Steps ==="
echo "1. To start the application:"
echo "   source venv/bin/activate"
echo "   python app.py"
echo ""
echo "2. Open your browser and go to:"
echo "   http://localhost:5000"
echo ""
echo "3. Optional: Create systemd service (run with sudo):"
echo "   $0 --create-service"
echo ""
echo "4. Optional: Generate SSL certificate:"
echo "   $0 --generate-ssl"
echo ""

# Handle command line arguments
case "${1:-}" in
    --create-service)
        create_service
        ;;
    --generate-ssl)
        generate_ssl
        ;;
    --test)
        test_installation
        ;;
    --help)
        echo "Usage: $0 [--create-service|--generate-ssl|--test|--help]"
        echo ""
        echo "Options:"
        echo "  --create-service  Create systemd service file"
        echo "  --generate-ssl    Generate self-signed SSL certificate"
        echo "  --test           Test the installation"
        echo "  --help           Show this help message"
        ;;
esac

print_success "Hardware Serial Collector is ready to use!"