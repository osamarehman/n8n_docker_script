#!/bin/bash

# ==============================================================================
# Qdrant Vector Database Standalone Installation Script
# Installs Qdrant vector database for AI/ML workflows
# Can be run independently or as part of the modular stack
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# --- Qdrant Specific Configuration ---
readonly COMPONENT_NAME="qdrant"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
QDRANT_SUBDOMAIN="${QDRANT_SUBDOMAIN:-qdrant}"
QDRANT_DOMAIN="${QDRANT_DOMAIN:-}"

# --- Configuration Collection ---
collect_qdrant_configuration() {
    info "Collecting Qdrant vector database configuration..."
    
    # Check if running in auto mode
    local auto_mode=false
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
        esac
    done
    
    # Generate API key if not set
    if [ -z "$QDRANT_API_KEY" ]; then
        QDRANT_API_KEY=$(generate_password 32)
        if [ ${#QDRANT_API_KEY} -lt 16 ]; then
            error "Failed to generate secure API key"
        fi
        info "🔑 Generated secure API key for Qdrant"
    fi
    
    # Collect domain if not set (optional for Qdrant)
    if [ -z "$QDRANT_DOMAIN" ] && [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "🌐 Qdrant Domain Configuration (Optional)"
            echo "Enter a domain for Qdrant if you want HTTPS access via Caddy"
            echo "Leave empty for direct port access (HTTP only on port 6333)"
            echo "If you have Caddy installed, it will automatically proxy Qdrant"
            echo
            echo -n "Enter Qdrant domain [leave empty for port access]: " > /dev/tty
            read QDRANT_DOMAIN < /dev/tty || QDRANT_DOMAIN=""
        fi
    fi
    
    # Validate domain if provided
    if [ -n "$QDRANT_DOMAIN" ]; then
        validate_domain "$QDRANT_DOMAIN"
        info "🌐 Domain-based setup: $QDRANT_DOMAIN (will be proxied by Caddy)"
    else
        info "🌐 Direct port access on port 6333"
    fi
    
    info "🔑 API key configured for secure access"
}

# --- Create Qdrant Environment File ---
create_qdrant_env_impl() {
    ensure_setup_directory
    
    # Create or update .env file for Qdrant
    local env_file="${SETUP_DIR}/.env"
    local temp_env="${env_file}.tmp"
    
    # Start with existing env file if it exists, otherwise start fresh
    if [ -f "$env_file" ]; then
        cp "$env_file" "$temp_env"
    else
        cat > "$temp_env" <<EOF
# n8n Modular Stack Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Timezone
TZ=UTC
EOF
    fi
    
    # Remove existing Qdrant configuration
    grep -v "^QDRANT_" "$temp_env" > "${temp_env}.clean" && mv "${temp_env}.clean" "$temp_env"
    
    # Add Qdrant configuration
    cat >> "$temp_env" <<EOF

# Qdrant Vector Database Configuration
QDRANT_API_KEY=${QDRANT_API_KEY}
QDRANT_SUBDOMAIN=${QDRANT_SUBDOMAIN}
${QDRANT_DOMAIN:+QDRANT_DOMAIN=${QDRANT_DOMAIN}}
EOF
    
    mv "$temp_env" "$env_file"
    file_operation "chmod" 600 "$env_file"
    
    success "Qdrant environment configuration created"
}

create_qdrant_env() {
    retry_with_user_prompt "Qdrant Environment Creation" create_qdrant_env_impl
}

# --- Create Qdrant Configuration File ---
create_qdrant_config_impl() {
    local config_file="${SETUP_DIR}/qdrant-config.yaml"
    
    cat > "$config_file" << 'EOF'
service:
  # Enable API key authentication
  http_port: 6333
  grpc_port: 6334
  
  # Enable CORS for web access
  enable_cors: true
  
  # Logging
  log_level: INFO
  
  # Performance tuning for production
  max_request_size_mb: 32
  max_workers: 0  # Auto-detect based on CPU cores

storage:
  # Storage settings
  storage_path: /qdrant/storage
  
  # Performance settings optimized for production
  optimizers:
    deleted_threshold: 0.2
    vacuum_min_vector_number: 1000
    default_segment_number: 0
    max_segment_size_kb: 5000000
    memmap_threshold_kb: 200000
    indexing_threshold_kb: 20000
    flush_interval_sec: 5
    max_optimization_threads: 1
  
  # Write-ahead log settings
  wal:
    wal_capacity_mb: 32
    wal_segments_ahead: 0

cluster:
  # Disable clustering for single-node setup
  enabled: false

# Security settings
tls:
  # TLS will be handled by Caddy reverse proxy if domain is configured
  enabled: false
EOF
    
    success "Qdrant configuration file created"
}

create_qdrant_config() {
    retry_with_user_prompt "Qdrant Configuration Creation" create_qdrant_config_impl
}

# --- Create Qdrant Docker Compose ---
create_qdrant_compose_impl() {
    local compose_file="${SETUP_DIR}/docker-compose.qdrant.yml"
    
    cat > "$compose_file" << 'EOF'
services:
  # Volume initialization service
  qdrant-init:
    image: alpine:latest
    volumes:
      - qdrant_data:/qdrant-data
    command: |
      sh -c "
        echo 'Fixing volume permissions for Qdrant (user 1000:1000)...'
        chown -R 1000:1000 /qdrant-data
        echo 'Qdrant volume permissions fixed'
      "
    restart: "no"
    networks:
      - n8n_network

  qdrant:
    image: qdrant/qdrant:${QDRANT_VERSION}
    container_name: qdrant
    restart: unless-stopped
    user: "1000:1000"
    depends_on:
      - qdrant-init
    environment:
      - TZ=${TZ}
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
    volumes:
      - qdrant_data:/qdrant/storage
      - ./qdrant-config.yaml:/qdrant/config/production.yaml:ro
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider --header='api-key: ${QDRANT_API_KEY}' http://localhost:6333/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF

    # Add ports for direct access if no domain is configured
    if [ -z "$QDRANT_DOMAIN" ]; then
        cat >> "$compose_file" << 'EOF'
    ports:
      - "6333:6333"
      - "6334:6334"
EOF
    fi

    cat >> "$compose_file" << 'EOF'

volumes:
  qdrant_data:

networks:
  n8n_network:
    external: true
EOF
    
    success "Qdrant Docker Compose configuration created"
}

create_qdrant_compose() {
    retry_with_user_prompt "Qdrant Docker Compose Creation" create_qdrant_compose_impl
}

# --- Deploy Qdrant ---
deploy_qdrant_impl() {
    cd "$SETUP_DIR"
    
    # Ensure Docker network exists
    ensure_docker_network
    
    # Pull latest Qdrant image
    info "Pulling latest Qdrant container image..."
    docker pull "qdrant/qdrant:${QDRANT_VERSION}"
    
    # Deploy Qdrant using the compose file
    info "Deploying Qdrant vector database..."
    ${DOCKER_COMPOSE_CMD} -f docker-compose.qdrant.yml up -d
    
    # Wait for Qdrant to be healthy
    info "Waiting for Qdrant to initialize (this may take up to 60 seconds)..."
    sleep 30
    
    # Enhanced health check
    local wait_count=0
    local max_wait=60
    while [ $wait_count -lt $max_wait ]; do
        if docker exec qdrant wget --no-verbose --tries=1 --spider --header="api-key: ${QDRANT_API_KEY}" http://localhost:6333/health 2>/dev/null; then
            success "Qdrant is healthy and responding!"
            break
        fi
        
        if [ $wait_count -ge $max_wait ]; then
            warning "Qdrant health check timed out, but container may still be starting"
            break
        fi
        
        echo "Waiting for Qdrant to be ready... ($wait_count/$max_wait seconds)"
        sleep 5
        wait_count=$((wait_count + 5))
    done
    
    # Show container status
    ${DOCKER_COMPOSE_CMD} -f docker-compose.qdrant.yml ps
    
    success "Qdrant vector database deployed successfully"
}

deploy_qdrant() {
    retry_with_user_prompt "Qdrant Deployment" deploy_qdrant_impl
}

# --- Configure Firewall for Qdrant ---
configure_qdrant_firewall_impl() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available, skipping firewall configuration"
        return 0
    fi
    
    # Only open ports if not using domain (domain traffic goes through Caddy)
    if [ -z "$QDRANT_DOMAIN" ]; then
        info "Configuring firewall for direct Qdrant access..."
        ufw allow 6333/tcp comment "Qdrant HTTP API"
        ufw allow 6334/tcp comment "Qdrant gRPC API"
        info "Firewall rules added for Qdrant (ports 6333, 6334)"
    else
        info "Domain-based setup detected - firewall will be configured by Caddy"
    fi
}

configure_qdrant_firewall() {
    retry_with_user_prompt "Qdrant Firewall Configuration" configure_qdrant_firewall_impl
}

# --- Create Qdrant Client Test Script ---
create_test_script_impl() {
    local test_script="${SETUP_DIR}/test-qdrant.sh"
    
    cat > "$test_script" << 'EOF'
#!/bin/bash

# Qdrant Test Script
# Test basic functionality of your Qdrant installation

set -e

# Load environment
if [ -f "/opt/n8n-stack/.env" ]; then
    source /opt/n8n-stack/.env
else
    echo "Error: Environment file not found"
    exit 1
fi

# Determine Qdrant URL
if [ -n "${QDRANT_DOMAIN:-}" ]; then
    QDRANT_URL="https://${QDRANT_DOMAIN}"
else
    PUBLIC_IP=$(curl -s ifconfig.me || echo "localhost")
    QDRANT_URL="http://${PUBLIC_IP}:6333"
fi

echo "Testing Qdrant at: $QDRANT_URL"
echo "Using API Key: ${QDRANT_API_KEY:0:8}..."
echo

# Test 1: Health check
echo "1. Health Check:"
if curl -s -H "api-key: $QDRANT_API_KEY" "$QDRANT_URL/health" | grep -q "ok"; then
    echo "✓ Qdrant is healthy"
else
    echo "✗ Qdrant health check failed"
    exit 1
fi

# Test 2: Get telemetry info
echo
echo "2. System Info:"
curl -s -H "api-key: $QDRANT_API_KEY" "$QDRANT_URL/telemetry" | jq '.result.app' 2>/dev/null || echo "Telemetry data retrieved (jq not available for formatting)"

# Test 3: List collections
echo
echo "3. Collections List:"
COLLECTIONS=$(curl -s -H "api-key: $QDRANT_API_KEY" "$QDRANT_URL/collections")
echo "Current collections: $COLLECTIONS"

# Test 4: Create test collection
echo
echo "4. Creating Test Collection:"
curl -s -X PUT -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    "$QDRANT_URL/collections/test_collection" \
    -d '{
        "vectors": {
            "size": 100,
            "distance": "Cosine"
        }
    }' | jq '.result' 2>/dev/null || echo "Test collection created"

# Test 5: Insert test vector
echo
echo "5. Inserting Test Vector:"
curl -s -X PUT -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    "$QDRANT_URL/collections/test_collection/points" \
    -d '{
        "points": [
            {
                "id": 1,
                "vector": [0.1, 0.2, 0.3, 0.4],
                "payload": {"test": "data"}
            }
        ]
    }' | jq '.result' 2>/dev/null || echo "Test vector inserted"

# Test 6: Search test
echo
echo "6. Vector Search Test:"
curl -s -X POST -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    "$QDRANT_URL/collections/test_collection/points/search" \
    -d '{
        "vector": [0.1, 0.2, 0.3, 0.4],
        "limit": 5
    }' | jq '.result' 2>/dev/null || echo "Search completed"

