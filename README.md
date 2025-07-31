# secure-bot-service

## Overview

`secure-bot-service` is a reference implementation for a secure, cloud-native conversational agent (bot) service. It demonstrates how to build, deploy, and manage a Microsoft 365 Copilot-compatible bot using modern Azure infrastructure and best practices for authentication, authorization, and operational security.

## High-Level Architecture

```
User ──▶ Teams ──▶ App GW ──▶ Container Apps
                                │
                                └──▶ Azure AI Foundry Agent 
                                │
                                └──▶ Graph API (OBO)
                                │
                                └──▶ Secure Storage / State Management
```

- **Bot Service**: Node.js/TypeScript Express app using Microsoft Agents SDK, with JWT-based authentication and Microsoft Graph integration.
- **Infrastructure**: Provisioned via Terraform, including Azure resources (Container Apps, Managed Identity, Log Analytics, etc.).
- **Security**: Uses Azure AD for authentication, supports secure secret management, and can be extended for custom domains and certificates.
- **Extensibility**: Easily connect to additional Azure AI services or custom APIs.

## Repository Structure

- `bot/` - Source code for the bot service (TypeScript, Express, Microsoft Agents SDK)
  - `src/` - Main application and agent logic
  - `Dockerfile` - Containerization for cloud deployment
  - `env.sample` - Example environment variables
- `terraform/` - Infrastructure as Code for Azure resources
  - `main.tf`, `variables.tf` - Core Terraform configuration
  - `env.sample` - Example Terraform environment variables

## Getting Started

1. **Configure environment variables** for both bot and Terraform using the provided `env.sample` files.
2. **Build and run the bot locally**:
   ```bash
   cd bot
   npm install
   npm run build
   npm start
   ```
3. **Provision Azure infrastructure**:
   ```bash
   cd ../terraform
   terraform init
   terraform apply
   ```

## Key Technologies

- Node.js, TypeScript, Express
- Microsoft Agents SDK, Microsoft Graph
- Azure App Service, Managed Identity, Log Analytics
- Terraform

## License

MIT License. See [LICENSE](LICENSE) for details.