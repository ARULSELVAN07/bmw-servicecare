import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError


table = boto3.resource("dynamodb").Table(os.environ["REQUESTS_TABLE"])
cors_headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT",
}


def lambda_handler(event, context):
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    groups = claims.get("cognito:groups", [])
    if isinstance(groups, str):
        try:
            groups = json.loads(groups)
        except json.JSONDecodeError:
            groups = [groups]
    if "ServiceAdvisors" not in groups:
        return {"statusCode": 403, "headers": cors_headers, "body": json.dumps({"message": "Advisor access is required"})}

    ticket_id = (event.get("pathParameters") or {}).get("ticket_id")
    if not ticket_id:
        return {"statusCode": 400, "headers": cors_headers, "body": json.dumps({"message": "ticket_id is required"})}

    body = json.loads(event.get("body") or "{}")
    updates = {
        key: body[key]
        for key in ("status", "vehicle", "concern", "advisor_notes")
        if key in body
    }
    if not updates:
        return {"statusCode": 400, "headers": cors_headers, "body": json.dumps({"message": "No supported fields to update"})}

    updates["updated_at"] = datetime.now(timezone.utc).isoformat()
    names = {f"#{key}": key for key in updates}
    values = {f":{key}": value for key, value in updates.items()}
    update_expression = "SET " + ", ".join(f"#{key} = :{key}" for key in updates)

    try:
        result = table.update_item(
            Key={"ticket_id": ticket_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
            ConditionExpression="attribute_exists(ticket_id)",
            ReturnValues="ALL_NEW",
        )
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return {"statusCode": 404, "headers": cors_headers, "body": json.dumps({"message": "Ticket not found"})}
        raise

    return {
        "statusCode": 200,
        "headers": cors_headers,
        "body": json.dumps(result["Attributes"]),
    }