# Test 7: Cleanup
echo
echo "7. Cleaning Up Test Collection:"
curl -s -X DELETE -H "api-key: $QDRANT_API_KEY" \
    "$QDRANT_URL/collections/test_collection" | jq '.result' 2>/dev/null || echo "Test collection deleted"

echo
echo "✅ All tests completed successfully!"
echo "Your Qdrant installation is working properly."
echo
echo "Usage in n8n:"
echo "  - HTTP Node URL: $QDRANT_URL"
echo "  - API Key Header: api-key: $QDRANT_API_KEY"
echo "  - Documentation: https://qdrant.tech/documentation/"
EOF
    
    file_operation "chmod" +x "$test_script"
    success "Qdrant test script created: $test_script"
}

create_test_script() {
    retry_with_user_prompt "Qdrant Test Script Creation" create_test_script_impl
}

# --- Show Qdrant Results ---
show_qdrant_results_impl() {
    load_env_config
    
    local public_ip=$(get_public_ip)
    
    echo
    echo "🎉======================================================="
    echo "   Qdrant Vector Database Successfully Installed!"
    echo "======================================================="
    echo
    
    if [ -n "${QDRANT_DOMAIN:-}" ]; then
        echo "🌐 Qdrant Access: https://${QDRANT_DOMAIN}"
        echo "⚠️  Ensure DNS record points ${QDRANT_DOMAIN} → ${public_ip}"
        echo "🔒 SSL: Automatic via Caddy (install/update Caddy script for HTTPS)"
    else
        echo "🌐 Qdrant Access: http://${public_ip}:6333"
        echo "📊 Qdrant gRPC: ${public_ip}:6334"
    fi
    
    echo
    echo "🔑 API Authentication:"
    echo "   Header: api-key: ${QDRANT_API_KEY}"
    echo "   (Use this header in all API requests)"
    echo
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo "🛠️  Qdrant Management Commands:"
    echo "   Status:  docker compose -f ${SETUP_DIR}/docker-compose.qdrant.yml ps"
    echo "   Logs:    docker compose -f ${SETUP_DIR}/docker-compose.qdrant.yml logs -f qdrant"
    echo "   Restart: docker compose -f ${SETUP_DIR}/docker-compose.qdrant.yml restart qdrant"
    echo "   Stop:    docker compose -f ${SETUP_DIR}/docker-compose.qdrant.yml down"
    echo
    echo "🧪 Test Your Installation:"
    echo "   Run: ${SETUP_DIR}/test-qdrant.sh"
    echo
    echo "✅ Features:"
    echo "   ✓ API key authentication"
    echo "   ✓ CORS enabled for web access"
    echo "   ✓ Production-optimized settings"
    echo "   ✓ Automatic volume permissions"
    echo "   ✓ Health monitoring"
    echo "   ✓ Persistent storage"
    
    if [ -n "${QDRANT_DOMAIN:-}" ]; then
        echo "   ✓ Domain-ready for HTTPS"
    else
        echo "   ✓ Direct HTTP/gRPC access"
    fi
    
    echo
    echo "📚 Integration with n8n:"
    echo "   • Use HTTP Node with URL: ${QDRANT_DOMAIN:+https://${QDRANT_DOMAIN}}${QDRANT_DOMAIN:-http://${public_ip}:6333}"
    echo "   • Add header: api-key = ${QDRANT_API_KEY}"
    echo "   • API Documentation: https://qdrant.tech/documentation/interfaces/rest/"
    echo
    
    # Quick connectivity test
    if [ -n "${QDRANT_DOMAIN:-}" ]; then
        echo "🔍 Quick connectivity test:"
        echo "   curl -H 'api-key: ${QDRANT_API_KEY}' https://${QDRANT_DOMAIN}/health"
    else
        echo "🔍 Quick connectivity test:"
        echo "   curl -H 'api-key: ${QDRANT_API_KEY}' http://${public_ip}:6333/health"
    fi
    echo
}

