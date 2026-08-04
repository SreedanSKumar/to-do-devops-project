import json


def lambda_handler(event, context):
    """Triggered on every s3:ObjectCreated:* event in the ops-data bucket.

    For this capstone it just logs a structured event to CloudWatch Logs
    (visible in Grafana via the CloudWatch/Loki pipeline, or directly in the
    AWS Console). Swap the body of the loop for a real notification -
    e.g. ses_client.send_email(...) - when you want actual emails.
    """
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        size = record["s3"]["object"].get("size")
        event_name = record.get("eventName")

        print(json.dumps({
            "message": "ops-board S3 event received",
            "event_name": event_name,
            "bucket": bucket,
            "key": key,
            "size_bytes": size,
        }))

    return {"statusCode": 200, "body": json.dumps({"processed": len(event.get("Records", []))})}
