"""
Product Assistant Lambda
- Calls Bedrock Claude directly with tool use
- Stores conversation history in DynamoDB (memory)
- /chat  → chat with the assistant
- /evaluate → LLM-as-a-Judge evaluation of last response
"""
import json
import os
import time
import boto3
from decimal import Decimal

# ── Clients ───────────────────────────────────────────────────
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION_NAME", "eu-west-1"))
dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION_NAME", "eu-west-1"))
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])

MODEL_ID       = os.environ.get("MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")
JUDGE_MODEL_ID = os.environ.get("JUDGE_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
SESSION_TTL    = 3600  # 1 hour

# ── Load products once at cold start ─────────────────────────
with open("products.json") as f:
    PRODUCTS = json.load(f)["products"]

# ── Tool definitions ──────────────────────────────────────────
TOOLS = [
    {
        "name": "search_products",
        "description": "Search products by keyword, category, or price range.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query":     {"type": "string",  "description": "Keyword or category to search"},
                "category":  {"type": "string",  "description": "Filter by category (optional)"},
                "max_price": {"type": "number",  "description": "Max price in USD (optional)"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_product_details",
        "description": "Get full details of a product by ID or name.",
        "input_schema": {
            "type": "object",
            "properties": {
                "product_id": {"type": "string", "description": "Product ID (e.g. watch-001) or name (e.g. Watch)"}
            },
            "required": ["product_id"]
        }
    },
    {
        "name": "check_availability",
        "description": "Check stock and availability of a product.",
        "input_schema": {
            "type": "object",
            "properties": {
                "product_id": {"type": "string", "description": "Product ID or name to check"}
            },
            "required": ["product_id"]
        }
    },
    {
        "name": "get_recommendations",
        "description": "Recommend products similar to a given product or category.",
        "input_schema": {
            "type": "object",
            "properties": {
                "based_on": {"type": "string", "description": "Product ID, name, or category to base recommendations on"}
            },
            "required": ["based_on"]
        }
    }
]

SYSTEM_PROMPT = """You are a friendly and helpful e-commerce product assistant for an online boutique.

You have access to 4 tools to help customers:
- search_products: find products by keyword/category/price
- get_product_details: get full info on a specific product  
- check_availability: check if a product is in stock
- get_recommendations: suggest similar products

Always use tools to get accurate product info. Be concise but informative.
Include prices and availability in your answers.
If a product is out of stock, suggest alternatives using get_recommendations."""

# ── Tool execution ────────────────────────────────────────────
def execute_tool(name: str, inputs: dict) -> str:
    if name == "search_products":
        return _search_products(**inputs)
    elif name == "get_product_details":
        return _get_product_details(inputs["product_id"])
    elif name == "check_availability":
        return _check_availability(inputs["product_id"])
    elif name == "get_recommendations":
        return _get_recommendations(inputs["based_on"])
    return json.dumps({"error": f"Unknown tool: {name}"})

def _search_products(query: str, category: str = None, max_price: float = None) -> str:
    results = []
    q = query.lower()
    for p in PRODUCTS:
        if category and p["category"].lower() != category.lower():
            continue
        if max_price and p["price"] > max_price:
            continue
        text = f"{p['name']} {p['description']} {' '.join(p.get('tags', []))}".lower()
        if q in text or not q:
            results.append({
                "id": p["id"], "name": p["name"], "price": p["price"],
                "category": p["category"], "inStock": p["inStock"],
                "description": p["description"]
            })
    return json.dumps({"count": len(results), "products": results})

def _get_product_details(product_id: str) -> str:
    pid = product_id.lower()
    for p in PRODUCTS:
        if p["id"].lower() == pid or p["name"].lower() == pid:
            return json.dumps(p)
    return json.dumps({"error": f"Product not found: {product_id}"})

def _check_availability(product_id: str) -> str:
    pid = product_id.lower()
    for p in PRODUCTS:
        if p["id"].lower() == pid or p["name"].lower() == pid:
            return json.dumps({
                "name": p["name"], "inStock": p["inStock"],
                "quantity": p["quantity"], "price": p["price"]
            })
    return json.dumps({"error": f"Product not found: {product_id}"})

def _get_recommendations(based_on: str) -> str:
    base = based_on.lower()
    base_product = next(
        (p for p in PRODUCTS if p["id"].lower() == base or p["name"].lower() == base), None
    )
    base_category = base_product["category"] if base_product else based_on

    recs = []
    for p in PRODUCTS:
        if base_product and p["id"] == base_product["id"]:
            continue
        if p["category"] == base_category:
            recs.append({"id": p["id"], "name": p["name"], "price": p["price"], "reason": f"Same category: {base_category}"})
        elif base_product and abs(p["price"] - base_product["price"]) <= 20:
            recs.append({"id": p["id"], "name": p["name"], "price": p["price"], "reason": "Similar price range"})
    return json.dumps({"recommendations": recs[:5]})

# ── DynamoDB memory ───────────────────────────────────────────
def load_history(session_id: str) -> list:
    try:
        resp = table.query(
            KeyConditionExpression="session_id = :sid",
            ExpressionAttributeValues={":sid": session_id},
            ScanIndexForward=True
        )
        messages = []
        for item in resp.get("Items", []):
            messages.append(json.loads(item["message"]))
        return messages
    except Exception:
        return []

def save_message(session_id: str, message: dict):
    ts = int(time.time() * 1000)
    table.put_item(Item={
        "session_id": session_id,
        "timestamp": ts,
        "message": json.dumps(message),
        "expires_at": int(time.time()) + SESSION_TTL
    })

# ── Agentic loop (tool use) ───────────────────────────────────
def run_agent(messages: list) -> str:
    MAX_ITERATIONS = 8

    for _ in range(MAX_ITERATIONS):
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 1024,
                "system": SYSTEM_PROMPT,
                "messages": messages,
                "tools": TOOLS,
                "temperature": 0.3
            })
        )
        body = json.loads(response["body"].read())
        stop_reason = body.get("stop_reason")
        content     = body.get("content", [])

        # Append assistant turn
        messages.append({"role": "assistant", "content": content})

        if stop_reason == "end_turn":
            # Extract text response
            for block in content:
                if block.get("type") == "text":
                    return block["text"]
            return "Done."

        if stop_reason == "tool_use":
            # Execute all requested tools
            tool_results = []
            for block in content:
                if block.get("type") == "tool_use":
                    result = execute_tool(block["name"], block.get("input", {}))
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block["id"],
                        "content": result
                    })
            messages.append({"role": "user", "content": tool_results})
        else:
            break

    return "I'm sorry, I couldn't complete your request."

