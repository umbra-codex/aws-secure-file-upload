# Owner: Portion A
module "status" {
  source = "./modules/status"

  project_name      = var.project_name
  table_name        = module.storage.table_name
  table_arn         = module.storage.table_arn
  api_id            = module.upload_api.api_id
  api_execution_arn = module.upload_api.api_execution_arn
}
