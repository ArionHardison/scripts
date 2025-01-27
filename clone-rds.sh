#!/bin/bash

# AWS RDS Clone Script
# Requirements: AWS CLI v2 installed and configured with appropriate permissions
# Usage: ./clone-rds.sh -s source-db -t target-db [-r region] [-c instance-class]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-west-2"
DB_INSTANCE_CLASS=""
SKIP_FINAL_SNAPSHOT=true

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -s, --source         Source DB identifier (required)"
    echo "  -t, --target         Target DB identifier (required)"
    echo "  -r, --region         AWS region (default: us-west-2)"
    echo "  -c, --class          DB instance class (optional, will use source if not specified)"
    echo "  -h, --help           Show this help message"
}

# Check AWS CLI installation and version
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        echo "Please install AWS CLI v2 from: https://aws.amazon.com/cli/"
        exit 1
    fi

    # Check AWS CLI version
    CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
    if [ "$CLI_VERSION" -lt "2" ]; then
        echo -e "${YELLOW}Warning: AWS CLI version 1 detected. Consider upgrading to version 2${NC}"
    fi
}

# Check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS credentials not configured${NC}"
        echo "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--source)
            SOURCE_DB="$2"
            shift; shift
            ;;
        -t|--target)
            TARGET_DB="$2"
            shift; shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift; shift
            ;;
        -c|--class)
            DB_INSTANCE_CLASS="$2"
            shift; shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$SOURCE_DB" ] || [ -z "$TARGET_DB" ]; then
    echo -e "${RED}Error: Source and target DB identifiers are required${NC}"
    show_help
    exit 1
fi

# Main execution
echo -e "${YELLOW}Starting RDS clone process...${NC}"
echo "Source DB: $SOURCE_DB"
echo "Target DB: $TARGET_DB"
echo "Region: $AWS_REGION"

# Check prerequisites
check_aws_cli
check_aws_credentials

# Get source DB information
echo -e "${YELLOW}Checking source database...${NC}"
SOURCE_DB_JSON=$(aws rds describe-db-instances \
    --db-instance-identifier "$SOURCE_DB" \
    --region "$AWS_REGION" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Source database $SOURCE_DB not found${NC}"
    exit 1
fi

# Use source DB class if not specified
if [ -z "$DB_INSTANCE_CLASS" ]; then
    DB_INSTANCE_CLASS=$(echo "$SOURCE_DB_JSON" | jq -r '.DBInstances[0].DBInstanceClass')
    echo -e "${YELLOW}Using source DB instance class: $DB_INSTANCE_CLASS${NC}"
fi

# Check if target DB already exists
if aws rds describe-db-instances \
    --db-instance-identifier "$TARGET_DB" \
    --region "$AWS_REGION" &>/dev/null; then
    echo -e "${RED}Error: Target database $TARGET_DB already exists${NC}"
    exit 1
fi

# Start the clone operation
echo -e "${YELLOW}Creating clone...${NC}"
aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier "$SOURCE_DB" \
    --target-db-instance-identifier "$TARGET_DB" \
    --restore-time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --db-instance-class "$DB_INSTANCE_CLASS" \
    --region "$AWS_REGION" \
    --no-publicly-accessible \
    --copy-tags-to-snapshot

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to initiate clone operation${NC}"
    exit 1
fi

# Wait for the database to be available
echo -e "${YELLOW}Waiting for clone to be available (this may take several minutes)...${NC}"
aws rds wait db-instance-available \
    --db-instance-identifier "$TARGET_DB" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed while waiting for database to become available${NC}"
    exit 1
fi

# Get the endpoint of the new database
ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$TARGET_DB" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text \
    --region "$AWS_REGION")

echo -e "${GREEN}Clone completed successfully!${NC}"
echo "New database endpoint: $ENDPOINT"

# Save clone details to a log file
echo "Clone details:" > "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"
echo "Timestamp: $(date)" >> "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"
echo "Source DB: $SOURCE_DB" >> "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"
echo "Target DB: $TARGET_DB" >> "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"
echo "Endpoint: $ENDPOINT" >> "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"
echo "Instance Class: $DB_INSTANCE_CLASS" >> "rds_clone_${TARGET_DB}_$(date +%Y%m%d_%H%M%S).log"