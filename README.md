# Serverless API Platform (AWS)


Multi‑stage HTTP API with **API Gateway + Lambda (Python) + DynamoDB + EventBridge**, secured by **Cognito**, fully automated with **Terraform + GitHub Actions (OIDC, no long‑lived keys)**.


![Architecture](./docs/architecture.png)


<p align="center">
<a href="https://github.com/gabriel-ejiro/serverless-api-platform/actions">
<img alt="CI" src="https://img.shields.io/github/actions/workflow/status/gabriel-ejiro/serverless-api-platform/terraform-deploy.yml?label=deploy" />
</a>
<a href="https://github.com/gabriel-ejiro/serverless-api-platform">
<img alt="License" src="https://img.shields.io/badge/IaC-Terraform-7B42BC" />
</a>
<img alt="Auth" src="https://img.shields.io/badge/Auth-Cognito-FF9900" />
<img alt="CI/CD" src="https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF" />
</p>


## ✨ Features
- JWT-protected routes via Cognito User Pool (Hosted UI)
- Durable persistence (DynamoDB) + async fan‑out (EventBridge)
- Zero‑secret CI/CD: GitHub → AWS via OIDC role assumption
- One‑command deploy & destroy (`terraform apply|destroy`)


## 🗺️ Architecture
See [`docs/architecture.mmd`](./docs/architecture.mmd) (Mermaid). A rendered PNG is recommended as `docs/architecture.png`.


**Flow:** Client → API Gateway HTTP API → Lambda (Python) → DynamoDB. POST `/items` emits `serverless.api` events to EventBridge (logged).


## 🚀 Deploy (10 minutes)
```bash
# Configure repo vars (Settings → Secrets and variables → Actions → Variables):
# AWS_ROLE_ARN, AWS_REGION (e.g., eu-north-1)
# Push to main to trigger GitHub Actions (terraform apply)


# (Optional) local apply
terraform -chdir=infra init -reconfigure
terraform -chdir=infra apply -auto-approve
