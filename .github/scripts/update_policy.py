#!/usr/bin/env python3
"""
Append missing IAM actions into the TerraformResourceActions statement of a
terraform-apply-policy.json file.

Usage:
    update_policy.py <policy.json> <input>

    <input> may be either:
      - A JSON string: '["iam:Action1", "iam:Action2"]'
      - A path to a JSON file containing a list OR the full analysis object
        produced by parse_new_resources.py (the "all_missing" key is used).
"""

import json
import sys
from pathlib import Path

TARGET_SID = "TerraformResourceActions"


def load_missing_actions(raw: str) -> list:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        with open(raw) as f:
            data = json.load(f)

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        return data.get("all_missing", [])
    raise ValueError(f"Unexpected input type: {type(data)}")


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: update_policy.py <policy.json> <input>", file=sys.stderr)
        sys.exit(1)

    policy_path = Path(sys.argv[1])
    missing = load_missing_actions(sys.argv[2])

    if not missing:
        print("No missing actions — policy unchanged.")
        return

    with open(policy_path) as f:
        policy = json.load(f)

    updated = False
    for statement in policy.get("Statement", []):
        if statement.get("Effect") == "Allow" and statement.get("Sid") == TARGET_SID:
            existing = statement.get("Action", [])
            if isinstance(existing, str):
                existing = [existing]
            statement["Action"] = sorted(set(existing) | set(missing))
            updated = True
            break

    if not updated:
        # Fall back to the first Allow statement, or append a new one.
        for statement in policy.get("Statement", []):
            if statement.get("Effect") == "Allow":
                existing = statement.get("Action", [])
                if isinstance(existing, str):
                    existing = [existing]
                statement["Action"] = sorted(set(existing) | set(missing))
                updated = True
                break

    if not updated:
        policy.setdefault("Statement", []).append({
            "Sid": TARGET_SID,
            "Effect": "Allow",
            "Action": sorted(missing),
            "Resource": "*",
        })

    with open(policy_path, "w") as f:
        json.dump(policy, f, indent=2)
        f.write("\n")

    print(f"Policy updated — added {len(missing)} action(s): {', '.join(missing)}")


if __name__ == "__main__":
    main()