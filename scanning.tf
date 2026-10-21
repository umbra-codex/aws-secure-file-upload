# Owner: Portion C
module "scanning" {
  source = "./modules/scanning"

  project_name         = var.project_name
  incoming_bucket_name = module.storage.incoming_bucket_name
  incoming_bucket_arn  = module.storage.incoming_bucket_arn
  router_lambda_arn    = module.processing.router_lambda_arn
  alert_email          = var.alert_email
}
