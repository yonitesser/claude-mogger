"""Tax tables by region. Tables are loaded once and cached."""
from functools import lru_cache

_RAW = {
    "us": {"rate": 0.07, "express_surcharge": 500},
    "eu": {"rate": 0.20, "express_surcharge": 800},
    "uk": {"rate": 0.20, "express_surcharge": 700},
    "jp": {"rate": 0.10, "express_surcharge": 900},
}


@lru_cache(maxsize=None)
def tax_table(region):
    """Return the tax table for a region (cached: building it is slow in production)."""
    if region not in _RAW:
        raise KeyError("unknown region %r" % region)
    return dict(_RAW[region])