# ── LLM-as-a-Judge ────────────────────────────────────────────
def evaluate_response(question: str, answer: str) -> dict:
    prompt = f"""Evaluate this e-commerce assistant response.

Question: {question}
Response: {answer}

Score each criterion from 0-10 and return ONLY valid JSON:
{{
  "accuracy": <int>,
  "helpfulness": <int>,
  "completeness": <int>,
  "relevance": <int>,
  "tone": <int>,
  "overall": <float>,
  "feedback": "<one sentence>"
}}"""

    resp = bedrock.invoke_model(
        modelId=JUDGE_MODEL_ID,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 300,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.1
        })
    )
    text = json.loads(resp["body"].read())["content"][0]["text"]
    start = text.find("{")
    end   = text.rfind("}") + 1
    return json.loads(text[start:end])

# ── Lambda handler ────────────────────────────────────────────
def lambda_handler(event, context):
    path = event.get("rawPath", event.get("path", "/chat"))
    body = json.loads(event.get("body") or "{}")

    session_id = body.get("session_id", "default")
    message    = body.get("message", "")

    if not message:
        return _response(400, {"error": "message is required"})

    # /evaluate — judge the last Q&A pair
    if path == "/evaluate":
        answer = body.get("answer", "")
        if not answer:
            return _response(400, {"error": "answer is required for evaluation"})
        try:
            scores = evaluate_response(message, answer)
            return _response(200, {"evaluation": scores})
        except Exception as e:
            return _response(500, {"error": str(e)})

    # /chat — main conversation
    history = load_history(session_id)
    history.append({"role": "user", "content": message})

    try:
        reply = run_agent(list(history))  # copy so we can save selectively

        # Save only the user message and final text reply
        save_message(session_id, {"role": "user",      "content": message})
        save_message(session_id, {"role": "assistant", "content": reply})

        return _response(200, {
            "session_id": session_id,
            "reply": reply
        })
    except Exception as e:
        return _response(500, {"error": str(e)})

def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body)
    }
