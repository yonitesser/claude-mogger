# Provider webhooks (copied from the provider's docs)

- The provider sends `POST` with a JSON body and these headers:
  - `X-Signature`: hex HMAC-SHA256 of the raw request body, keyed with your webhook secret.
- If your endpoint does not answer 2xx within 5 seconds, the provider sends the same event
  again (same `id`), up to 5 times.
