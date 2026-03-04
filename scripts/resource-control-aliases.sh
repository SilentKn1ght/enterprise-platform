#!/bin/bash
# Resource Control - Quick Reference & Aliases
# Add these to your ~/.bashrc or ~/.zshrc for convenient access

# Go to project
alias ep='cd /home/silentkn1ght/projects/enterprise-platform'

# Quick resource control commands
alias rc='./scripts/resource-control.sh'              # Run interactive menu
alias rc-start='./scripts/resource-control.sh start'  # Start all
alias rc-stop='./scripts/resource-control.sh stop'    # Stop all  
alias rc-status='./scripts/resource-control.sh status' # Check status
alias rc-cost='./scripts/resource-control.sh cost'    # View savings
alias rc-help='./scripts/resource-control.sh help'    # Show help

# Individual control
alias rc-ecs-start='./scripts/resource-control.sh start-ecs'
alias rc-ecs-stop='./scripts/resource-control.sh stop-ecs'
alias rc-rds-start='./scripts/resource-control.sh start-rds'
alias rc-rds-stop='./scripts/resource-control.sh stop-rds'

# Monitoring
alias rc-watch='watch -n 5 "./scripts/resource-control.sh status"'

# Documentation
alias rc-doc='cat RESOURCE-CONTROL-QUICKSTART.md'
alias rc-guide='cat docs/RESOURCE-CONTROL-GUIDE.md'

# Usage examples:
# 
# cd to project:
#   ep
#
# Check status:
#   rc-status
#
# Start everything:
#   rc-start
#
# Stop everything:
#   rc-stop
#
# Open interactive menu:
#   rc
#
# Monitor in real-time:
#   rc-watch
#
# View cost savings:
#   rc-cost
#
# View documentation:
#   rc-doc
#

echo "Resource Control aliases loaded!"
echo "Quick starting points:"
echo "  rc                # Interactive menu"
echo "  rc-start         # Start all resources"
echo "  rc-stop          # Stop all resources"
echo "  rc-status        # Check resource status"
echo "  rc-cost          # View cost savings"
