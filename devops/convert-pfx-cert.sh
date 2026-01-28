#!/usr/bin/env bash
#
# convert-pfx-cert.sh - Convert PFX/PKCS#12 certificate to PEM format for Caddy
#
# This script extracts certificate and private key from a PFX file and places
# them in the correct location for StatBus custom TLS configuration.
#
# Usage:
#   ./devops/convert-pfx-cert.sh <pfx-file> [output-name]
#
# Examples:
#   ./devops/convert-pfx-cert.sh ~/Downloads/certificate.pfx
#   ./devops/convert-pfx-cert.sh ~/Downloads/certificate.pfx albania
#
# The script will:
#   1. Prompt for the PFX password
#   2. Extract the certificate chain (fullchain format)
#   3. Extract and decrypt the private key
#   4. Place files in caddy/data/custom-certs/
#   5. Set secure permissions
#   6. Show the .env.config settings to use
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Find project root (where .env.config lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Target directory for certificates
CERT_DIR="$PROJECT_ROOT/caddy/data/custom-certs"

usage() {
    echo "Usage: $0 <pfx-file> [output-name]"
    echo ""
    echo "Arguments:"
    echo "  pfx-file     Path to the PFX/PKCS#12 certificate file"
    echo "  output-name  Base name for output files (default: derived from PFX filename)"
    echo ""
    echo "Examples:"
    echo "  $0 ~/Downloads/certificate.pfx"
    echo "  $0 ~/Downloads/certificate.pfx albania"
    echo ""
    echo "Output files will be placed in: $CERT_DIR/"
    exit 1
}

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

PFX_FILE="$1"
OUTPUT_NAME="${2:-}"

# Validate PFX file exists
if [[ ! -f "$PFX_FILE" ]]; then
    error "PFX file not found: $PFX_FILE"
fi

# Check for openssl
if ! command -v openssl &> /dev/null; then
    error "openssl is required but not installed. Please install OpenSSL."
fi

# Derive output name from PFX filename if not provided
if [[ -z "$OUTPUT_NAME" ]]; then
    OUTPUT_NAME=$(basename "$PFX_FILE" | sed 's/\.[^.]*$//')
    # Sanitize: lowercase, replace spaces with hyphens
    OUTPUT_NAME=$(echo "$OUTPUT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
fi

# Output file paths
CERT_FILE="$CERT_DIR/${OUTPUT_NAME}.crt"
KEY_FILE="$CERT_DIR/${OUTPUT_NAME}.key"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}     PFX to PEM Certificate Converter for StatBus          ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

info "PFX file: $PFX_FILE"
info "Output name: $OUTPUT_NAME"
info "Certificate: $CERT_FILE"
info "Private key: $KEY_FILE"
echo ""

# Create output directory if needed
if [[ ! -d "$CERT_DIR" ]]; then
    info "Creating certificate directory: $CERT_DIR"
    mkdir -p "$CERT_DIR"
fi

# Check if output files already exist
if [[ -f "$CERT_FILE" ]] || [[ -f "$KEY_FILE" ]]; then
    warn "Output files already exist!"
    read -p "Overwrite existing files? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Prompt for PFX password
echo -e "${YELLOW}Enter the PFX password:${NC}"
read -s PFX_PASSWORD
echo ""

# Validate the PFX file and password
info "Validating PFX file..."
if ! openssl pkcs12 -in "$PFX_FILE" -nokeys -passin "pass:$PFX_PASSWORD" -passout "pass:" &>/dev/null; then
    error "Failed to read PFX file. Check the password and file format."
fi
success "PFX file validated"

# Extract certificate chain (fullchain format)
# -clcerts: only client certs, -cacerts: only CA certs
# We want both for fullchain, so we use -nokeys without filters
info "Extracting certificate chain..."
if ! openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -passin "pass:$PFX_PASSWORD" -passout "pass:" 2>/dev/null > "$CERT_FILE.tmp"; then
    rm -f "$CERT_FILE.tmp"
    error "Failed to extract certificate"
fi

# Also extract CA certificates and append them
if openssl pkcs12 -in "$PFX_FILE" -cacerts -nokeys -passin "pass:$PFX_PASSWORD" -passout "pass:" 2>/dev/null >> "$CERT_FILE.tmp"; then
    : # CA certs extracted successfully
fi

# Clean up the certificate file (remove bag attributes, keep only PEM blocks)
grep -A1000 "BEGIN CERTIFICATE" "$CERT_FILE.tmp" | grep -B1000 "END CERTIFICATE" > "$CERT_FILE" || true
rm -f "$CERT_FILE.tmp"

if [[ ! -s "$CERT_FILE" ]]; then
    rm -f "$CERT_FILE"
    error "No certificates found in PFX file"
fi
success "Certificate chain extracted"

# Extract private key (decrypted)
info "Extracting private key..."
if ! openssl pkcs12 -in "$PFX_FILE" -nocerts -nodes -passin "pass:$PFX_PASSWORD" 2>/dev/null > "$KEY_FILE.tmp"; then
    rm -f "$KEY_FILE.tmp" "$CERT_FILE"
    error "Failed to extract private key"
fi

# Clean up the key file (remove bag attributes, keep only PEM block)
grep -A1000 "BEGIN" "$KEY_FILE.tmp" | grep -B1000 "END" > "$KEY_FILE" || true
rm -f "$KEY_FILE.tmp"

if [[ ! -s "$KEY_FILE" ]]; then
    rm -f "$KEY_FILE" "$CERT_FILE"
    error "No private key found in PFX file"
fi
success "Private key extracted"

# Set secure permissions
info "Setting secure permissions..."
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"
success "Permissions set (cert: 644, key: 600)"

# Verify the certificate and key match
info "Verifying certificate and key match..."
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERT_FILE" 2>/dev/null | openssl md5)
KEY_MODULUS=$(openssl rsa -noout -modulus -in "$KEY_FILE" 2>/dev/null | openssl md5 || \
              openssl ec -noout -text -in "$KEY_FILE" 2>/dev/null | openssl md5)

if [[ "$CERT_MODULUS" != "$KEY_MODULUS" ]]; then
    warn "Certificate and private key may not match!"
    warn "This could indicate a problem with the PFX file."
else
    success "Certificate and key match"
fi

# Show certificate details
echo ""
echo -e "${BLUE}Certificate details:${NC}"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'

# Count certificates in chain
CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CERT_FILE" || echo "0")
echo "  Chain length: $CERT_COUNT certificate(s)"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                    Conversion Complete!                    ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Files created:"
echo "  Certificate: $CERT_FILE"
echo "  Private key: $KEY_FILE"
echo ""

# Update .env.config with new certificate paths
ENV_CONFIG="$PROJECT_ROOT/.env.config"
TLS_CERT_VALUE="/data/custom-certs/${OUTPUT_NAME}.crt"
TLS_KEY_VALUE="/data/custom-certs/${OUTPUT_NAME}.key"

if [[ -f "$ENV_CONFIG" ]]; then
    info "Updating .env.config with certificate paths..."
    
    # Update TLS_CERT_FILE (handle both empty and existing values)
    if grep -q "^TLS_CERT_FILE=" "$ENV_CONFIG"; then
        sed -i.bak "s|^TLS_CERT_FILE=.*|TLS_CERT_FILE=$TLS_CERT_VALUE|" "$ENV_CONFIG"
    else
        echo "TLS_CERT_FILE=$TLS_CERT_VALUE" >> "$ENV_CONFIG"
    fi
    
    # Update TLS_KEY_FILE (handle both empty and existing values)
    if grep -q "^TLS_KEY_FILE=" "$ENV_CONFIG"; then
        sed -i.bak "s|^TLS_KEY_FILE=.*|TLS_KEY_FILE=$TLS_KEY_VALUE|" "$ENV_CONFIG"
    else
        echo "TLS_KEY_FILE=$TLS_KEY_VALUE" >> "$ENV_CONFIG"
    fi
    
    rm -f "$ENV_CONFIG.bak"
    success "Updated .env.config"
    echo "  TLS_CERT_FILE=$TLS_CERT_VALUE"
    echo "  TLS_KEY_FILE=$TLS_KEY_VALUE"
    echo ""
    
    # Regenerate configuration
    info "Regenerating Caddy configuration..."
    if "$PROJECT_ROOT/devops/manage-statbus.sh" generate-config >/dev/null 2>&1; then
        success "Configuration regenerated"
    else
        warn "Failed to regenerate configuration. Run manually:"
        echo "  ./devops/manage-statbus.sh generate-config"
    fi
    echo ""
    
    # Offer to restart Caddy
    echo -e "${YELLOW}Final step:${NC} Restart Caddy to use the new certificate"
    echo ""
    read -p "Restart Caddy now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        info "Restarting Caddy..."
        if docker compose -f "$PROJECT_ROOT/docker-compose.yml" restart proxy >/dev/null 2>&1; then
            success "Caddy restarted with new certificate"
        else
            warn "Failed to restart Caddy. Run manually:"
            echo "  docker compose restart proxy"
        fi
    else
        echo ""
        echo "To apply the certificate, run:"
        echo "  docker compose restart proxy"
    fi
else
    warn ".env.config not found at $ENV_CONFIG"
    echo ""
    echo -e "${YELLOW}Manual steps required:${NC}"
    echo ""
    echo "1. Add to .env.config:"
    echo ""
    echo "   TLS_CERT_FILE=$TLS_CERT_VALUE"
    echo "   TLS_KEY_FILE=$TLS_KEY_VALUE"
    echo ""
    echo "2. Regenerate configuration:"
    echo ""
    echo "   ./devops/manage-statbus.sh generate-config"
    echo ""
    echo "3. Restart Caddy:"
    echo ""
    echo "   docker compose restart proxy"
fi

echo ""
success "Done!"
echo ""
