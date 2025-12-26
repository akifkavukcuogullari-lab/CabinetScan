#!/bin/bash

# CabinetScan Deployment Script
# Usage: ./scripts/deploy.sh [qa|prod|all]

set -e

# Project References
PROD_PROJECT_REF="lhldqenpllbfxjkburzr"
QA_PROJECT_REF="wnyrnpeabhxdqvcpofmb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENV=${1:-"all"}

echo -e "${YELLOW}=== CabinetScan Deployment ===${NC}"
echo "Environment: $ENV"
echo ""

deploy_to_env() {
    local env_name=$1
    local project_ref=$2

    echo -e "${GREEN}Deploying to $env_name...${NC}"

    # Check if project ref is set
    if [ "$project_ref" = "YOUR_QA_PROJECT_REF" ]; then
        echo -e "${RED}Error: QA project ref not configured. Update QA_PROJECT_REF in this script.${NC}"
        return 1
    fi

    echo "  - Pushing database migrations..."
    supabase db push --project-ref "$project_ref"

    echo "  - Deploying Edge Functions..."
    supabase functions deploy --project-ref "$project_ref"

    echo -e "${GREEN}✓ $env_name deployment complete${NC}"
    echo ""
}

case $ENV in
    "qa")
        deploy_to_env "QA" "$QA_PROJECT_REF"
        ;;
    "prod")
        deploy_to_env "Production" "$PROD_PROJECT_REF"
        ;;
    "all")
        deploy_to_env "QA" "$QA_PROJECT_REF"
        deploy_to_env "Production" "$PROD_PROJECT_REF"
        ;;
    *)
        echo -e "${RED}Usage: ./scripts/deploy.sh [qa|prod|all]${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}=== Deployment Complete ===${NC}"
