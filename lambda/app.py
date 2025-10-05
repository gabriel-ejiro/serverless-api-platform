import json, os, time, boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])
events = boto3.client("events")

def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }

def handler(event, context):
    route = event.get("rawPath", "/")
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if route.startswith("/public"):
        return _resp(200, {"ok": True, "service": "serverless-api-platform"})

    if route.startswith("/items") and method == "POST":
        body = json.loads(event.get("body") or "{}")
        item = {
            "id": body.get("id") or str(int(time.time())),
            "value": body.get("value", ""),
        }
        table.put_item(Item=item)
        events.put_events(Entries=[{
            "Source": "serverless.api",
            "DetailType": "item.created",
            "Detail": json.dumps(item),
            "EventBusName": "default"
        }])
        return _resp(201, item)

    if route.startswith("/items") and method == "GET":
        qs = event.get("queryStringParameters") or {}
        id_ = qs.get("id")
        if not id_:
            return _resp(400, {"error": "missing id"})
        res = table.get_item(Key={"id": id_})
        return _resp(200, res.get("Item"))

    return _resp(404, {"error": "not found"})
