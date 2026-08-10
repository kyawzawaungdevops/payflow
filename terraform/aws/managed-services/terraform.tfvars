# Copy from terraform.tfvars.example or edit in place. Never commit real passwords.

db_password       = "REPLACE_WITH_YOUR_PASSWORD"
rabbitmq_password = "REPLACE_WITH_YOUR_PASSWORD"

# Optional: extra SG IDs for RDS/Redis/MQ ingress. Leave empty; cluster + node SGs are resolved by tag in data.tf.
# additional_rds_security_group_ids = []
deletion_protection = false
