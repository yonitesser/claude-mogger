"""Plan catalogue and limits for the billing service.

Layout of this file (top to bottom):
  1. PLANS            one entry per sellable plan, base price in cents per month
  2. RATE_LIMITS      requests per minute by tier
  3. REGION_FACTORS   multiplier on the tier rate limit by region
  4. FEATURE_FLAGS    which tier gets which feature
  5. OVERRIDES        price changes, applied IN ORDER (later entries win)
  6. REGION_RATE_OVERRIDES  explicit rate limits that beat the region factor
  7. helper functions

Prices are integers in cents per month. Never use floats for money.
"""

PLANS = {
    "free-monthly": {
        "tier": "free",
        "cycle": "monthly",
        "price_cents": 0,
        "seats": 1,
        "trial_days": 0,
        "sellable": True,
        "notes": "free plan on the monthly cycle",
        "limits": {
            "projects": 2,
            "storage_gb": 5,
            "retention_days": 30,
            "max_upload_mb": 25,
            "concurrent_jobs": 1,
        },
    },
    "free-annual": {
        "tier": "free",
        "cycle": "annual",
        "price_cents": 0,
        "seats": 1,
        "trial_days": 0,
        "sellable": True,
        "notes": "free plan on the annual cycle",
        "limits": {
            "projects": 2,
            "storage_gb": 5,
            "retention_days": 30,
            "max_upload_mb": 25,
            "concurrent_jobs": 1,
        },
    },
    "starter-monthly": {
        "tier": "starter",
        "cycle": "monthly",
        "price_cents": 1200,
        "seats": 3,
        "trial_days": 14,
        "sellable": True,
        "notes": "starter plan on the monthly cycle",
        "limits": {
            "projects": 6,
            "storage_gb": 15,
            "retention_days": 30,
            "max_upload_mb": 250,
            "concurrent_jobs": 1,
        },
    },
    "starter-annual": {
        "tier": "starter",
        "cycle": "annual",
        "price_cents": 960,
        "seats": 3,
        "trial_days": 14,
        "sellable": True,
        "notes": "starter plan on the annual cycle",
        "limits": {
            "projects": 6,
            "storage_gb": 15,
            "retention_days": 30,
            "max_upload_mb": 250,
            "concurrent_jobs": 1,
        },
    },
    "starter-edu": {
        "tier": "starter",
        "cycle": "annual",
        "price_cents": 960,
        "seats": 3,
        "trial_days": 14,
        "sellable": True,
        "notes": "starter plan on the annual cycle",
        "limits": {
            "projects": 6,
            "storage_gb": 15,
            "retention_days": 30,
            "max_upload_mb": 250,
            "concurrent_jobs": 1,
        },
    },
    "starter-legacy2023": {
        "tier": "starter",
        "cycle": "monthly",
        "price_cents": 1080,
        "seats": 3,
        "trial_days": 14,
        "sellable": False,
        "notes": "starter plan on the monthly cycle",
        "limits": {
            "projects": 6,
            "storage_gb": 15,
            "retention_days": 30,
            "max_upload_mb": 250,
            "concurrent_jobs": 1,
        },
    },
    "team-monthly": {
        "tier": "team",
        "cycle": "monthly",
        "price_cents": 4900,
        "seats": 15,
        "trial_days": 14,
        "sellable": True,
        "notes": "team plan on the monthly cycle",
        "limits": {
            "projects": 30,
            "storage_gb": 75,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 2,
        },
    },
    "team-annual": {
        "tier": "team",
        "cycle": "annual",
        "price_cents": 7900,
        "seats": 15,
        "trial_days": 14,
        "sellable": True,
        "notes": "team plan on the annual cycle",
        "limits": {
            "projects": 30,
            "storage_gb": 75,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 2,
        },
    },
    "team-edu": {
        "tier": "team",
        "cycle": "annual",
        "price_cents": 3900,
        "seats": 15,
        "trial_days": 14,
        "sellable": True,
        "notes": "team plan on the annual cycle",
        "limits": {
            "projects": 30,
            "storage_gb": 75,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 2,
        },
    },
    "team-legacy2023": {
        "tier": "team",
        "cycle": "monthly",
        "price_cents": 4410,
        "seats": 15,
        "trial_days": 14,
        "sellable": False,
        "notes": "team plan on the monthly cycle",
        "limits": {
            "projects": 30,
            "storage_gb": 75,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 2,
        },
    },
    "business-monthly": {
        "tier": "business",
        "cycle": "monthly",
        "price_cents": 9900,
        "seats": 50,
        "trial_days": 0,
        "sellable": True,
        "notes": "business plan on the monthly cycle",
        "limits": {
            "projects": 100,
            "storage_gb": 250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 6,
        },
    },
    "business-annual": {
        "tier": "business",
        "cycle": "annual",
        "price_cents": 7920,
        "seats": 50,
        "trial_days": 0,
        "sellable": True,
        "notes": "business plan on the annual cycle",
        "limits": {
            "projects": 100,
            "storage_gb": 250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 6,
        },
    },
    "business-edu": {
        "tier": "business",
        "cycle": "annual",
        "price_cents": 7920,
        "seats": 50,
        "trial_days": 0,
        "sellable": True,
        "notes": "business plan on the annual cycle",
        "limits": {
            "projects": 100,
            "storage_gb": 250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 6,
        },
    },
    "business-legacy2023": {
        "tier": "business",
        "cycle": "monthly",
        "price_cents": 8910,
        "seats": 50,
        "trial_days": 0,
        "sellable": False,
        "notes": "business plan on the monthly cycle",
        "limits": {
            "projects": 100,
            "storage_gb": 250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 6,
        },
    },
    "enterprise-monthly": {
        "tier": "enterprise",
        "cycle": "monthly",
        "price_cents": 24900,
        "seats": 250,
        "trial_days": 0,
        "sellable": True,
        "notes": "enterprise plan on the monthly cycle",
        "limits": {
            "projects": 500,
            "storage_gb": 1250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 26,
        },
    },
    "enterprise-annual": {
        "tier": "enterprise",
        "cycle": "annual",
        "price_cents": 19920,
        "seats": 250,
        "trial_days": 0,
        "sellable": True,
        "notes": "enterprise plan on the annual cycle",
        "limits": {
            "projects": 500,
            "storage_gb": 1250,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 26,
        },
    },
    "enterprise-plus-monthly": {
        "tier": "enterprise-plus",
        "cycle": "monthly",
        "price_cents": 49900,
        "seats": 1000,
        "trial_days": 0,
        "sellable": True,
        "notes": "enterprise-plus plan on the monthly cycle",
        "limits": {
            "projects": 2000,
            "storage_gb": 5000,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 101,
        },
    },
    "enterprise-plus-annual": {
        "tier": "enterprise-plus",
        "cycle": "annual",
        "price_cents": 39920,
        "seats": 1000,
        "trial_days": 0,
        "sellable": True,
        "notes": "enterprise-plus plan on the annual cycle",
        "limits": {
            "projects": 2000,
            "storage_gb": 5000,
            "retention_days": 365,
            "max_upload_mb": 250,
            "concurrent_jobs": 101,
        },
    },
}

