#!/bin/bash

#################################################################################
# Terraform State Lock Unlock Script
# Purpose: Force unlock Terraform state in S3 backend
# Usage: ./scripts/unlock-terraform-state.sh
# WARNING: Only use this if you're sure no other process is running Terraform
#################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="eu-north-1"
STATE_BUCKET_PREFIX="enterprise-platform-tfstate"
STATE_PATH="prod/terraform.tfstate"

#################################################################################
# Helper Functions
#################################################################################

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

confirm() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$(echo -e ${YELLOW})$prompt (yes/no): $(echo -e ${NC})" response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                print_warning "Please answer 'yes' or 'no'"
                ;;
        esac
    done
}

check_aws_credentials() {
    if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
}

#################################################################################
# State Lock Detection Functions
#################################################################################

find_state_bucket() {
    print_info "Finding S3 state bucket..."
    
    local bucket=$(aws s3 ls --region "$AWS_REGION" 2>/dev/null | \
        grep -oP "$STATE_BUCKET_PREFIX-[0-9]+" | head -1)
    
    if [ -z "$bucket" ]; then
        print_error "State bucket not found"
        echo "Expected bucket pattern: $STATE_BUCKET_PREFIX-*"
        return 1
    fi
    
    print_success "Found state bucket: $bucket"
    echo "$bucket"
}

get_lock_id_from_s3() {
    local bucket="$1"
    local lock_file="${STATE_PATH}.terraform.lock.json"
    
    print_info "Checking for lock file in S3: s3://$bucket/$lock_file"
    
    if aws s3 ls "s3://$bucket/$lock_file" --region "$AWS_REGION" 2>/dev/null; then
        print_info "Lock file found. Retrieving lock information..."
        
        local lock_data=$(aws s3 cp "s3://$bucket/$lock_file" - --region "$AWS_REGION" 2>/dev/null)
        echo "$lock_data" | jq '.' 2>/dev/null || echo "$lock_data"
        return 0
    else
        print_warning "Lock file not found in S3"
        return 1
    fi
}

get_lock_id_from_terraform() {
    print_info "Checking for lock ID in local Terraform files..."
    
    cd terraform
    
    if [ -f ".terraform.lock.hcl" ]; then
        local lock_id=$(grep -oP '(?<="id" = ")[^"]*' .terraform.lock.hcl | head -1)
        if [ -n "$lock_id" ]; then
            print_success "Found lock ID in .terraform.lock.hcl: $lock_id"
            echo "$lock_id"
            cd ..
            return 0
        fi
    fi
    
    # Try to get from terraform state directly
    if [ -f ".terraform/lockfile" ]; then
        local lock_id=$(cat .terraform/lockfile | jq -r '.ID' 2>/dev/null)
        if [ -n "$lock_id" ] && [ "$lock_id" != "null" ]; then
            print_success "Found lock ID in .terraform/lockfile: $lock_id"
            echo "$lock_id"
            cd ..
            return 0
        fi
    fi
    
    cd ..
    print_warning "Could not find lock ID in local files"
    return 1
}

#################################################################################
# State Lock Management Functions
#################################################################################

show_current_locks() {
    local bucket="$1"
    
    print_header "CURRENT TERRAFORM LOCKS IN S3"
    
    print_info "Fetching lock information from: s3://$bucket/${STATE_PATH}.terraform.lock.json"
    echo ""
    
    # Check if lock file exists and show its contents
    if aws s3 ls "s3://$bucket/${STATE_PATH}.terraform.lock.json" --region "$AWS_REGION" 2>/dev/null; then
        print_success "Lock file found"
        echo ""
        
        # Retrieve and display lock file
        local lock_data=$(aws s3 cp "s3://$bucket/${STATE_PATH}.terraform.lock.json" - --region "$AWS_REGION" 2>/dev/null)
        
        if [ -n "$lock_data" ]; then
            echo -e "${CYAN}Lock Details:${NC}"
            echo "$lock_data" | jq '.' 2>/dev/null || echo "$lock_data"
            echo ""
            
            # Parse and display specific lock info
            echo -e "${CYAN}Parsed Lock Info:${NC}"
            echo "$lock_data" | jq -r '
            "  Lock ID:        " + .ID,
            "  Who:            " + .Who,
            "  Operation:      " + .Operation,
            "  Created:        " + .Created,
            "  Path:           " + .Path,
            "  Version:        " + .Version,
            "  Info:           " + .Info
            ' 2>/dev/null || echo "  (Could not parse lock data)"
        else
            print_warning "Lock file is empty"
        fi
    else
        print_success "No active lock on state"
        echo ""
        echo "The Terraform state is currently unlocked and ready for operations."
    fi
}

