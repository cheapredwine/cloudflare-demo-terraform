#!/bin/bash

# Cloudflare Demo Platform - Management Script
# Deploy, manage, and clean up the demo platform

set -e

# Parse command line arguments
ACTION=${1:-deploy}
ZONE_NAME=""

show_help() {
    echo "🚀 Cloudflare Demo Platform Management"
    echo "====================================="
    echo ""
    echo "Usage: ./run-demo.sh [ACTION] [OPTIONS]"
    echo ""
    echo "Actions:"
    echo "  deploy      Deploy fresh infrastructure (default)"
    echo "  reset       Reset data but keep infrastructure"
    echo "  destroy     Tear down all infrastructure"
    echo "  fresh       Destroy and redeploy everything"
    echo "  test        Test existing deployment"
    echo "  help        Show this help"
    echo ""
    echo "Options:"
    echo "  --demo      Run demo commands after deployment"
    echo "  --zone NAME Override zone name from terraform.tfvars"
    echo ""
    echo "Examples:"
    echo "  ./run-demo.sh deploy --demo"
    echo "  ./run-demo.sh reset"
    echo "  ./run-demo.sh fresh --zone demo2.example.com"
    echo ""
}

if [ "$ACTION" == "help" ] || [ "$ACTION" == "--help" ] || [ "$ACTION" == "-h" ]; then
    show_help
    exit 0
fi

echo "🚀 Cloudflare Demo Platform - $ACTION"
echo "====================================="

check_prerequisites() {
    if ! command -v terraform &> /dev/null; then
        echo "❌ Terraform is required but not installed."
        echo "Install from: https://www.terraform.io/downloads"
        exit 1
    fi

    if [ ! -f "terraform.tfvars" ] && [ "$ACTION" != "destroy" ]; then
        echo "❌ terraform.tfvars not found"
        echo "Copy terraform.tfvars.example to terraform.tfvars and configure your settings"
        exit 1
    fi
}

get_zone_name() {
    # Check for --zone override
    for arg in "$@"; do
        if [[ $arg == --zone=* ]]; then
            ZONE_NAME="${arg#*=}"
            return
        fi
    done
    
    # Extract from terraform.tfvars
    if [ -f "terraform.tfvars" ]; then
        ZONE_NAME=$(grep 'zone_name' terraform.tfvars | cut -d'"' -f2)
    fi
    
    if [ -z "$ZONE_NAME" ]; then
        echo "❌ zone_name not found. Use --zone=domain.com or set in terraform.tfvars"
        exit 1
    fi
}

check_prerequisites
get_zone_name "$@"

echo "📋 Configuration:"
echo "   Zone: $ZONE_NAME"
echo "   Action: $ACTION"
echo ""

deploy_infrastructure() {
    echo "🏗️  Deploying infrastructure..."
    terraform init
    terraform apply -auto-approve

    if [ $? -ne 0 ]; then
        echo "❌ Terraform deployment failed"
        exit 1
    fi

    echo "✅ Infrastructure deployed successfully!"
    echo ""

    # Wait a moment for DNS propagation
    echo "⏳ Waiting for DNS propagation..."
    sleep 30
    
    test_endpoints
    show_success_message
}

reset_data() {
    echo "🔄 Resetting demo data..."
    
    # Test if infrastructure exists
    if ! test_endpoints_silent; then
        echo "❌ Infrastructure not found. Deploy first with: ./run-demo.sh deploy"
        exit 1
    fi
    
    echo "Clearing database and cache..."
    
    # Reset via admin API
    response=$(curl -s -w "%{http_code}" -u admin:demo123 \
        -X POST "https://admin.$ZONE_NAME/setup" -o /tmp/reset_response.json)
    
    if [ "$response" -eq 200 ]; then
        echo "✅ Database reset"
    else
        echo "⚠️  Database reset may have failed (HTTP $response)"
    fi
    
    # Seed fresh data
    echo "Loading sample data..."
    response=$(curl -s -w "%{http_code}" \
        -X POST "https://api.$ZONE_NAME/products/seed" -o /tmp/seed_response.json)
    
    if [ "$response" -eq 200 ]; then
        echo "✅ Sample data loaded"
    else
        echo "⚠️  Sample data load may have failed (HTTP $response)"
    fi
    
    echo ""
    echo "🎯 Demo environment reset and ready!"
    show_quick_start
}

