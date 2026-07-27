#!/bin/bash

# Terraform Demo Script for Cloudflare Demo Platform
# Shows Terraform features: idempotency, drift detection, state management, etc.

set -e

ZONE_NAME=""
ACTION=${1:-help}

show_help() {
    cat << 'EOF'
Terraform Demo Script
=====================

Usage: ./terraform-demo.sh [ACTION] [OPTIONS]

Actions:
  idempotency     Show declarative idempotency (apply twice, 0 changes second time)
  drift-detect    Detect manual changes in dashboard and reconcile
  state-inspect   Show state list, show resource details, output values
  targeted        Deploy only one resource using -target
  plan-file       Save plan to file and apply exact plan
  workspaces      Create staging workspace and switch between them
  refresh-only    Detect drift without making changes
  taint-replace   Force recreation of a single resource
  var-override    Plan with overridden zone_name (requires existing zone)
  graph           Generate visual dependency graph
  all             Run all demos sequentially
  help            Show this help

Examples:
  ./terraform-demo.sh idempotency
  ./terraform-demo.sh drift-detect
  ./terraform-demo.sh all
  ./terraform-demo.sh var-override staging.example.com

EOF
}

check_prereqs() {
    if ! command -v terraform &> /dev/null; then
        echo "Terraform required. Install: https://terraform.io/downloads"
        exit 1
    fi

    if [ ! -f "terraform.tfvars" ]; then
        echo "terraform.tfvars not found. Create from terraform.tfvars.example"
        exit 1
    fi

    ZONE_NAME=$(grep 'zone_name' terraform.tfvars | cut -d'"' -f2)
    echo "Zone: $ZONE_NAME"
    echo ""
}

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

run_cmd() {
    echo "\$ $1"
    eval "$1"
    echo ""
}

demo_idempotency() {
    print_header "DEMO: Idempotency"
    echo "Terraform is declarative. Running apply twice should produce"
    echo "zero changes the second time."
    echo ""
    press_enter

    echo "First apply (creates infrastructure):"
    run_cmd "terraform apply -auto-approve"
    press_enter

    echo "Second apply (should show 0 changes):"
    run_cmd "terraform apply -auto-approve"
    press_enter

    echo "Notice: '0 to add, 0 to change, 0 to destroy' on second run."
    echo "This proves Terraform only acts when actual changes are needed."
}

demo_drift_detect() {
    print_header "DEMO: Drift Detection"
    echo "When someone changes resources in the Cloudflare dashboard,"
    echo "Terraform detects drift on the next plan/apply."
    echo ""
    echo "Steps:"
    echo "  1. Deploy infrastructure"
    echo "  2. YOU: Go to Cloudflare dashboard and manually change something"
    echo "     (e.g., add a DNS record, modify a Worker, change SSL setting)"
    echo "  3. Run terraform plan to detect the drift"
    echo "  4. Run terraform apply to reconcile back to code"
    echo ""
    press_enter

    echo "Deploying baseline infrastructure..."
    run_cmd "terraform apply -auto-approve"
    press_enter

    echo ""
    echo "⚠️  ACTION REQUIRED:"
    echo "   Go to https://dash.cloudflare.com and manually change something"
    echo "   in the $ZONE_NAME zone. Suggestions:"
    echo "   - Add a random DNS record"
    echo "   - Change a zone setting"
    echo "   - Edit a Worker script"
    echo ""
    press_enter

    echo "Detecting drift:"
    run_cmd "terraform plan"
    press_enter

    echo "Reconciling back to desired state:"
    run_cmd "terraform apply -auto-approve"
    press_enter

    echo "Drift resolved. Infrastructure now matches code again."
}

demo_state_inspect() {
    print_header "DEMO: State Inspection"
    echo "Terraform maintains a state file tracking all resources."
    echo "You can inspect it without making changes."
    echo ""
    press_enter

    echo "List all managed resources:"
    run_cmd "terraform state list"
    press_enter

    echo "Show details of a specific resource:"
    run_cmd "terraform state show cloudflare_d1_database.products"
    press_enter

    echo "Show all output values:"
    run_cmd "terraform output"
    press_enter

    echo "Show a specific output:"
    run_cmd "terraform output api_gateway_url"
    press_enter

    echo "Show outputs as JSON (useful for automation):"
    run_cmd "terraform output -json"
}

demo_targeted() {
    print_header "DEMO: Targeted Operations"
    echo "You can apply or destroy specific resources using -target."
    echo "This is useful for testing or incremental changes."
    echo ""
    press_enter

    echo "Plan changes for only the products API worker:"
    run_cmd "terraform plan -target=cloudflare_workers_script.products_api"
    press_enter

    echo "Apply only the products API worker:"
    run_cmd "terraform apply -target=cloudflare_workers_script.products_api -auto-approve"
    press_enter

    echo "Targeted operations let you control blast radius during changes."
}

