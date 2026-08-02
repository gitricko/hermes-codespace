#!/usr/bin/env python3
"""Validate Mnemon seed.json structure and content."""
import json
import sys

def validate_seed(path):
    with open(path) as f:
        data = json.load(f)

    errors = []

    # Schema version
    if data.get("schema_version") != "1":
        errors.append(f'schema_version must be "1", got "{data.get("schema_version")}"')

    # Insights array
    insights = data.get("insights", [])
    if not insights:
        errors.append("insights array is empty")

    valid_categories = {"preference", "decision", "fact", "insight", "context", "general"}

    for i, e in enumerate(insights):
        # Required fields
        for field in ("content", "category", "importance", "tags", "entities"):
            if field not in e:
                errors.append(f"insight[{i}]: missing '{field}'")

        # Importance range
        imp = e.get("importance", 0)
        if imp < 1 or imp > 5:
            errors.append(f"insight[{i}]: importance must be 1-5, got {imp}")

        # Category validation
        cat = e.get("category", "")
        if cat not in valid_categories:
            errors.append(f"insight[{i}]: invalid category '{cat}'")

        # Content length
        content = e.get("content", "")
        if len(content) > 8000:
            errors.append(f"insight[{i}]: content too long ({len(content)} > 8000 chars)")

    # Size guard
    if len(insights) > 50:
        errors.append(f"too many insights ({len(insights)} > 50) — consolidate")

    if errors:
        print(f"FAIL: {len(errors)} error(s) in {path}")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print(f"OK: {len(insights)} insights, schema_version={data.get('schema_version')}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: validate-seed.py <path-to-seed.json>")
        sys.exit(1)
    validate_seed(sys.argv[1])
