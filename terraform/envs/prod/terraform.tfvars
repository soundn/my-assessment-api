# Non-secret environment configuration. See staging/terraform.tfvars for the
# secrets-handling note.
#
# Timebox trade-off, documented in the README: in a real production
# environment db_tier would be a dedicated-core machine (e.g. db-custom-2-8192)
# with db_availability_type = "REGIONAL" for automatic cross-zone failover.
# The smallest tier is used here to favour engineering quality over
# infrastructure spend, per the assessment constraints.

image              = "africa-south1-docker.pkg.dev/cashonrails-assess/cashonrails/api:bootstrap"
deployer_email     = "github-deployer@cashonrails-assess.iam.gserviceaccount.com"
notification_email = "soundnwankwo@gmail.com"

db_tier       = "db-f1-micro"
min_instances = 1
max_instances = 10