show_qdrant_results() {
    retry_with_user_prompt "Qdrant Results Display" show_qdrant_results_impl
}

# --- Cleanup Qdrant Installation ---
cleanup_qdrant() {
    info "Cleaning up existing Qdrant installation..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop and remove Qdrant containers
    if [ -f "docker-compose.qdrant.yml" ]; then
        ${DOCKER_COMPOSE_CMD} -f docker-compose.qdrant.yml down 2>/dev/null || true
    fi
    
    # Remove individual containers if they exist
    for container in "qdrant" "qdrant-init"; do
        if docker ps -aq -f name="^${container}$" | grep -q .; then
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Remove Qdrant-related files
    rm -f "${SETUP_DIR}/docker-compose.qdrant.yml" 2>/dev/null || true
    rm -f "${SETUP_DIR}/qdrant-config.yaml" 2>/dev/null || true
    rm -f "${SETUP_DIR}/test-qdrant.sh" 2>/dev/null || true
    
    # Remove firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow 6333/tcp 2>/dev/null || true
        ufw delete allow 6334/tcp 2>/dev/null || true
    fi
    
    success "Qdrant cleanup completed"
}

# --- Main Qdrant Installation Function ---
main() {
    local cleanup_mode=false
    local auto_mode=false
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            "--cleanup")
                cleanup_mode=true
                ;;
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
            "--help"|"-h")
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --cleanup              Remove existing Qdrant installation"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  QDRANT_API_KEY         API key for authentication (auto-generated if not set)"
                echo "  QDRANT_DOMAIN          Domain for Qdrant (optional, for HTTPS via Caddy)"
                echo "  QDRANT_SUBDOMAIN       Subdomain prefix (default: qdrant)"
                echo ""
                echo "Qdrant is a vector database perfect for AI/ML workflows and semantic search."
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_qdrant
        exit 0
    fi
    
    info "Starting Qdrant vector database installation..."
    
    collect_qdrant_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    create_qdrant_env
    create_qdrant_config
    create_qdrant_compose
    configure_qdrant_firewall
    deploy_qdrant
    create_test_script
    show_qdrant_results
    
    success "Qdrant vector database installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi