"""
Product Assistant Lambda
- Calls Bedrock Claude directly with tool use
- Stores conversation history in DynamoDB (memory)
- Langfuse tracing for observability (traces, scores, evaluation)
- /chat     → chat with the assistant
- /evaluate → open-source NLP evaluation + Langfuse scoring
"""
import json
import os
import re
import time
import uuid
import math
import boto3
import urllib.request
import urllib.error
from collections import Counter

# ── Clients ───────────────────────────────────────────────────
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION_NAME", "eu-west-1"))
dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION_NAME", "eu-west-1"))
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])

MODEL_ID       = os.environ.get("MODEL_ID", "eu.anthropic.claude-sonnet-4-5-20250929-v1:0")
SESSION_TTL    = 3600  # 1 hour

# ── Langfuse config ───────────────────────────────────────────
LANGFUSE_PUBLIC_KEY  = os.environ.get("LANGFUSE_PUBLIC_KEY", "")
LANGFUSE_SECRET_KEY  = os.environ.get("LANGFUSE_SECRET_KEY", "")
LANGFUSE_HOST        = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com")
LANGFUSE_ENABLED     = bool(LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY)

# ── Langfuse HTTP client (no SDK needed - pure stdlib) ────────
def _lf_post(path: str, payload: dict):
    """Send a POST to Langfuse API."""
    if not LANGFUSE_ENABLED:
        return
    try:
        import base64
        creds = base64.b64encode(
            f"{LANGFUSE_PUBLIC_KEY}:{LANGFUSE_SECRET_KEY}".encode()
        ).decode()
        data = json.dumps(payload).encode()
        url  = f"{LANGFUSE_HOST.rstrip('/')}/api/public/{path}"
        req  = urllib.request.Request(
            url, data=data,
            headers={
                "Authorization": f"Basic {creds}",
                "Content-Type":  "application/json",
            },
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"Langfuse HTTP error {e.code}: {e.read().decode()}")
    except Exception as e:
        print(f"Langfuse error: {type(e).__name__}: {e}")

