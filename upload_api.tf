# Owner: Portion B
module "upload_api" {
  source = "./modules/upload_api"

  project_name               = var.project_name
  incoming_bucket_name       = module.storage.incoming_bucket_name
  incoming_bucket_arn        = module.storage.incoming_bucket_arn
  table_name                 = module.storage.table_name
  table_arn                  = module.storage.table_arn
  allowed_types              = var.allowed_types
  max_size_mb                = var.max_size_mb
  router_function_name       = module.processing.router_function_name
  dlq_name                   = module.scanning.dlq_name
  router_failures_queue_name = module.processing.router_failures_queue_name
}
