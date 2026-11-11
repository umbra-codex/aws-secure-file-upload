# scanning

Scans every file uploaded to the Incoming bucket for malware with GuardDuty Malware Protection for S3.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.10.0, < 2.0.0 |
| aws | ~> 6.69 |

## Usage

```hcl
# Owner: Portion C
module "scanning" {
  source = "./modules/scanning"

  project_name         = var.project_name
  incoming_bucket_name = module.storage.incoming_bucket_name
  incoming_bucket_arn  = module.storage.incoming_bucket_arn
  router_lambda_arn    = module.processing.router_lambda_arn
  alert_email          = var.alert_email
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| project_name | Prefix for resource names. | string | yes |
| incoming_bucket_name | Name of the Incoming bucket. | string | yes |
| incoming_bucket_arn | ARN of the Incoming bucket. | string | yes |
| router_lambda_arn | ARN of Lambda 2 (router), the scan-result rule's target. | string | yes |
| alert_email | Email address subscribed to the alerts topic. | string | yes |

## Outputs

| Name | Description |
|------|-------------|
| guardduty_role_arn | ARN of the GuardDuty malware protection plan's IAM role. |
| guardduty_plan_id | ID of the GuardDuty malware protection plan on the Incoming bucket. |
