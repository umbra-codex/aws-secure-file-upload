# Owner: Portion D
module "processing" {
  source = "./modules/processing"

  project_name           = var.project_name
  incoming_bucket_name   = module.storage.incoming_bucket_name
  incoming_bucket_arn    = module.storage.incoming_bucket_arn
  approved_bucket_name   = module.storage.approved_bucket_name
  approved_bucket_arn    = module.storage.approved_bucket_arn
  quarantine_bucket_name = module.storage.quarantine_bucket_name
  quarantine_bucket_arn  = module.storage.quarantine_bucket_arn
  table_name             = module.storage.table_name
  table_arn              = module.storage.table_arn
  allowed_types          = var.allowed_types
  max_size_mb            = var.max_size_mb
}