demo_plan_file() {
    print_header "DEMO: Plan Files & Approval Workflow"
    echo "In production, plans are reviewed before apply."
    echo "Terraform supports saving a plan and applying it exactly."
    echo ""
    press_enter

    echo "Save plan to file:"
    run_cmd "terraform plan -out=tfplan"
    press_enter

    echo "Show contents of saved plan:"
    run_cmd "terraform show tfplan"
    press_enter

    echo "Apply the exact saved plan (no surprises):"
    run_cmd "terraform apply tfplan"
    press_enter

    echo "Clean up plan file:"
    run_cmd "rm -f tfplan"
}

demo_workspaces() {
    print_header "DEMO: Workspace Isolation"
    echo "Workspaces allow multiple environments (dev, staging, prod)"
    echo "with separate state files but the same configuration."
    echo ""
    press_enter

    echo "Current workspace:"
    run_cmd "terraform workspace show"
    press_enter

    echo "Create a staging workspace:"
    run_cmd "terraform workspace new staging || terraform workspace select staging"
    press_enter

    echo "List all workspaces:"
    run_cmd "terraform workspace list"
    press_enter

    echo "Plan for staging (separate state, no actual resources yet):"
    run_cmd "terraform plan"
    press_enter

    echo "Switch back to default workspace:"
    run_cmd "terraform workspace select default"
    press_enter

    echo "Verify we're back on default:"
    run_cmd "terraform workspace show"
}

demo_refresh_only() {
    print_header "DEMO: Refresh-Only (Detect Without Changing)"
    echo "Sometimes you want to update state with current infrastructure"
    echo "without proposing any changes."
    echo ""
    press_enter

    echo "Refresh state to match reality (no changes proposed):"
    run_cmd "terraform apply -refresh-only -auto-approve"
    press_enter

    echo "This updates the state file but does not modify resources."
    echo "Useful after manual changes to understand current state."
}

demo_taint_replace() {
    print_header "DEMO: Taint & Force Replace"
    echo "Sometimes you need to force recreation of a resource."
    echo "Terraform 'taint' marks a resource for replacement."
    echo ""
    press_enter

    echo "Taint the products API worker (mark for replacement):"
    run_cmd "terraform taint cloudflare_workers_script.products_api"
    press_enter

    echo "Plan shows the resource will be replaced:"
    run_cmd "terraform plan -target=cloudflare_workers_script.products_api"
    press_enter

    echo "Apply to replace the resource:"
    run_cmd "terraform apply -target=cloudflare_workers_script.products_api -auto-approve"
    press_enter

    echo "Resource recreated. Untaint it for demo cleanup:"
    run_cmd "terraform untaint cloudflare_workers_script.products_api || true"
}

demo_var_override() {
    print_header "DEMO: Variable Overrides"
    echo "Variables can be set via CLI, environment, or files."
    echo "Command-line overrides take highest precedence."
    echo ""
    press_enter

    local override_zone="${2:-}"
    if [ -z "$override_zone" ]; then
        echo "Usage: ./terraform-demo.sh var-override <existing-zone>"
        echo "Example: ./terraform-demo.sh var-override staging.example.com"
        echo "Provide a zone that exists in your Cloudflare account."
        return
    fi

    echo "Plan with a different zone (dry run, won't apply):"
    run_cmd "terraform plan -var=\"zone_name=$override_zone\""
    press_enter

    echo "Notice: plan uses the overridden zone name."
    echo "Original terraform.tfvars value is unchanged."
}

demo_graph() {
    print_header "DEMO: Resource Dependency Graph"
    echo "Terraform knows the dependency graph between resources."
    echo "You can visualize it."
    echo ""
    press_enter

    if command -v dot &> /dev/null; then
        echo "Generating dependency graph image:"
        run_cmd "terraform graph | dot -Tpng > terraform-graph.png"
        echo "Graph saved to terraform-graph.png"
        run_cmd "ls -la terraform-graph.png"
    else
        echo "Graphviz 'dot' not installed. Showing text graph:"
        run_cmd "terraform graph"
    fi
}

run_all() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          RUNNING ALL TERRAFORM DEMOS SEQUENTIALLY             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This will deploy infrastructure and run through each demo."
    echo "Estimated time: 10-15 minutes"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi

    check_prereqs
    demo_idempotency
    demo_state_inspect
    demo_targeted
    demo_plan_file
    demo_refresh_only
    demo_var_override
    demo_graph
    demo_workspaces

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                   ALL DEMOS COMPLETE                          ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "To clean up: terraform destroy -auto-approve"
}

# Main
case "$ACTION" in
    idempotency)
        check_prereqs
        demo_idempotency
        ;;
    drift-detect)
        check_prereqs
        demo_drift_detect
        ;;
    state-inspect)
        check_prereqs
        demo_state_inspect
        ;;
    targeted)
        check_prereqs
        demo_targeted
        ;;
    plan-file)
        check_prereqs
        demo_plan_file
        ;;
    workspaces)
        check_prereqs
        demo_workspaces
        ;;
    refresh-only)
        check_prereqs
        demo_refresh_only
        ;;
    taint-replace)
        check_prereqs
        demo_taint_replace
        ;;
    var-override)
        check_prereqs
        demo_var_override "$2"
        ;;
    graph)
        check_prereqs
        demo_graph
        ;;
    all)
        run_all
        ;;
    help|--help|-h|*)
        show_help
        ;;
esac