destroy_infrastructure() {
    echo "🧨 Destroying infrastructure..."
    echo "⚠️  This will delete all data and stop all costs"
    
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    terraform destroy -auto-approve
    
    if [ $? -eq 0 ]; then
        echo "✅ Infrastructure destroyed successfully"
        echo "💰 All costs stopped"
    else
        echo "❌ Destroy failed - check Terraform output"
        exit 1
    fi
}

fresh_deploy() {
    echo "🔄 Fresh deployment (destroy + deploy)"
    destroy_infrastructure
    echo ""
    deploy_infrastructure
}

test_endpoints_silent() {
    API_URL="https://api.$ZONE_NAME"
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$API_URL" 2>/dev/null)
    [ "$response" -eq 200 ]
}

test_endpoints() {
    echo "🧪 Testing endpoints..."

    # Test API Gateway
    echo "Testing API Gateway..."
    API_URL="https://api.$ZONE_NAME"
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$API_URL" 2>/dev/null)
    if [ "$response" -eq 200 ]; then
        echo "✅ API Gateway: $API_URL"
    else
        echo "⚠️  API Gateway: $API_URL (HTTP $response)"
    fi

    # Test Admin Panel
    echo "Testing Admin Panel..."
    ADMIN_URL="https://admin.$ZONE_NAME"
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$ADMIN_URL" 2>/dev/null)
    if [ "$response" -eq 401 ]; then
        echo "✅ Admin Panel: $ADMIN_URL (Auth required)"
    else
        echo "⚠️  Admin Panel: $ADMIN_URL (HTTP $response)"
    fi
}

show_success_message() {

    echo ""
    echo "🎉 Demo Platform Ready!"
    echo "======================="
    echo ""
    echo "📱 Web Interface:"
    echo "   Main Site:    https://$ZONE_NAME"
    echo "   API Gateway:  https://api.$ZONE_NAME"
    echo "   Admin Panel:  https://admin.$ZONE_NAME"
    echo "   File Uploads: https://uploads.$ZONE_NAME"
    echo ""
    echo "🔑 Admin Access:"
    echo "   URL:      https://admin.$ZONE_NAME"
    echo "   Username: admin"
    echo "   Password: demo123"
    echo ""
    show_quick_start
}

show_quick_start() {
    echo "📚 Quick Start:"
    echo "   1. Visit the admin panel and initialize the database"
    echo "   2. Load sample data using the 'Load Sample Data' button"
    echo "   3. Test the API endpoints:"
    echo ""
    echo "   # Get products"
    echo "   curl https://api.$ZONE_NAME/products"
    echo ""
    echo "   # Create order"
    echo "   curl -X POST https://api.$ZONE_NAME/orders \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"customer_id\":\"demo\",\"items\":[{\"product_id\":1,\"quantity\":1,\"unit_price\":24.99}],\"total\":24.99}'"
    echo ""
    echo "   # Upload file"
    echo "   curl -X POST https://api.$ZONE_NAME/upload -F 'file=@image.jpg'"
    echo ""
    echo "🧹 Management:"
    echo "   ./run-demo.sh reset     # Reset data"
    echo "   ./run-demo.sh destroy   # Full cleanup"
    echo ""
}

run_demo_commands() {

    echo "🎬 Running demo commands..."
    
    # Wait a bit more for everything to be ready
    sleep 10
    
    echo "Creating sample product..."
    response=$(curl -s -X POST "https://api.$ZONE_NAME/products" \
        -H "Content-Type: application/json" \
        -d '{"name":"Demo Product","description":"Created by script","price":99.99,"category":"demo","stock":10}')
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq .
    else
        echo "$response"
    fi
    
    echo ""
    echo "Getting all products..."
    response=$(curl -s "https://api.$ZONE_NAME/products")
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq .
    else
        echo "$response"
    fi
    
    echo ""
    echo "Creating sample order..."
    response=$(curl -s -X POST "https://api.$ZONE_NAME/orders" \
        -H "Content-Type: application/json" \
        -d '{"customer_id":"script-demo","items":[{"product_id":1,"quantity":1,"unit_price":99.99}],"total":99.99}')
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq .
    else
        echo "$response"
    fi
    
    echo ""
    echo "🎯 Demo commands completed!"
}

# Main execution logic
case "$ACTION" in
    "deploy")
        deploy_infrastructure
        ;;
    "reset")
        reset_data
        ;;
    "destroy")
        destroy_infrastructure
        ;;
    "fresh")
        fresh_deploy
        ;;
    "test")
        test_endpoints
        ;;
    *)
        echo "❌ Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac

# Check for --demo flag
for arg in "$@"; do
    if [ "$arg" == "--demo" ]; then
        run_demo_commands
        break
    fi
done

echo "✨ Operation complete!"