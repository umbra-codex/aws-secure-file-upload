import os
import json
import uuid
import time
import base64
import logging
from datetime import datetime, timezone

import boto3


# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================

TABLE_NAME = os.environ["TABLE_NAME"]
BUCKET_NAME = os.environ["BUCKET_NAME"]

ALLOWED_TYPES = os.environ["ALLOWED_TYPES"].split(",")

MAX_SIZE_MB = int(os.environ["MAX_SIZE_MB"])


# ==========================================
# AWS CLIENTS
# ==========================================

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

s3 = boto3.client("s3")


# ==========================================
# LOGGER
# ==========================================

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ==========================================
# RESPONSE HELPER
# ==========================================

def response(status_code, body):

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }


# ==========================================
# MAIN LAMBDA HANDLER
# ==========================================

def handler(event, context):

    # --------------------------------------
    # STEP 1: READ REQUEST BODY
    # --------------------------------------

    try:

        body = event.get("body") or ""

        if event.get("isBase64Encoded"):

            body = base64.b64decode(body)

        data = json.loads(body)

        if not isinstance(data, dict):

            logger.warning("request body must be a JSON object")

            return response(
                400,
                {"error": "request body must be a JSON object"}
            )

    except (ValueError, TypeError, base64.binascii.Error):

        logger.warning("invalid JSON request")

        return response(
            400,
            {"error": "invalid JSON request"}
        )

    # --------------------------------------
    # STEP 2: EXTRACT REQUEST FIELDS
    # --------------------------------------

    filename = data.get("filename")
    content_type = data.get("content_type")
    size = data.get("size")

    # --------------------------------------
    # STEP 3: VALIDATE FIELD TYPES
    # --------------------------------------

    if not isinstance(filename, str):

        logger.warning("invalid filename")

        return response(
            400,
            {"error": "filename must be a string"}
        )

    if not isinstance(content_type, str):

        logger.warning("invalid content_type")

        return response(
            400,
            {"error": "content_type must be a string"}
        )

    if type(size) is not int:

        logger.warning("invalid size")

        return response(
            400,
            {"error": "size must be a whole number"}
        )

    # --------------------------------------
    # STEP 4: VALIDATE CONTENT TYPE
    # --------------------------------------

    if content_type not in ALLOWED_TYPES:

        logger.warning("content_type is not allowed")

        return response(
            400,
            {"error": "content_type is not allowed"}
        )

    # --------------------------------------
    # STEP 5: VALIDATE FILE SIZE
    # --------------------------------------

    max_size_bytes = MAX_SIZE_MB * 1024 * 1024

    if size < 1 or size > max_size_bytes:

        logger.warning("file size is not allowed")

        return response(
            400,
            {"error": "file size is not allowed"}
        )

    # --------------------------------------
    # STEP 6: SANITIZE FILENAME
    # --------------------------------------

    cleaned_filename = "".join(
        char
        for char in filename
        if ord(char) >= 32 and ord(char) != 127
    )

    cleaned_filename = cleaned_filename.replace("/", "")
    cleaned_filename = cleaned_filename.replace("\\", "")

    while ".." in cleaned_filename:

        cleaned_filename = cleaned_filename.replace("..", "")

    cleaned_filename = cleaned_filename[:100]

    if not cleaned_filename:

        logger.warning("filename is empty after cleaning")

        return response(
            400,
            {"error": "filename is invalid"}
        )

    # --------------------------------------
    # STEP 7: GENERATE UPLOAD ID
    # --------------------------------------

    upload_id = str(uuid.uuid4())

    # --------------------------------------
    # STEP 8: GENERATE TIMESTAMPS
    # --------------------------------------

    created_at = datetime.now(timezone.utc).isoformat()

    expires_at = int(time.time()) + 900 + 3600

    # --------------------------------------
    # STEP 9: SAVE UPLOAD IN DYNAMODB
    # --------------------------------------

    table.put_item(
        Item={
            "upload_id": upload_id,
            "filename": cleaned_filename,
            "declared_type": content_type,
            "declared_size": size,
            "status": "PENDING",
            "created_at": created_at,
            "expires_at": expires_at
        }
    )

    # --------------------------------------
    # STEP 10: GENERATE S3 OBJECT KEY
    # --------------------------------------

    object_key = f"uploads/{upload_id}/{cleaned_filename}"

    # --------------------------------------
    # STEP 11: GENERATE PRESIGNED POST
    # --------------------------------------

    presigned_post = s3.generate_presigned_post(
        Bucket=BUCKET_NAME,
        Key=object_key,
        ExpiresIn=900
    )

    # --------------------------------------
    # STEP 12: STRUCTURED LOGGING
    # --------------------------------------

    logger.info(
        "upload url issued",
        extra={"upload_id": upload_id}
    )

    # --------------------------------------
    # STEP 13: RETURN SUCCESS RESPONSE
    # --------------------------------------

    return response(
        200,
        {
            "upload_id": upload_id,
            "url": presigned_post["url"],
            "fields": presigned_post["fields"],
            "expires_in": 900
        }
    )