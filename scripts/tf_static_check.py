#!/usr/bin/env python3
"""Offline Terraform consistency checker (no providers / network needed).

Complements `terraform validate` when the terraform binary or registry is unavailable:
  * every .tf file parses (HCL2)
  * module calls: unknown arguments, missing required variables
  * references: var.X declared, local.X defined, module.X declared,
    module.X.Y output exists, data/resource references declared
Usage: python3 scripts/tf_static_check.py terraform/
"""
import os
import re
import sys

import hcl2

META_ARGS = {"source", "providers", "count", "for_each", "depends_on", "version"}
errors = []


def uq(x):
    """python-hcl2 >= 7 keeps quotes around block labels and string literals."""
    if isinstance(x, str) and len(x) >= 2 and x[0] == '"' and x[-1] == '"':
        return x[1:-1]
    return x


def norm(obj):
    if isinstance(obj, dict):
        return {uq(k): norm(v) for k, v in obj.items() if not (k.startswith("__") and k.endswith("__"))}
    if isinstance(obj, list):
        return [norm(i) for i in obj]
    return uq(obj)


def load_dir(d):
    blocks = {"variable": {}, "output": {}, "locals": set(), "module": {}, "resource": set(), "data": set()}
    texts = {}
    for f in sorted(os.listdir(d)):
        if not f.endswith(".tf"):
            continue
        path = os.path.join(d, f)
        text = open(path).read()
        texts[path] = text
        try:
            obj = norm(hcl2.loads(text))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"PARSE {path}: {exc}")
            continue
        for v in obj.get("variable", []):
            for name, body in v.items():
                blocks["variable"][name] = body
        for o in obj.get("output", []):
            blocks["output"].update(o)
        for l in obj.get("locals", []):
            blocks["locals"].update(l.keys())
        for m in obj.get("module", []):
            blocks["module"].update(m)
        for r in obj.get("resource", []):
            for rtype, inst in r.items():
                for rname in inst:
                    blocks["resource"].add(f"{rtype}.{rname}")
        for r in obj.get("data", []):
            for rtype, inst in r.items():
                for rname in inst:
                    blocks["data"].add(f"{rtype}.{rname}")
    return blocks, texts


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.splitlines():
        # remove # and // comments that are not inside strings (good enough for our code style)
        in_str = False
        res = ""
        i = 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            if not in_str and (c == "#" or line[i:i + 2] == "//"):
                break
            res += c
            i += 1
        out.append(res)
    return "\n".join(out)


def check_dir(d):
    blocks, texts = load_dir(d)
    if not texts:
        return
    all_text = "\n".join(strip_comments(t) for t in texts.values())

    for ref in set(re.findall(r"\bvar\.([A-Za-z0-9_-]+)", all_text)):
        if ref not in blocks["variable"]:
            errors.append(f"{d}: var.{ref} is not declared")
    for ref in set(re.findall(r"\blocal\.([A-Za-z0-9_-]+)", all_text)):
        if ref not in blocks["locals"]:
            errors.append(f"{d}: local.{ref} is not defined")
    for ref in set(re.findall(r"\bdata\.([a-z0-9_]+\.[A-Za-z0-9_-]+)", all_text)):
        if ref not in blocks["data"] and not ref.startswith("terraform_remote_state"):
            errors.append(f"{d}: data.{ref} is not declared")
    if "terraform_remote_state" in all_text:
        pass
    for rtype, rname in set(re.findall(r"(?<![\w.\"])(aws_[a-z0-9_]+|random_[a-z_]+)\.([a-z0-9_]+)\b", all_text)):
        key = f"{rtype}.{rname}"
        if key not in blocks["resource"]:
            errors.append(f"{d}: resource {key} referenced but not declared")

    for mname, mbody in blocks["module"].items():
        src = mbody.get("source")
        if not isinstance(src, str) or not src.startswith("."):
            continue
        child = os.path.normpath(os.path.join(d, src))
        if not os.path.isdir(child):
            errors.append(f"{d}: module {mname} source {src} not found")
            continue
        cblocks, _ = load_dir(child)
        for arg in mbody:
            if arg in META_ARGS:
                continue
            if arg not in cblocks["variable"]:
                errors.append(f"{d}: module {mname} passes unknown argument '{arg}'")
        for vname, vbody in cblocks["variable"].items():
            if "default" not in vbody and vname not in mbody:
                errors.append(f"{d}: module {mname} missing required variable '{vname}'")
        for out in set(re.findall(r"\bmodule\." + re.escape(mname) + r"(?:\[[^\]]+\])?\.([A-Za-z0-9_]+)", all_text)):
            if out not in cblocks["output"]:
                errors.append(f"{d}: module.{mname}.{out} is not an output of {src}")

    for ref in set(re.findall(r"\bmodule\.([A-Za-z0-9_-]+)", all_text)):
        if ref not in blocks["module"]:
            errors.append(f"{d}: module.{ref} referenced but not declared")


def main(root):
    dirs = sorted({dp for dp, _, fs in os.walk(root) if any(f.endswith(".tf") for f in fs) and ".terraform" not in dp})
    for d in dirs:
        check_dir(d)
    if errors:
        print("\n".join(sorted(set(errors))))
        print(f"\nFAILED: {len(set(errors))} issue(s) in {len(dirs)} directories")
        sys.exit(1)
    print(f"OK: {len(dirs)} Terraform directories parsed and cross-checked")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "terraform")
