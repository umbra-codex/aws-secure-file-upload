# upload_api

The front door: the HTTP API and Lambda 1, which checks a request, records the upload as `PENDING`, and signs the presigned POST.


## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.10.0, < 2.0.0 |
| aws | ~> 6.69 |
| archive | ~> 2.8 |

## Usage

```hcl
module "upload_api" {
  source                     = "./modules/upload_api"
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
```


## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| project_name | string | — | yes | Prefix for resource names. |
| incoming_bucket_name | string | — | yes | Incoming bucket name. |
| incoming_bucket_arn | string | — | yes | Incoming bucket ARN. |
| table_name | string | — | yes | Uploads table name. |
| table_arn | string | — | yes | Uploads table ARN. |
| allowed_types | list(string) | — | yes | Accepted MIME types. |
| max_size_mb | number | — | yes | Largest upload, in MB. |
| router_function_name | string | — | yes | Lambda 2's name. |
| dlq_name | string | — | yes | EventBridge target DLQ name. |
| router_failures_queue_name | string | — | yes | Lambda 2 failure queue name. |


## Outputs

| Name | Description |
|---|---|
| api_url | API base URL. |
| api_id | API ID. |
| api_execution_arn | API execution ARN. |
| upload_role_arn | Lambda 1 role ARN. |
| upload_function_name | Lambda 1 name. |