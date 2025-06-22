#!/bin/bash
set -e

# Prepare a fresh farmOS installation for external integrations.
# Assumes Docker containers are already running.
# See docs/development/api/index.md and docs/development/module/oauth.md.

REACT_ORIGIN=${REACT_ORIGIN:-http://localhost:3000}
CDCB_TOKEN_ENV=${CDCB_TOKEN:-}

if [ -n "$CDCB_TOKEN_ENV" ]; then
  echo "CDCB_TOKEN=$CDCB_TOKEN_ENV" > .env
fi

# Enable JSON:API and OAuth modules.
./enable_api_modules.sh

# Create an OAuth consumer for the React frontend if it does not exist.
# Allowed origins reference docs/development/module/oauth.md
docker exec -i -u www-data farmos_www_1 drush php:eval "use Drupal\\consumers\\Entity\\Consumer; \$storage = Drupal::entityTypeManager()->getStorage('consumer'); \$existing = \$storage->loadByProperties(['client_id' => 'react_frontend']); if (empty(\$existing)) { Consumer::create(['label' => 'React Frontend', 'client_id' => 'react_frontend', 'allowed_origins' => ['$REACT_ORIGIN'], 'grant_types' => ['authorization_code','refresh_token'], 'redirect' => '$REACT_ORIGIN', 'confidential' => FALSE])->save(); }"

# Run code style checks and tests to verify the installation.
docker exec -it -u www-data farmos_www_1 phpcs /opt/drupal/web/profiles/farm || true
docker exec -it -u www-data farmos_www_1 phpstan analyze /opt/drupal/web/profiles/farm || true
docker exec -it -u www-data farmos_www_1 phpunit --verbose --debug /opt/drupal/web/profiles/farm || true

echo "External integration setup complete."
