import json
import os

import boto3


table = boto3.resource("dynamodb").Table(os.environ["REQUESTS_TABLE"])
cors_headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT",
}


def lambda_handler(event, context):
    ticket_id = (event.get("pathParameters") or {}).get("ticket_id")
    if not ticket_id:
        return {"statusCode": 400, "headers": cors_headers, "body": json.dumps({"message": "ticket_id is required"})}

    result = table.get_item(Key={"ticket_id": ticket_id})
    ticket = result.get("Item")
    if not ticket:
        return {"statusCode": 404, "headers": cors_headers, "body": json.dumps({"message": "Ticket not found"})}

    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    groups = claims.get("cognito:groups", [])
    if isinstance(groups, str):
        try:
            groups = json.loads(groups)
        except json.JSONDecodeError:
            groups = [groups]
    if ticket.get("created_by_sub") != claims.get("sub") and "ServiceAdvisors" not in groups:
        return {"statusCode": 403, "headers": cors_headers, "body": json.dumps({"message": "You cannot access this request"})}

    return {
        "statusCode": 200,
        "headers": cors_headers,
        "body": json.dumps(ticket),
    }