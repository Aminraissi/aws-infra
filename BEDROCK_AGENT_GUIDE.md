# Bedrock Agent - Guide d'utilisation

## 🤖 Vue d'ensemble

L'agent Bedrock "Product Assistant" est un assistant e-commerce intelligent qui peut:
- Rechercher des produits par catégorie, prix, ou mots-clés
- Vérifier la disponibilité et les stocks
- Fournir des informations détaillées sur les produits
- Recommander des produits similaires
- **Mémoriser** les préférences de l'utilisateur durant la conversation

## 🏗️ Architecture

```
┌─────────────────────┐
│   User (Website)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Bedrock Agent      │
│  (Claude 3.5 Haiku) │
└──────┬───────┬──────┘
       │       │
       │       └──────────────────┐
       │                          │
       ▼                          ▼
┌──────────────┐      ┌──────────────────────┐
│ Knowledge    │      │  MCP Server (Lambda) │
│ Base         │      │  - get_product_details│
│ (OpenSearch) │      │  - check_availability │
│              │      │  - search_products    │
│ Products JSON│      │  - get_recommendations│
└──────────────┘      └──────────────────────┘
```

## 📊 Outils MCP disponibles

### 1. **get_product_details**
Récupère les détails complets d'un produit.
```json
{
  "product_id": "watch-001"  // ou "Watch" (nom du produit)
}
```

### 2. **check_availability**
Vérifie la disponibilité et les stocks.
```json
{
  "product_id": "sunglasses-001"
}
```

### 3. **search_products**
Recherche des produits avec filtres.
```json
{
  "query": "kitchen",
  "category": "Kitchen",      // optionnel
  "max_price": 20.0          // optionnel
}
```

### 4. **get_recommendations**
Recommande des produits similaires.
```json
{
  "based_on": "tank-top-001"  // ID produit ou catégorie
}
```

## 🚀 Déploiement

### 1. Appliquer Terraform

```powershell
cd C:\Users\Amine\Downloads\aws\infra
terraform init
terraform apply -auto-approve
```

**Ressources créées:**
- ✅ Bedrock Agent avec mémoire de session
- ✅ Lambda MCP Server (4 tools)
- ✅ Knowledge Base (OpenSearch Serverless)
- ✅ S3 Bucket avec products.json
- ✅ IAM roles et permissions

**Durée:** ~10-15 minutes

### 2. Synchroniser la Knowledge Base

Une fois Terraform appliqué, lancez la synchronisation des données:

```bash
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <KB_ID_FROM_TERRAFORM_OUTPUT> \
  --data-source-id <DATA_SOURCE_ID> \
  --region eu-west-1
```

Ou via la console AWS:
1. Ouvre Bedrock > Knowledge bases
2. Sélectionne `online-boutique-products-kb`
3. Clique **Sync** sur la data source

**Durée:** ~2-5 minutes

## 🧪 Test de l'agent

### Test rapide (CLI)

```bash
# Copie l'agent ID et alias ID depuis Terraform outputs
terraform output bedrock_agent_id
terraform output bedrock_agent_alias_id

# Test simple
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-$(date +%s) \
  --input-text "Show me all watches" \
  --region eu-west-1 \
  response.txt

# Voir la réponse
cat response.txt
```

### Test complet avec évaluation

Utilise le script Python avec LLM-as-a-Judge:

```bash
cd infra/scripts
python test_agent.py <AGENT_ID> <ALIAS_ID>
```

**Ce script:**
- Pose 8 questions variées à l'agent
- Évalue chaque réponse avec Claude 3 Haiku (Judge)
- Calcule un score sur 10 pour chaque réponse
- Sauvegarde les résultats dans un fichier JSON

**Critères d'évaluation:**
- Accuracy (précision)
- Helpfulness (utilité)
- Completeness (complétude)
- Relevance (pertinence)
- Tone (ton)

## 💬 Exemples de conversations

### Exemple 1: Recherche basique
```
User: "Show me your watches"
Agent: "We have an elegant gold-tone wristwatch for $109.99. 
        It features water resistance, Japanese quartz movement, 
        and a mesh strap. We currently have 15 units in stock."
```

### Exemple 2: Filtrage par prix
```
User: "What do you have under $20?"
Agent: "I found several products under $20:
        - Sunglasses ($19.99) - UV protection, 45 in stock
        - Tank Top ($18.99) - Cotton blend, 30 in stock
        - Candle Holder ($18.99) - Metallic finish, 35 in stock
        - Salt & Pepper Shakers ($18.49) - Glass, 40 in stock"
```

### Exemple 3: Vérification de stock
```
User: "Is the hairdryer available?"
Agent: "Yes! The professional ionic hairdryer is in stock with 
        18 units available. It's priced at $24.99 and includes 
        3 heat settings and a concentrator nozzle."
```

