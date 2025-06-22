cd path/to/farmOS # the directory where docker-compose.yml is 
located docker compose exec -u www-data www phpunit --verbose 
--debug /opt/drupal/web/profiles/farm
