variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "agent_name" {
  description = "Name of the Bedrock agent"
  type        = string
  default     = "product-assistant"
}

variable "model_id" {
  description = "Bedrock model ID for the agent"
  type        = string
  default     = "anthropic.claude-3-5-haiku-20241022-v1:0"
}

variable "judge_model_id" {
  description = "Model ID for LLM-as-a-Judge evaluation"
  type        = string
  default     = "eu.anthropic.claude-3-haiku-20240307-v1:0"
}

variable "langfuse_public_key" {
  description = "Langfuse public key for tracing"
  type        = string
  default     = ""
}

variable "langfuse_secret_key" {
  description = "Langfuse secret key for tracing"
  type        = string
  sensitive   = true
  default     = ""
}

variable "langfuse_host" {
  description = "Langfuse host URL"
  type        = string
  default     = "https://cloud.langfuse.com"
}

variable "products_data_path" {
  description = "Path to products JSON file"
  type        = string
}

variable "lambda_runtime" {
  description = "Lambda runtime for MCP server"
  type        = string
  default     = "python3.12"
}