RATE_LIMITS = {
    "free": 60,
    "starter": 300,
    "team": 1200,
    "business": 3000,
    "enterprise": 6000,
    "enterprise-plus": 10000,
}

REGION_FACTORS = {
    "us-east": 1.0,
    "us-west": 1.0,
    "eu-west": 0.75,
    "eu-central": 0.8,
    "ap-south": 0.6,
    "ap-northeast": 0.7,
    "sa-east": 0.5,
}

FEATURE_FLAGS = {
    "sso": ('starter', 'team', 'business', 'enterprise', 'enterprise-plus'),
    "audit_log": ('team', 'business', 'enterprise', 'enterprise-plus'),
    "priority_support": ('business', 'enterprise', 'enterprise-plus'),
    "custom_domains": ('enterprise', 'enterprise-plus'),
    "data_export": ('enterprise-plus',),
    "sla_99_9": ('starter', 'team', 'business', 'enterprise', 'enterprise-plus'),
    "dedicated_ip": ('team', 'business', 'enterprise', 'enterprise-plus'),
    "webhooks": ('business', 'enterprise', 'enterprise-plus'),
    "api_v2": ('enterprise', 'enterprise-plus'),
    "sandbox": ('enterprise-plus',),
}


# ---------------------------------------------------------------------------
# Quarterly price notes. These are history, kept for the finance team. They do
# not change any value by themselves; only entries in OVERRIDES below do.
# ---------------------------------------------------------------------------
# 2021 Q1: review 1. Finance sign-off ref FIN-1007.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2021 Q2: review 2. Finance sign-off ref FIN-1014.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2021 Q3: review 3. Finance sign-off ref FIN-1021.
#   - team plans: promo discussed, not approved here
#   - business plans: no change
#   - legacy plans: frozen
# 2021 Q4: review 4. Finance sign-off ref FIN-1028.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2022 Q1: review 5. Finance sign-off ref FIN-1035.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2022 Q2: review 6. Finance sign-off ref FIN-1042.
#   - team plans: promo discussed, not approved here
#   - business plans: list price held
#   - legacy plans: frozen
# 2022 Q3: review 7. Finance sign-off ref FIN-1049.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2022 Q4: review 8. Finance sign-off ref FIN-1056.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2023 Q1: review 9. Finance sign-off ref FIN-1063.
#   - team plans: promo discussed, not approved here
#   - business plans: no change
#   - legacy plans: frozen
# 2023 Q2: review 10. Finance sign-off ref FIN-1070.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2023 Q3: review 11. Finance sign-off ref FIN-1077.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2023 Q4: review 12. Finance sign-off ref FIN-1084.
#   - team plans: promo discussed, not approved here
#   - business plans: list price held
#   - legacy plans: frozen
# 2024 Q1: review 13. Finance sign-off ref FIN-1091.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2024 Q2: review 14. Finance sign-off ref FIN-1098.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2024 Q3: review 15. Finance sign-off ref FIN-1105.
#   - team plans: promo discussed, not approved here
#   - business plans: no change
#   - legacy plans: frozen
# 2024 Q4: review 16. Finance sign-off ref FIN-1112.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen
# 2025 Q1: review 17. Finance sign-off ref FIN-1119.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2025 Q2: review 18. Finance sign-off ref FIN-1126.
#   - team plans: promo discussed, not approved here
#   - business plans: list price held
#   - legacy plans: frozen
# 2025 Q3: review 19. Finance sign-off ref FIN-1133.
#   - team plans: no change
#   - business plans: no change
#   - legacy plans: frozen
# 2025 Q4: review 20. Finance sign-off ref FIN-1140.
#   - team plans: no change
#   - business plans: list price held
#   - legacy plans: frozen