force_unlock_state() {
    local lock_id="$1"
    
    if [ -z "$lock_id" ]; then
        print_error "No lock ID provided"
        return 1
    fi
    
    print_header "FORCE UNLOCK TERRAFORM STATE"
    
    echo -e "${RED}⚠  WARNING:${NC}"
    echo "  Forcing unlock can lead to state corruption if another process"
    echo "  is still modifying the state!"
    echo ""
    echo "  Lock ID to unlock: ${CYAN}$lock_id${NC}"
    echo ""
    
    print_warning "Make absolutely sure that:"
    echo "  1. No other terraform processes are running"
    echo "  2. No CI/CD pipelines are applying changes"
    echo "  3. No team members are running terraform"
    echo ""
    
    if ! confirm "Are you absolutely certain you want to force unlock?"; then
        print_warning "Operation cancelled"
        return 1
    fi
    
    cd terraform
    
    print_info "Attempting to force unlock state with ID: $lock_id"
    
    if terraform force-unlock "$lock_id"; then
        print_success "State force-unlocked successfully"
        cd ..
        return 0
    else
        print_error "Force unlock failed"
        echo ""
        echo -e "${YELLOW}Possible solutions:${NC}"
        echo "  1. Check AWS credentials and permissions"
        echo "  2. Verify lock ID is correct"
        echo "  3. Try using AWS S3 API to delete the lock file directly:"
        echo "     aws s3 rm 's3://<bucket>/$STATE_PATH.terraform.lock.json' --region $AWS_REGION"
        echo ""
        cd ..
        return 1
    fi
}

delete_lock_file_from_s3() {
    local bucket="$1"
    
    print_header "DELETE LOCK FILE FROM S3 (Advanced)"
    
    print_warning "This directly deletes the lock file from S3"
    echo ""
    
    if ! confirm "Delete lock file from S3?"; then
        print_warning "Operation cancelled"
        return 1
    fi
    
    print_info "Deleting lock file from S3: s3://$bucket/${STATE_PATH}.terraform.lock.json"
    
    if aws s3 rm "s3://$bucket/${STATE_PATH}.terraform.lock.json" --region "$AWS_REGION"; then
        print_success "Lock file deleted from S3"
        return 0
    else
        print_error "Failed to delete lock file from S3"
        return 1
    fi
}

#################################################################################
# Main Script Logic
#################################################################################

