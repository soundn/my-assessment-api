# One complete environment: network, database, Cloud Run service and
# monitoring. staging and prod instantiate this with different variables.

module "network" {
  source = "../network"

  name            = var.name
  region          = var.region
  subnet_cidr     = var.subnet_cidr
  psa_range_start = var.psa_range_start
}

module "database" {
  source = "../database"

  name                = var.name
  region              = var.region
  network_id          = module.network.network_id
  psa_connection_id   = module.network.psa_connection_id
  tier                = var.db_tier
  availability_type   = var.db_availability_type
  deletion_protection = var.db_deletion_protection

  depends_on = [module.network]
}

module "service" {
  source = "../service"

  name                  = var.name
  region                = var.region
  environment           = var.environment
  image                 = var.image
  network_id            = module.network.network_id
  subnet_id             = module.network.subnet_id
  db_host               = module.database.private_ip
  db_name               = module.database.database_name
  db_user               = module.database.database_user
  db_password_secret_id = module.database.password_secret_id
  deployer_email        = var.deployer_email
  min_instances         = var.min_instances
  max_instances         = var.max_instances
}

module "observability" {
  source = "../observability"

  name               = var.name
  project_id         = var.project_id
  notification_email = var.notification_email
  service_url        = module.service.url
  service_name       = module.service.service_name
  sql_instance_name  = module.database.instance_name
}
