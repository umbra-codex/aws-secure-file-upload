# bucket

A private, encrypted S3 bucket with optional versioning and CORS.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.10.0 |
| aws | ~> 6.69 |

## Usage

```hcl
module "incoming" {
  source            = "./bucket"
  bucket_name       = "my-project-123456789012-incoming"
  enable_versioning = true
  tags              = { Name = "my-project-123456789012-incoming", Role = "incoming", ManagedBy = "terraform" }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| bucket_name | string | | yes | Full, globally unique bucket name. |
| enable_versioning | bool | false | no | Turn on object versioning. |
| cors_allowed_origins | list(string) | [] | no | Browser origins allowed to POST. |
| tags | map(string) | {} | no | Tags: at least Name, Role, ManagedBy. |
| expiration_days | number | null | no | Days until objects expire. |

## Outputs

| Name | Description |
|---|---|
| bucket_id | ID of the bucket. |
| bucket_name | Name of the bucket. |
| bucket_arn | ARN of the bucket. |
| tags | Tags on the bucket. |
| versioning_enabled | Whether versioning is on. |
| cors_enabled | Whether CORS is configured. |
| expiration_days | Days until objects expire. |
