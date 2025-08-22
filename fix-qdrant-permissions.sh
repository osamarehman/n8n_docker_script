#!/bin/bash

# ==============================================================================
# Qdrant Permission Fix Script
# Fixes the "Permission denied (os error 13)" issue for Qdrant containers
# running as user 1000:1000 with Docker volumes owned by root
# ==============================================================================

set -euo pipefail

# --- Color Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# --- Main Fix Function ---
fix_qdrant_permissions() {
    info "🔧 Qdrant Permission Fix Script"
    echo
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed or not in PATH"
    fi
    
    # Check if qdrant_data volume exists
    if ! docker volume ls --format "table {{.Name}}" | grep -q "^qdrant_data$"; then
        error "qdrant_data volume not found. Make sure your n8n stack is deployed first."
    fi
    
    info "Found qdrant_data volume"
    
    # Check if Qdrant container is running and stop it temporarily
    local qdrant_was_running=false
    if docker ps --format "table {{.Names}}" | grep -q "^qdrant$"; then
        qdrant_was_running=true
        info "Stopping Qdrant container temporarily..."
        docker stop qdrant >/dev/null 2>&1 || true
    fi
    
    # Fix volume permissions using Option 2 approach
    info "Fixing volume ownership to user 1000:1000..."
    echo
    
    # Create a temporary container to fix volume ownership
    info "Running permission fix container..."
    docker run --rm \
        -v qdrant_data:/qdrant/storage \
        alpine sh -c "
            echo 'Current permissions:'
            ls -la /qdrant/storage
            echo
            echo 'Fixing ownership to 1000:1000...'
            chown -R 1000:1000 /qdrant/storage
            echo 'New permissions:'
            ls -la /qdrant/storage
            echo
            echo 'Permissions fixed successfully!'
        "
    
    # Restart Qdrant if it was running
    if [ "$qdrant_was_running" = true ]; then
        info "Restarting Qdrant container..."
        docker start qdrant >/dev/null 2>&1 || true
        
        # Wait a moment for container to start
        sleep 5
        
        # Check if container is running
        if docker ps --format "table {{.Names}}" | grep -q "^qdrant$"; then
            success "Qdrant container restarted successfully"
        else
            warning "Qdrant container may need manual restart. Check with: docker ps -a"
        fi
    fi
    
    echo
    success "✅ Qdrant permission fix completed!"
    echo
    info "📋 What was fixed:"
    echo "   • Changed qdrant_data volume ownership from root:root to 1000:1000"
    echo "   • This allows Qdrant container (running as user 1000:1000) to write to storage"
    echo "   • Resolves 'Permission denied (os error 13)' errors"
    echo
    info "🔍 To verify the fix:"
    echo "   • Check Qdrant logs: docker logs qdrant"
    echo "   • Check container status: docker ps"
    echo "   • Test Qdrant API: curl http://localhost:6333/readiness"
    echo
}

# --- Alternative Manual Fix Instructions ---
show_manual_instructions() {
    echo
    info "📖 Manual Fix Instructions (Alternative)"
    echo
    echo "If this script doesn't work, you can manually fix the permissions:"
    echo
    echo "1. Stop Qdrant container:"
    echo "   docker stop qdrant"
    echo
    echo "2. Fix volume permissions:"
    echo "   docker run --rm -v qdrant_data:/qdrant/storage alpine chown -R 1000:1000 /qdrant/storage"
    echo
    echo "3. Start Qdrant container:"
    echo "   docker start qdrant"
    echo
    echo "4. Verify fix:"
    echo "   docker logs qdrant"
    echo
}

# --- Main Script ---
main() {
    echo "🔧 Qdrant Permission Fix Script"
    echo "================================"
    echo
    echo "This script fixes the Qdrant permission issue where the container"
    echo "cannot write to its storage volume due to ownership mismatch."
    echo
    echo "Issue: Qdrant runs as user 1000:1000 but volume is owned by root"
    echo "Solution: Change volume ownership to 1000:1000 (Option 2)"
    echo
    
    # Confirm before proceeding
    if [ -t 0 ]; then
        echo -n "Proceed with the fix? [Y/n]: "
        read -r confirm
        if [[ "${confirm,,}" =~ ^(n|no)$ ]]; then
            info "Fix cancelled by user"
            show_manual_instructions
            exit 0
        fi
    else
        info "Running in non-interactive mode, proceeding with fix..."
    fi
    
    echo
    fix_qdrant_permissions
    show_manual_instructions
}

# Run main function
main "$@"