OVERRIDES = []


def override(plan, **fields):
    """Record a change to a plan. Applied in the order written in this file."""
    OVERRIDES.append((plan, fields))


# 2024 list price rise
override('starter-monthly', **{'price_cents': 1260})
# 2024 list price rise
override('starter-annual', **{'price_cents': 1008})
# 2024 list price rise
override('business-monthly', **{'price_cents': 10395})
# 2024 list price rise
override('business-annual', **{'price_cents': 8316})
# 2024 list price rise
override('enterprise-monthly', **{'price_cents': 26145})
# 2024 list price rise
override('enterprise-annual', **{'price_cents': 20916})

# 2025 spring promo for team plans (approved FIN-1112)
override("team-annual", price_cents=7500)
override("team-monthly", price_cents=4500)

# housekeeping 1: no price effect, keeps the audit trail contiguous
# ref AUD-0201 reviewed and closed
# housekeeping 2: no price effect, keeps the audit trail contiguous
# ref AUD-0202 reviewed and closed
# housekeeping 3: no price effect, keeps the audit trail contiguous
# ref AUD-0203 reviewed and closed
# housekeeping 4: no price effect, keeps the audit trail contiguous
# ref AUD-0204 reviewed and closed
# housekeeping 5: no price effect, keeps the audit trail contiguous
# ref AUD-0205 reviewed and closed
# housekeeping 6: no price effect, keeps the audit trail contiguous
# ref AUD-0206 reviewed and closed
# housekeeping 7: no price effect, keeps the audit trail contiguous
# ref AUD-0207 reviewed and closed
# housekeeping 8: no price effect, keeps the audit trail contiguous
# ref AUD-0208 reviewed and closed

# Rejected by finance, DO NOT ENABLE (kept so nobody proposes it again)
# override("team-annual", price_cents=5900)

# 2025 autumn: promo ended, new annual price for team (approved FIN-1190)
override("team-annual", price_cents=6900)

# enterprise plus is quoted per contract; list value kept for reporting only
override("enterprise-plus-annual", price_cents=39900)

# legacy plans stay frozen
# starter-legacy2023: frozen, no override
# team-legacy2023: frozen, no override
# business-legacy2023: frozen, no override


REGION_RATE_OVERRIDES = {
    # (tier, region): requests per minute. Beats REGION_FACTORS.
    ("enterprise", "eu-central"): 4800,
    ("enterprise-plus", "eu-west"): 7500,
    ("business", "ap-south"): 1800,
    ("enterprise", "eu-west"): 5000,
    ("team", "sa-east"): 600,
}


def effective_price(plan):
    """Base price with every override for the plan applied in order."""
    price = PLANS[plan]["price_cents"]
    for name, fields in OVERRIDES:
        if name == plan and 'price_cents' in fields:
            price = fields['price_cents']
    return price


def rate_limit(tier, region):
    if (tier, region) in REGION_RATE_OVERRIDES:
        return REGION_RATE_OVERRIDES[(tier, region)]
    return int(RATE_LIMITS[tier] * REGION_FACTORS[region])


def has_feature(tier, feature):
    return tier in FEATURE_FLAGS.get(feature, ())


def sellable_plans():
    return sorted(n for n, p in PLANS.items() if p["sellable"])

