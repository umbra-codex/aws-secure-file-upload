# Owner: Portion A
#
# storage takes router_role_arn from processing, and processing takes the
# bucket names from storage. That is fine because Terraform tracks dependencies
# per value, not per module. Keep it that way: no storage OUTPUT may be computed
# from router_role_arn, or plan fails with "Cycle: module.storage, module.processing".
module "storage" {
  source = "./modules/storage"

  project_name         = var.project_name
  cors_allowed_origins = var.cors_allowed_origins
  router_role_arn      = module.processing.router_role_arn
}
