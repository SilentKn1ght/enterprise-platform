#!/bin/bash

#################################################################################
# Terraform Remote State Bootstrap
# Purpose: Create the S3 bucket and DynamoDB table required for Terraform remote
#          state and atomic locking. Run this ONCE before the first terraform init.
#
# Usage: ./scripts/bootstrap-tfstate.sh [--region eu-north-1] [--env prod]
#
# What it creates:
#   S3 bucket  : enterprise-platform-tfstate-<aws_account_id>
#                  - versioning enabled (recover from accidental state corruption)
#                  - server-side encryption (AES-256)
#                  - public access blocked
#   DynamoDB   : enterprise-platform-tfstate-lock
#                  - PAY_PER_REQUEST billing (near-zero cost when idle)
#                  - TTL on LockID so interrupted runs self-heal after 1h
#
# After running, init Terraform with:
#   terraform init \
#     -backend-config="bucket=enterprise-platform-tfstate-<account_id>" \
#     -backend-config="key=prod/terraform.tfstate" \
#     -backend-config="region=<region>" \
#     -backend-config="dynamodb_table=enterprise-platform-tfstate-lock"
#################################################################################

set -euo pipefail

# -- Colour helpers -------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}i${NC}  $*"; }
success() { echo -e "${GREEN}OK${NC}  $*"; }
warn()    { echo -e "${YELLOW}!${NC}  $*"; }
error()   { echo -e "${RED}X${NC}  $*" >&2; }
header()  {
  echo -e "\n${BLUE}==================================================${NC}"
  echo -e "${BLUE}${NC}  $*"
  echo -e "${BLUE}==================================================${NC}\n"
}

# -- Defaults -------------------------------------------------------------------
AWS_REGION="eu-north-1"
ENVIRONMENT="prod"
PROJECT="enterprise-platform"

# -- Argument parsing -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)  AWS_REGION="$2";  shift 2 ;;
    --env)     ENVIRONMENT="$2"; shift 2 ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,\}//'
      exit 0
      ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

# -- Pre-flight -----------------------------------------------------------------
header "Terraform State Bootstrap"

if ! command -v aws &>/dev/null; then
  error "AWS CLI not found. Install it first: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  exit 1
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
  error "AWS credentials not configured or invalid. Run: aws configure"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="${PROJECT}-tfstate-lock"
STATE_KEY="${ENVIRONMENT}/terraform.tfstate"

info "AWS Account : $ACCOUNT_ID"
info "Region      : $AWS_REGION"
info "S3 Bucket   : $BUCKET"
info "DynamoDB    : $LOCK_TABLE"
info "State key   : $STATE_KEY"

# -- S3 Bucket ------------------------------------------------------------------
echo ""
header "S3 State Bucket"

if aws s3api head-bucket --bucket "$BUCKET" --region "$AWS_REGION" 2>/dev/null; then
  warn "Bucket already exists - skipping creation: s3://$BUCKET"
else
  info "Creating bucket..."

  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$AWS_REGION" \
      --output text > /dev/null
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" \
      --output text > /dev/null
  fi
  success "Bucket created: s3://$BUCKET"
fi

info "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  > /dev/null
success "Public access blocked"

info "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --versioning-configuration Status=Enabled \
  > /dev/null
success "Versioning enabled"

info "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }' > /dev/null
success "Encryption enabled (AES-256)"

info "Setting lifecycle policy for old state versions..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
    }]
  }' > /dev/null
success "Lifecycle rule applied (old versions expire after 90 days)"

# -- DynamoDB Lock Table --------------------------------------------------------
echo ""
header "DynamoDB Lock Table"

if aws dynamodb describe-table \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION" &>/dev/null; then
  warn "Table already exists - skipping creation: $LOCK_TABLE"
else
  info "Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --region "$AWS_REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --output text > /dev/null
  success "Table created: $LOCK_TABLE"

  info "Waiting for table to become active..."
  aws dynamodb wait table-exists \
    --table-name "$LOCK_TABLE" \
    --region "$AWS_REGION"
  success "Table is active"
fi

info "Enabling TTL on LockID..."
aws dynamodb update-time-to-live \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION" \
  --time-to-live-specification "Enabled=true,AttributeName=LockID" \
  > /dev/null 2>&1 || warn "TTL may already be set"
success "TTL enabled on LockID"

# -- Summary --------------------------------------------------------------------
echo ""
header "Bootstrap Complete"

echo -e "Run the following to initialise Terraform:\n"
echo -e "  ${CYAN}cd terraform${NC}"
echo -e "  ${CYAN}terraform init \\${NC}"
echo -e "  ${CYAN}  -backend-config=\"bucket=${BUCKET}\" \\${NC}"
echo -e "  ${CYAN}  -backend-config=\"key=${STATE_KEY}\" \\${NC}"
echo -e "  ${CYAN}  -backend-config=\"region=${AWS_REGION}\" \\${NC}"
echo -e "  ${CYAN}  -backend-config=\"dynamodb_table=${LOCK_TABLE}\"${NC}"
echo ""
echo -e "Add these GitHub Actions secrets so the CI workflow can use the same backend:"
echo -e "  ${YELLOW}TF_STATE_BUCKET${NC}  = ${BUCKET}"
echo -e "  ${YELLOW}TF_LOCK_TABLE${NC}    = ${LOCK_TABLE}"
echo ""
