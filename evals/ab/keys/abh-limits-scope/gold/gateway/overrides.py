"""Hand-written exceptions to the generated table."""

# (tier, region) -> {"rpm": requests per minute, "burst": burst allowance}
OVERRIDES = {
    ("business", "ap-south-1"): {"rpm": 2500, "burst": 5000},
    ("enterprise", "eu-west-1"): {"rpm": 7500, "burst": 15000},
}
