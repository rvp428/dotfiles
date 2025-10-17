#!/usr/bin/env python3
import sys
from ruamel.yaml import YAML
from ruamel.yaml.scalarstring import FoldedScalarString

def fold_long_strings(node, width):
    if isinstance(node, dict):
        return {k: fold_long_strings(v, width) for k, v in node.items()}
    if isinstance(node, list):
        return [fold_long_strings(v, width) for v in node]
    if isinstance(node, str) and ("\n" in node or len(node) > width):
        return FoldedScalarString(node)
    return node

def main():
    width = int(sys.argv[1]) if len(sys.argv) > 1 else 88
    yaml = YAML(typ="rt")  # round-trip; preserves comments & styles
    yaml.preserve_quotes = True
    yaml.width = width
    data = yaml.load(sys.stdin)
    data = fold_long_strings(data, width)
    yaml.dump(data, sys.stdout)

if __name__ == "__main__":
    main()

