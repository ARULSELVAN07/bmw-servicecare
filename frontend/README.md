# ServiceCare frontend

The portal is a React/Vite static site. Cognito Hosted UI uses authorization code with PKCE; the app stores the ID token for the current browser session and sends it to the API Gateway Cognito authorizer.

## Build without local Node.js

The GitHub Actions workflow builds the app on GitHub's Node runner and publishes `dist/` as an artifact. Add these repository variables before pushing the frontend:

- `SERVICECARE_API_URL`: `terraform output -raw api_url`
- `COGNITO_DOMAIN_URL`: `terraform output -raw cognito_domain_url`
- `COGNITO_APP_CLIENT_ID`: `terraform output -raw cognito_app_client_id`
- `SERVICECARE_FRONTEND_URL`: `terraform output -raw frontend_url`

After the workflow succeeds, download and extract the `servicecare-frontend-dist` artifact into `frontend/dist`. With AWS CLI credentials configured, deploy from the project root:

```powershell
aws s3 sync .\frontend\dist "s3://$(terraform output -raw frontend_bucket_name)" --delete
aws cloudfront create-invalidation --distribution-id (terraform output -raw frontend_distribution_id) --paths "/*"
```

Open the URL from `terraform output -raw frontend_url` after the CloudFront deployment is ready.

## Advisor access

Only users in the Cognito `ServiceAdvisors` group can update tickets. Add advisor accounts to that group in the Cognito console. Customers can retrieve only tickets created by their own account.