### Exemple 4: Recommandations
```
User: "I like the sunglasses, what else would you suggest?"
Agent: "Based on the sunglasses, I recommend:
        - Watch ($109.99) - Similar accessories category
        - Candle Holder ($18.99) - Similar price range
        - Loafers ($89.99) - Complements your style"
```

### Exemple 5: Mémoire conversationnelle
```
User: "I'm looking for kitchen items"
Agent: "We have several kitchen products: Bamboo Glass Jar ($5.49), 
        Salt & Pepper Shakers ($18.49), and a Mug ($8.99)."

User: "What was the cheapest one you mentioned?"
Agent: "The cheapest kitchen item I mentioned was the Bamboo Glass Jar 
        at $5.49. It's eco-friendly with an airtight bamboo lid, 
        and we have 50 in stock."
```

## 💰 Estimation des coûts

### Par conversation (5 tours)

| Composant | Coût unitaire | Total |
|-----------|---------------|-------|
| Agent (Claude 3.5 Haiku) | $0.003/1K input | ~$0.003 |
|  | $0.015/1K output | ~$0.003 |
| Knowledge Base query | $0.002/query | ~$0.010 |
| Lambda MCP Server | $0.20/1M req | ~$0.0001 |
| **Total par conversation** |  | **~$0.016** |

### Évaluation LLM-as-a-Judge

| Composant | Coût |
|-----------|------|
| Claude 3 Haiku (Judge) | $0.0003/évaluation |

### Projection pour démo (5 heures)

| Scénario | Conversations | Coût Agent | Coût avec Judge |
|----------|---------------|------------|-----------------|
| Test léger | 10 | $0.16 | $0.16 |
| Démo active | 50 | $0.80 | $0.82 |
| Stress test | 200 | $3.20 | $3.26 |

**Coût infrastructre total (5h démo):**
- EKS + NAT + ALB + CloudFront + WAF: **$0.87**
- Agent Bedrock (50 conversations): **$0.82**
- **Total: ~$1.70**

## 🔧 Configuration avancée

### Changer le modèle de l'agent

Dans `infra/main.tf`:
```hcl
module "bedrock_agent" {
  # Pour économiser (10x moins cher):
  model_id = "anthropic.claude-3-haiku-20240307-v1:0"
  
  # Pour performance maximale:
  model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}
```

### Ajouter des produits

1. Édite `infra/data/products.json`
2. Ajoute tes produits:
```json
{
  "id": "new-product-001",
  "name": "Product Name",
  "category": "Category",
  "price": 29.99,
  "inStock": true,
  "quantity": 10,
  "description": "Description here"
}
```
3. Applique Terraform:
```bash
terraform apply -auto-approve
```
4. Resynchronise la Knowledge Base (voir section déploiement)

### Personnaliser les instructions de l'agent

Dans `infra/modules/bedrock-agent/main.tf`, modifie le bloc `instruction` de l'agent.

## 📱 Intégration frontend

### API REST simple

```python
import boto3
import json

client = boto3.client('bedrock-agent-runtime', region_name='eu-west-1')

def chat_with_agent(message: str, session_id: str):
    response = client.invoke_agent(
        agentId='<YOUR_AGENT_ID>',
        agentAliasId='<YOUR_ALIAS_ID>',
        sessionId=session_id,
        inputText=message
    )
    
    # Parse streaming response
    full_response = ""
    for event in response['completion']:
        if 'chunk' in event:
            chunk = event['chunk']
            if 'bytes' in chunk:
                full_response += chunk['bytes'].decode('utf-8')
    
    return full_response
```

### WebSocket pour streaming

Pour une expérience de chat en temps réel, utilise les streams Bedrock directement dans ton frontend.

## 🐛 Debugging

### Voir les logs Lambda
```bash
aws logs tail /aws/lambda/online-boutique-mcp-server --follow
```

### Tester un outil MCP directement
```bash
aws lambda invoke \
  --function-name online-boutique-mcp-server \
  --payload '{"function":"search_products","parameters":[{"name":"query","value":"kitchen"}]}' \
  response.json

cat response.json
```

### Vérifier la Knowledge Base
```bash
# Lister les data sources
aws bedrock-agent list-data-sources \
  --knowledge-base-id <KB_ID> \
  --region eu-west-1

# Vérifier le statut de synchronisation
aws bedrock-agent get-data-source \
  --knowledge-base-id <KB_ID> \
  --data-source-id <DATA_SOURCE_ID> \
  --region eu-west-1
```

## 🧹 Nettoyage

Pour détruire toutes les ressources:

```bash
cd infra
terraform destroy -auto-approve
```

⚠️ **Attention:** Cela supprimera l'agent, la knowledge base, et toutes les données associées.

## 📚 Ressources

- [Bedrock Agents Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [Knowledge Bases](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [Claude 3.5 Haiku Pricing](https://aws.amazon.com/bedrock/pricing/)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
