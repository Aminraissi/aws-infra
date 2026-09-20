#!/usr/bin/env python3
"""
Test Bedrock Agent and evaluate responses with LLM-as-a-Judge
"""
import boto3
import json
import sys
import time
from datetime import datetime

# Initialize clients
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name='eu-west-1')
bedrock_runtime = boto3.client('bedrock-runtime', region_name='eu-west-1')

# Test questions for the agent
TEST_QUESTIONS = [
    "Show me all watches available",
    "What products do you have under $20?",
    "Is the hairdryer in stock?",
    "I need something for my kitchen around $10",
    "Can you recommend products similar to the sunglasses?",
    "Do you have any clothing items?",
    "What's the price of the bamboo glass jar?",
    "Suggest me a gift for under $25",
]

# Evaluation criteria for LLM-as-a-Judge
JUDGE_PROMPT_TEMPLATE = """You are evaluating the quality of an AI assistant's response for an e-commerce product assistant.

**User Question:** {question}

**Assistant Response:** {response}

**Evaluation Criteria:**
1. **Accuracy** (0-10): Does the response contain correct information about products?
2. **Helpfulness** (0-10): Does it answer the user's question effectively?
3. **Completeness** (0-10): Does it provide enough detail (price, availability, features)?
4. **Relevance** (0-10): Are the suggested products relevant to the query?
5. **Tone** (0-10): Is the response polite, professional, and friendly?

**Output Format (JSON only):**
{{
  "accuracy": <score>,
  "helpfulness": <score>,
  "completeness": <score>,
  "relevance": <score>,
  "tone": <score>,
  "overall_score": <average of all scores>,
  "feedback": "<brief explanation of scores>",
  "issues": ["<list any problems found>"]
}}

Respond with ONLY the JSON, no other text.
"""

def invoke_agent(agent_id: str, agent_alias_id: str, question: str, session_id: str) -> dict:
    """Invoke Bedrock Agent with a question"""
    print(f"\n🤖 Asking: {question}")
    
    try:
        response = bedrock_agent_runtime.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias_id,
            sessionId=session_id,
            inputText=question
        )
        
        # Parse streaming response
        full_response = ""
        for event in response['completion']:
            if 'chunk' in event:
                chunk = event['chunk']
                if 'bytes' in chunk:
                    full_response += chunk['bytes'].decode('utf-8')
        
        print(f"✅ Response: {full_response[:200]}..." if len(full_response) > 200 else f"✅ Response: {full_response}")
        
        return {
            'success': True,
            'question': question,
            'response': full_response,
            'timestamp': datetime.now().isoformat()
        }
    
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return {
            'success': False,
            'question': question,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }

def evaluate_response(question: str, response: str, judge_model: str = "anthropic.claude-3-haiku-20240307-v1:0") -> dict:
    """Evaluate agent response using LLM-as-a-Judge"""
    print(f"⚖️  Evaluating response...")
    
    prompt = JUDGE_PROMPT_TEMPLATE.format(
        question=question,
        response=response
    )
    
    try:
        invoke_response = bedrock_runtime.invoke_model(
            modelId=judge_model,
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 1000,
                "messages": [
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                "temperature": 0.1
            })
        )
        
        response_body = json.loads(invoke_response['body'].read())
        judge_output = response_body['content'][0]['text']
        
        # Extract JSON from response
        json_start = judge_output.find('{')
        json_end = judge_output.rfind('}') + 1
        evaluation = json.loads(judge_output[json_start:json_end])
        
        print(f"📊 Overall Score: {evaluation['overall_score']}/10")
        
        return evaluation
    
    except Exception as e:
        print(f"⚠️  Evaluation failed: {str(e)}")
        return {
            'accuracy': 0,
            'helpfulness': 0,
            'completeness': 0,
            'relevance': 0,
            'tone': 0,
            'overall_score': 0,
            'feedback': f'Evaluation error: {str(e)}',
            'issues': ['Evaluation failed']
        }

def main():
    if len(sys.argv) < 3:
        print("Usage: python test_agent.py <agent_id> <agent_alias_id> [session_id]")
        print("\nExample:")
        print("  python test_agent.py ABCD1234 EFGH5678")
        sys.exit(1)
    
    agent_id = sys.argv[1]
    agent_alias_id = sys.argv[2]
    session_id = sys.argv[3] if len(sys.argv) > 3 else f"test-{int(time.time())}"
    
    print(f"\n{'='*60}")
    print(f"Bedrock Agent Test & Evaluation")
    print(f"{'='*60}")
    print(f"Agent ID: {agent_id}")
    print(f"Alias ID: {agent_alias_id}")
    print(f"Session ID: {session_id}")
    print(f"{'='*60}\n")
    
    results = []
    total_score = 0
    successful_tests = 0
    
    for i, question in enumerate(TEST_QUESTIONS, 1):
        print(f"\n{'─'*60}")
        print(f"Test {i}/{len(TEST_QUESTIONS)}")
        print(f"{'─'*60}")
        
        # Invoke agent
        agent_result = invoke_agent(agent_id, agent_alias_id, question, session_id)
        
        if agent_result['success']:
            # Evaluate response
            evaluation = evaluate_response(
                question=agent_result['question'],
                response=agent_result['response']
            )
            
            agent_result['evaluation'] = evaluation
            total_score += evaluation['overall_score']
            successful_tests += 1
        
        results.append(agent_result)
        
        # Small delay between requests
        time.sleep(1)
    
    # Summary
    print(f"\n{'='*60}")
    print(f"Summary")
    print(f"{'='*60}")
    print(f"Total Tests: {len(TEST_QUESTIONS)}")
    print(f"Successful: {successful_tests}")
    print(f"Failed: {len(TEST_QUESTIONS) - successful_tests}")
    
    if successful_tests > 0:
        avg_score = total_score / successful_tests
        print(f"Average Score: {avg_score:.2f}/10")
        
        # Score interpretation
        if avg_score >= 8:
            print(f"Rating: ⭐⭐⭐⭐⭐ Excellent")
        elif avg_score >= 6:
            print(f"Rating: ⭐⭐⭐⭐ Good")
        elif avg_score >= 4:
            print(f"Rating: ⭐⭐⭐ Fair")
        else:
            print(f"Rating: ⭐⭐ Needs Improvement")
    
    # Save results
    output_file = f"agent_test_results_{int(time.time())}.json"
    with open(output_file, 'w') as f:
        json.dump({
            'agent_id': agent_id,
            'agent_alias_id': agent_alias_id,
            'session_id': session_id,
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'total_tests': len(TEST_QUESTIONS),
                'successful': successful_tests,
                'failed': len(TEST_QUESTIONS) - successful_tests,
                'average_score': total_score / successful_tests if successful_tests > 0 else 0
            },
            'results': results
        }, f, indent=2)
    
    print(f"\n📄 Results saved to: {output_file}")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
