#!/bin/sh

# Xcode Cloud Post-Clone Script
# This script runs after the repository is cloned
# It determines which environment to use based on the branch

echo "=== CabinetScan CI Post-Clone Script ==="
echo "Branch: $CI_BRANCH"
echo "Tag: $CI_TAG"
echo "Workflow: $CI_WORKFLOW"

# Determine environment based on branch
if [ "$CI_BRANCH" = "main" ]; then
    echo "Building for PRODUCTION environment"
    export BUILD_ENV="production"
elif [ "$CI_BRANCH" = "develop" ]; then
    echo "Building for QA environment"
    export BUILD_ENV="qa"
else
    echo "Building for QA environment (feature branch)"
    export BUILD_ENV="qa"
fi

echo "Build Environment: $BUILD_ENV"
echo "=== Post-Clone Complete ==="