def _lf_otel(resource_spans: list):
    """Send traces via OpenTelemetry endpoint (Langfuse v4 / current API)."""
    if not LANGFUSE_ENABLED:
        return
    try:
        import base64
        creds = base64.b64encode(
            f"{LANGFUSE_PUBLIC_KEY}:{LANGFUSE_SECRET_KEY}".encode()
        ).decode()
        payload = json.dumps({"resourceSpans": resource_spans}).encode()
        url = f"{LANGFUSE_HOST.rstrip('/')}/api/public/otel/v1/traces"
        req = urllib.request.Request(
            url, data=payload,
            headers={
                "Authorization": f"Basic {creds}",
                "Content-Type":  "application/json",
            },
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        print(f"Langfuse OTel error {e.code}: {e.read().decode()}")
    except Exception as e:
        print(f"Langfuse OTel error: {type(e).__name__}: {e}")

def _otel_span_id() -> str:
    return uuid.uuid4().hex[:16]

def _otel_trace_id_hex(trace_id: str) -> str:
    """Convert UUID trace_id to 32-char hex for OTel."""
    return trace_id.replace("-", "").ljust(32, "0")[:32]

def _now_ns() -> int:
    return int(time.time() * 1e9)

def lf_trace(trace_id: str, session_id: str, name: str,
             user_input: str, output: str,
             metadata: dict = None, tags: list = None):
    """Send a trace via OTel to Langfuse."""
    tid  = _otel_trace_id_hex(trace_id)
    sid  = _otel_span_id()
    now  = _now_ns()
    attrs = [
        {"key": "langfuse.session.id",  "value": {"stringValue": session_id}},
        {"key": "langfuse.observation.input",  "value": {"stringValue": str(user_input)}},
        {"key": "langfuse.observation.output", "value": {"stringValue": str(output)}},
        {"key": "gen_ai.system", "value": {"stringValue": "aws_bedrock"}},
    ]
    if tags:
        attrs.append({"key": "langfuse.tags", "value": {"stringValue": ",".join(tags)}})
    for k, v in (metadata or {}).items():
        attrs.append({"key": k, "value": {"stringValue": str(v)}})

    _lf_otel([{
        "resource": {"attributes": [
            {"key": "service.name", "value": {"stringValue": "product-assistant"}}
        ]},
        "scopeSpans": [{"spans": [{
            "traceId": tid,
            "spanId":  sid,
            "name":    name,
            "kind":    1,
            "startTimeUnixNano": str(now - 1000000),
            "endTimeUnixNano":   str(now),
            "attributes": attrs,
            "status": {"code": 1}
        }]}]
    }])

def lf_generation(trace_id: str, name: str, model: str,
                  prompt: str, completion: str,
                  input_tokens: int = 0, output_tokens: int = 0,
                  latency_ms: int = 0):
    """Send a generation span via OTel to Langfuse."""
    tid  = _otel_trace_id_hex(trace_id)
    sid  = _otel_span_id()
    now  = _now_ns()
    dur  = latency_ms * 1_000_000

    _lf_otel([{
        "resource": {"attributes": [
            {"key": "service.name", "value": {"stringValue": "product-assistant"}}
        ]},
        "scopeSpans": [{"spans": [{
            "traceId": tid,
            "spanId":  sid,
            "name":    name,
            "kind":    3,
            "startTimeUnixNano": str(now - dur),
            "endTimeUnixNano":   str(now),
            "attributes": [
                {"key": "gen_ai.system",           "value": {"stringValue": "aws_bedrock"}},
                {"key": "gen_ai.request.model",    "value": {"stringValue": model}},
                {"key": "gen_ai.usage.input_tokens",  "value": {"intValue": input_tokens}},
                {"key": "gen_ai.usage.output_tokens", "value": {"intValue": output_tokens}},
                {"key": "langfuse.observation.input",  "value": {"stringValue": str(prompt)[:500]}},
                {"key": "langfuse.observation.output", "value": {"stringValue": str(completion)[:500]}},
            ],
            "status": {"code": 1}
        }]}]
    }])

def lf_score(trace_id: str, name: str, value: float, comment: str = ""):
    """Send scores via the scores API (still supported)."""
    _lf_post("scores", {
        "traceId": trace_id,
        "name":    name,
        "value":   value,
        "comment": comment,
        "dataType": "NUMERIC"
    })

def lf_trace(trace_id: str, session_id: str, name: str,
             user_input: str, output: str,
             metadata: dict = None, tags: list = None):
    """Create a Langfuse trace via batch ingestion."""
    _lf_post("ingestion", {
        "batch": [{
            "id":        str(uuid.uuid4()),
            "type":      "trace-create",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "body": {
                "id":        trace_id,
                "name":      name,
                "sessionId": session_id,
                "input":     user_input,
                "output":    output,
                "metadata":  metadata or {},
                "tags":      tags or ["product-assistant"],
            }
        }]
    })

def lf_generation(trace_id: str, name: str, model: str,
                  prompt: str, completion: str,
                  input_tokens: int = 0, output_tokens: int = 0,
                  latency_ms: int = 0):
    """Create a Langfuse generation span via batch ingestion."""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    _lf_post("ingestion", {
        "batch": [{
            "id":        str(uuid.uuid4()),
            "type":      "generation-create",
            "timestamp": now,
            "body": {
                "traceId":    trace_id,
                "name":       name,
                "model":      model,
                "input":      prompt,
                "output":     completion,
                "startTime":  now,
                "endTime":    now,
                "usage": {
                    "input":  input_tokens,
                    "output": output_tokens
                }
            }
        }]
    })

def lf_score(trace_id: str, name: str, value: float, comment: str = ""):
    """Attach a numeric score to a trace via batch ingestion."""
    _lf_post("ingestion", {
        "batch": [{
            "id":        str(uuid.uuid4()),
            "type":      "score-create",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "body": {
                "traceId":  trace_id,
                "name":     name,
                "value":    value,
                "comment":  comment,
                "dataType": "NUMERIC"
            }
        }]
    })

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
def run_agent(messages: list, trace_id: str = None, session_id: str = None) -> str:
    MAX_ITERATIONS = 8
    iteration = 0

    for _ in range(MAX_ITERATIONS):
        iteration += 1
        t_start = time.time()

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
        latency_ms  = int((time.time() - t_start) * 1000)
        stop_reason = body.get("stop_reason")
        content     = body.get("content", [])
        usage       = body.get("usage", {})

        # Append assistant turn
        messages.append({"role": "assistant", "content": content})

        if stop_reason == "end_turn":
            for block in content:
                if block.get("type") == "text":
                    reply = block["text"]
                    # Send generation to Langfuse
                    if trace_id:
                        lf_generation(
                            trace_id   = trace_id,
                            name       = f"chat-turn-{iteration}",
                            model      = MODEL_ID,
                            prompt     = messages[-2]["content"] if len(messages) >= 2 else "",
                            completion = reply,
                            input_tokens  = usage.get("input_tokens", 0),
                            output_tokens = usage.get("output_tokens", 0),
                            latency_ms    = latency_ms
                        )
                    return reply
            return "Done."

        if stop_reason == "tool_use":
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

# ── DeepEval-inspired Open Source Evaluation ─────────────────
# Implements standard NLP metrics locally (no external API needed):
#   - Answer Relevancy  (keyword overlap + semantic scoring)
#   - Faithfulness      (factual consistency check)
#   - ROUGE-L           (recall-oriented overlap)
#   - Completeness      (coverage of expected info)
# Falls back to Bedrock only for the semantic judge score

import re
import math
from collections import Counter

def _tokenize(text: str) -> list:
    """Simple whitespace + punctuation tokenizer."""
    return re.findall(r'\b\w+\b', text.lower())

def _ngrams(tokens: list, n: int) -> Counter:
    return Counter(tuple(tokens[i:i+n]) for i in range(len(tokens)-n+1))

def _rouge_l(reference: str, hypothesis: str) -> float:
    """ROUGE-L F1 score using LCS length."""
    ref  = _tokenize(reference)
    hyp  = _tokenize(hypothesis)
    if not ref or not hyp:
        return 0.0
    # LCS via DP
    m, n = len(ref), len(hyp)
    dp = [[0]*(n+1) for _ in range(m+1)]
    for i in range(1, m+1):
        for j in range(1, n+1):
            dp[i][j] = dp[i-1][j-1]+1 if ref[i-1]==hyp[j-1] else max(dp[i-1][j], dp[i][j-1])
    lcs = dp[m][n]
    p = lcs / n if n else 0
    r = lcs / m if m else 0
    return round(2*p*r/(p+r), 3) if (p+r) else 0.0

def _rouge_1_f1(reference: str, hypothesis: str) -> float:
    """ROUGE-1 F1 (unigram overlap)."""
    ref_tok = _tokenize(reference)
    hyp_tok = _tokenize(hypothesis)
    if not ref_tok or not hyp_tok:
        return 0.0
    ref_c = Counter(ref_tok)
    hyp_c = Counter(hyp_tok)
    overlap = sum((ref_c & hyp_c).values())
    p = overlap / len(hyp_tok)
    r = overlap / len(ref_tok)
    return round(2*p*r/(p+r), 3) if (p+r) else 0.0

def _answer_relevancy(question: str, answer: str) -> float:
    """
    Keyword-based relevancy: how many question keywords appear in the answer.
    Score 0-10.
    """
    stopwords = {'a','an','the','is','are','was','were','be','been','being',
                 'have','has','had','do','does','did','will','would','could',
                 'should','may','might','shall','can','i','you','he','she',
                 'it','we','they','what','which','who','whom','this','that',
                 'these','those','am','your','my','our','their','in','on',
                 'at','to','for','of','with','by','from','about','me','how'}
    q_tokens = [t for t in _tokenize(question) if t not in stopwords]
    a_tokens  = set(_tokenize(answer))
    if not q_tokens:
        return 5.0
    hits = sum(1 for t in q_tokens if t in a_tokens)
    score = hits / len(q_tokens)
    return round(score * 10, 1)

def _faithfulness_check(answer: str) -> float:
    """
    Checks if the answer contains factual product data from our catalog.
    Penalizes hallucinated product names/prices.
    Score 0-10.
    """
    answer_lower = answer.lower()
    known_products = [p["name"].lower() for p in PRODUCTS]
    known_prices   = [str(p["price"]) for p in PRODUCTS]

    # Extract any prices mentioned in the answer
    mentioned_prices = re.findall(r'\$?(\d+\.?\d*)', answer)
    
    price_score = 1.0
    for mp in mentioned_prices:
        try:
            val = float(mp)
            if val > 1:  # ignore small numbers like quantities
                if not any(abs(val - float(kp)) < 0.01 for kp in known_prices):
                    price_score *= 0.7  # penalize each hallucinated price
        except ValueError:
            pass

    # Check product names
    name_score = 1.0
    # Extract capitalized words that might be product names
    potential_names = re.findall(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b', answer)
    for pn in potential_names:
        pn_lower = pn.lower()
        if len(pn_lower) > 4 and pn_lower not in known_products:
            # Could be hallucinated - mild penalty
            name_score *= 0.95

    return round(min(price_score * name_score, 1.0) * 10, 1)

def _completeness_score(question: str, answer: str) -> float:
    """
    Checks if e-commerce expected fields are present based on question type.
    Score 0-10.
    """
    answer_lower = answer.lower()
    score = 5.0  # base

    # If asking about price - is price mentioned?
    if any(w in question.lower() for w in ['price', 'cost', 'how much', 'cheap', 'expensive', 'under', '$']):
        if re.search(r'\$\d+|\d+\.\d{2}', answer):
            score += 2.0
        else:
            score -= 1.0

    # If asking about availability/stock
    if any(w in question.lower() for w in ['stock', 'available', 'availability', 'have']):
        if any(w in answer_lower for w in ['in stock', 'out of stock', 'available', 'units', 'quantity']):
            score += 2.0
        else:
            score -= 1.0

    # If asking for recommendations/suggestions
    if any(w in question.lower() for w in ['recommend', 'suggest', 'similar', 'like']):
        if any(p["name"].lower() in answer_lower for p in PRODUCTS):
            score += 2.0
        else:
            score -= 1.0

    # General: answer should be non-trivial
    if len(_tokenize(answer)) < 10:
        score -= 2.0

    return round(max(0.0, min(score, 10.0)), 1)

def evaluate_response(question: str, answer: str) -> dict:
    """
    Open-source evaluation using local NLP metrics (ROUGE, keyword overlap).
    No external API calls - fully deterministic and reproducible.
    """
    # Compute local metrics
    relevancy    = _answer_relevancy(question, answer)
    rouge_l      = round(_rouge_l(question, answer) * 10, 1)
    rouge_1      = round(_rouge_1_f1(question, answer) * 10, 1)
    faithfulness = _faithfulness_check(answer)
    completeness = _completeness_score(question, answer)

    # Weighted overall score
    overall = round(
        relevancy    * 0.30 +
        faithfulness * 0.25 +
        completeness * 0.25 +
        rouge_l      * 0.10 +
        rouge_1      * 0.10,
        1
    )

    # Generate feedback based on scores
    issues = []
    if relevancy < 5:
        issues.append("answer may not address the question directly")
    if faithfulness < 7:
        issues.append("possible factual inaccuracies detected")
    if completeness < 5:
        issues.append("answer may be missing key details (price/availability)")
    if rouge_l < 3:
        issues.append("low lexical overlap with question")

    feedback = "Good response." if not issues else "Issues: " + "; ".join(issues) + "."

    return {
        "answer_relevancy": relevancy,
        "faithfulness":     faithfulness,
        "completeness":     completeness,
        "rouge_l":          rouge_l,
        "rouge_1":          rouge_1,
        "overall":          overall,
        "feedback":         feedback,
        "method":           "open-source (ROUGE + keyword + faithfulness)",
        "issues":           issues
    }

# ── Lambda handler ────────────────────────────────────────────
def lambda_handler(event, context):
    path = event.get("rawPath", event.get("path", "/chat"))
    body = json.loads(event.get("body") or "{}")

    session_id = body.get("session_id", "default")
    message    = body.get("message", "")

    if not message:
        return _response(400, {"error": "message is required"})

    # /evaluate — open-source NLP evaluation + Langfuse scores
    if path == "/evaluate":
        answer = body.get("answer", "")
        if not answer:
            return _response(400, {"error": "answer is required for evaluation"})
        try:
            scores   = evaluate_response(message, answer)
            trace_id = body.get("trace_id") or str(uuid.uuid4())

            # Send all scores to Langfuse scores API
            if LANGFUSE_ENABLED:
                for metric, value in scores.items():
                    if isinstance(value, (int, float)):
                        lf_score(
                            trace_id = trace_id,
                            name     = metric,
                            value    = float(value),
                            comment  = scores.get("feedback", "")
                        )

            return _response(200, {"evaluation": scores, "trace_id": trace_id})
        except Exception as e:
            return _response(500, {"error": str(e)})

    # /chat — main conversation
    trace_id = str(uuid.uuid4())
    history  = load_history(session_id)
    history.append({"role": "user", "content": message})

    try:
        t_start = time.time()
        reply   = run_agent(list(history), trace_id=trace_id, session_id=session_id)
        latency = int((time.time() - t_start) * 1000)

        # Create top-level trace in Langfuse
        lf_trace(
            trace_id   = trace_id,
            session_id = session_id,
            name       = "product-assistant-chat",
            user_input = message,
            output     = reply,
            metadata   = {"latency_ms": latency, "model": MODEL_ID},
            tags       = ["chat", "product-assistant"]
        )

        # Save to DynamoDB memory
        save_message(session_id, {"role": "user",      "content": message})
        save_message(session_id, {"role": "assistant", "content": reply})

        return _response(200, {
            "session_id": session_id,
            "reply":      reply,
            "trace_id":   trace_id   # return so frontend can link evaluation to this trace
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
