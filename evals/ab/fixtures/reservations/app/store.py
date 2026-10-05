"""In-memory state. Reset between tests with reset()."""

ITEMS = {}
_NEXT_ITEM_ID = 1


def next_item_id():
    global _NEXT_ITEM_ID
    n = _NEXT_ITEM_ID
    _NEXT_ITEM_ID += 1
    return n


def reset():
    global _NEXT_ITEM_ID
    ITEMS.clear()
    _NEXT_ITEM_ID = 1
