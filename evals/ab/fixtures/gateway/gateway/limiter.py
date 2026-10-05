from gateway import limits_table as T
from gateway import overrides


def canonical_region(region):
    r = region.strip().lower()
    return T.REGION_ALIASES.get(r, r)


def limit_for(tier, region, endpoint=None):
    """Requests per minute. With an endpoint: that endpoint's own cap."""
    region = canonical_region(region)
    if endpoint is not None:
        return T.ENDPOINT_RPM[(tier, region, endpoint)]
    ov = overrides.OVERRIDES.get((tier, region), {})
    if "rpm" in ov:
        return ov["rpm"]
    return T.RPM[(tier, region)]


def burst_for(tier, region):
    region = canonical_region(region)
    ov = overrides.OVERRIDES.get((tier, region), {})
    if "burst" in ov:
        return ov["burst"]
    return T.BURST[(tier, region)]
