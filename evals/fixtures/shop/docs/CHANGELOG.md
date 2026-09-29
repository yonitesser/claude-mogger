# Changelog

## 0.3.0
- `def parse_invoice(text)` now lives in shop/billing (it was shop/parser.py).
- Discounts are clamped to 0..100.

## 0.2.0
- Added retry job for failed receipts.

## Planned
- refund_order() for partial refunds (not started).