main() {
    # Parse command line arguments
    local command="${1:-}"
    
    # Check AWS credentials
    check_aws_credentials
    
    # Find state bucket
    STATE_BUCKET=$(find_state_bucket) || exit 1
    echo ""
    
    # Handle different commands
    case "$command" in
        view|status|info)
            # Just show current locks, don't offer to unlock
            show_current_locks "$STATE_BUCKET"
            echo ""
            print_info "To unlock this state, run: $0 unlock"
            ;;
        
        unlock|force-unlock)
            # Show current locks first
            show_current_locks "$STATE_BUCKET"
            echo ""
            
            # Try to get lock ID from terraform files first
            LOCK_ID=$(get_lock_id_from_terraform 2>/dev/null) || \
            LOCK_ID=$(get_lock_id_from_s3 "$STATE_BUCKET" 2>/dev/null | jq -r '.ID // .ID' 2>/dev/null)
            
            echo ""
            
            if [ -z "$LOCK_ID" ]; then
                print_warning "Could not automatically detect lock ID"
                echo ""
                read -p "$(echo -e ${YELLOW})Enter lock ID manually (or press Enter to skip): $(echo -e ${NC})" LOCK_ID
            fi
            
            if [ -n "$LOCK_ID" ]; then
                echo ""
                print_info "Using lock ID: $LOCK_ID"
                echo ""
                
                # Offer force unlock
                if confirm "Attempt to force unlock this state?"; then
                    echo ""
                    if force_unlock_state "$LOCK_ID"; then
                        echo ""
                        print_success "State should now be unlocked and ready for use"
                        echo ""
                        echo "Next steps:"
                        echo "  1. Verify the state is accessible: cd terraform && terraform state list"
                        echo "  2. If you had a plan file, you may need to recreate it"
                        echo "  3. Retry your terraform operation"
                    else
                        echo ""
                        print_warning "Force unlock via terraform failed. Trying S3 deletion..."
                        echo ""
                        
                        if confirm "Delete lock file directly from S3?"; then
                            echo ""
                            if delete_lock_file_from_s3 "$STATE_BUCKET"; then
                                echo ""
                                print_warning "Lock file deleted. The state might be in an inconsistent state."
                                echo "Run 'cd terraform && terraform refresh' to verify state consistency"
                            fi
                        fi
                    fi
                fi
            else
                print_warning "No lock ID provided. Cannot proceed with unlock"
                echo ""
                echo "To unlock manually:"
                echo "  cd terraform"
                echo "  terraform force-unlock <LOCK_ID>"
                exit 1
            fi
            
            echo ""
            print_info "Unlock process complete"
            ;;
        
        help|--help|-h)
            print_header "TERRAFORM STATE LOCK RESOLVER - USAGE"
            echo ""
            echo "Manage Terraform state locks in AWS S3 backend"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  view, status, info    Show current lock information without unlocking"
            echo "  unlock, force-unlock  Force unlock the Terraform state"
            echo "  help, --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 view                # Check who has the state locked"
            echo "  $0 unlock              # Force unlock the state (prompts for confirmation)"
            echo "  $0 help                # Show this help message"
            echo ""
            ;;
        
        *)
            # Default: show locks and offer unlock option
            if [ -n "$command" ]; then
                print_error "Unknown command: $command"
                echo ""
                echo "Run '$0 help' for usage information"
                exit 1
            fi
            
            show_current_locks "$STATE_BUCKET"
            echo ""
            
            # Try to get lock ID from terraform files first
            LOCK_ID=$(get_lock_id_from_terraform 2>/dev/null) || \
            LOCK_ID=$(get_lock_id_from_s3 "$STATE_BUCKET" 2>/dev/null | jq -r '.ID // .ID' 2>/dev/null)
            
            echo ""
            
            if [ -z "$LOCK_ID" ]; then
                print_warning "Could not automatically detect lock ID"
                echo ""
                read -p "$(echo -e ${YELLOW})Enter lock ID manually (or press Enter to skip): $(echo -e ${NC})" LOCK_ID
            fi
            
            if [ -n "$LOCK_ID" ]; then
                echo ""
                print_info "Using lock ID: $LOCK_ID"
                echo ""
                
                # Offer force unlock
                if confirm "Attempt to force unlock this state?"; then
                    echo ""
                    if force_unlock_state "$LOCK_ID"; then
                        echo ""
                        print_success "State should now be unlocked and ready for use"
                        echo ""
                        echo "Next steps:"
                        echo "  1. Verify the state is accessible: cd terraform && terraform state list"
                        echo "  2. If you had a plan file, you may need to recreate it"
                        echo "  3. Retry your terraform operation"
                    else
                        echo ""
                        print_warning "Force unlock via terraform failed. Trying S3 deletion..."
                        echo ""
                        
                        if confirm "Delete lock file directly from S3?"; then
                            echo ""
                            if delete_lock_file_from_s3 "$STATE_BUCKET"; then
                                echo ""
                                print_warning "Lock file deleted. The state might be in an inconsistent state."
                                echo "Run 'cd terraform && terraform refresh' to verify state consistency"
                            fi
                        fi
                    fi
                fi
            else
                print_warning "No lock ID provided. Cannot proceed with unlock"
                echo ""
                echo "To unlock manually:"
                echo "  cd terraform"
                echo "  terraform force-unlock <LOCK_ID>"
                exit 1
            fi
            
            echo ""
            print_info "Unlock process complete"
            ;;
    esac
}

# Run main function
main "$@"
