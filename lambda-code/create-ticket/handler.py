import json
import os
import uuid
from datetime import datetime, timezone

import boto3


dynamodb = boto3.resource("dynamodb")
events = boto3.client("events")
table = dynamodb.Table(os.environ["REQUESTS_TABLE"])


def lambda_handler(event, context):
    body = json.loads(event.get("body") or "{}")
    ticket_id = str(uuid.uuid4())
    ticket = {
        "ticket_id": ticket_id,
        "status": "OPEN",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by_sub": event.get("requestContext", {}).get("authorizer", {}).get("claims", {}).get("sub"),
        "customer_name": body.get("customer_name", ""),
        "email": body.get("email", ""),
        "vehicle": body.get("vehicle", ""),
        "concern": body.get("concern", ""),
    }
    table.put_item(Item=ticket)
    events.put_events(
        Entries=[
            {
                "EventBusName": os.environ["EVENTS_BUS"],
                "Source": "bmw.servicecare",
                "DetailType": "ServiceRequestCreated",
                "Detail": json.dumps(ticket),
            }
        ]
    )
    return {
        "statusCode": 201,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT",
        },
        "body": json.dumps(ticket),
    }