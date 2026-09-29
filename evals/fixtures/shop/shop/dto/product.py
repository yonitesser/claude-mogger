"""Product data transfer object."""
from dataclasses import dataclass


@dataclass
class ProductDTO:
    sku: str
    name: str
    price_cents: int

    @classmethod
    def from_dict(cls, data):
        # Unknown keys are ignored; names are stripped of surrounding whitespace.
        return cls(sku=data["sku"], name=data["name"].strip(), price_cents=int(data["price_cents"]))

    def to_dict(self):
        return {"sku": self.sku, "name": self.name, "price_cents": self.price_cents}
