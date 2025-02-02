#!/bin/bash

# Navigate to the root of the repository (assumes script is inside the `website` folder)
cd ../../..

# Check if on the main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "You must be on the 'main' branch to deploy."
    exit 1
fi

# Build a fresh commit with only the content of the website folder and push it to gh-pages branch
git subtree split --prefix documents/documentation/website -b pages-deploy

# Force push the new subtree commit to the gh-pages branch
git push origin pages-deploy:pages --force

# Delete the temporary gh-pages-deploy branch created locally
git branch -D pages-deploy

# Optional: Return success message
if [ $? -eq 0 ]; then
    echo "Deployment successful! All content on pages branch has been overridden."
else
    echo "Deployment failed!"
fi
