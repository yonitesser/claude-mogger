"""Builds dist/ and build/ from app/ (stand-in for the real bundler)."""
import os

os.makedirs("build", exist_ok=True)
os.makedirs("dist", exist_ok=True)
with open("build/bundle.js", "w") as f:
    f.write("// bundle\n")
print("built")
