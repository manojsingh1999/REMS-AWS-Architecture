#!/usr/bin/env python3
"""Render every REMS chart for every environment without the helm binary and validate the output.

Steps per chart/env:
  1. Helm-style values merge: values.yaml <- values-<env>.yaml <- helm/environments/<env>/global.yaml
     (maps merge recursively, lists replace, null deletes a key)
  2. Render with scripts/helm-render-check (Go text/template + Sprig subset used by rems-common)
  3. Parse the YAML output and run kubeconform (Kubernetes 1.31 + CRD catalog) if installed

Usage: python3 scripts/helm_render_check.py [--out rendered/]
"""
import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARTS = os.path.join(ROOT, "helm", "charts")
ENVS = ["dev", "staging", "prod", "prod-dr"]
# value files per environment (same layering as the ArgoCD ApplicationSets)
LAYERS = {"dev": ["dev"], "staging": ["staging"], "prod": ["prod"], "prod-dr": ["prod", "prod-dr"]}
CRD_SCHEMAS = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"


def merge(base, over):
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        if v is None:
            out.pop(k, None)
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None, help="write rendered manifests to this directory")
    args = ap.parse_args()

    renderer = os.path.join(tempfile.mkdtemp(), "helm-render-check")
    subprocess.run(["go", "build", "-o", renderer, os.path.join(ROOT, "scripts", "helm-render-check", "main.go")],
                   check=True, env=dict(os.environ, GO111MODULE="off", GOFLAGS=""))

    failures = 0
    have_kc = shutil.which("kubeconform") is not None
    for chart in sorted(os.listdir(CHARTS)):
        cdir = os.path.join(CHARTS, chart)
        meta = yaml.safe_load(open(os.path.join(cdir, "Chart.yaml")))
        if meta.get("type") == "library":
            continue
        ns = meta.get("annotations", {}).get("rems.io/namespace", "default")
        base = yaml.safe_load(open(os.path.join(cdir, "values.yaml")))
        for env in ENVS:
            vals = base
            for layer in LAYERS[env]:
                vals = merge(vals, yaml.safe_load(open(os.path.join(cdir, f"values-{layer}.yaml"))))
            vals = merge(vals, yaml.safe_load(open(os.path.join(ROOT, "helm", "environments", env, "global.yaml"))))
            with tempfile.TemporaryDirectory() as td:
                vf = os.path.join(td, "values.json")
                json.dump(vals, open(vf, "w"))
                json.dump(meta, open(os.path.join(cdir, "Chart.json"), "w"))
                try:
                    res = subprocess.run([renderer, cdir, os.path.join(CHARTS, "rems-common"), vf, chart, ns],
                                         capture_output=True, text=True)
                finally:
                    os.remove(os.path.join(cdir, "Chart.json"))
                label = f"{chart}/{env}"
                if res.returncode != 0:
                    print(f"FAIL {label}: {res.stderr.strip()}")
                    failures += 1
                    continue
                try:
                    docs = [d for d in yaml.safe_load_all(res.stdout) if d]
                except yaml.YAMLError as exc:
                    print(f"FAIL {label}: invalid YAML output: {exc}")
                    failures += 1
                    continue
                kinds = ",".join(sorted({d["kind"] for d in docs}))
                rendered = os.path.join(td, "out.yaml")
                open(rendered, "w").write(res.stdout)
                if args.out:
                    os.makedirs(os.path.join(args.out, env), exist_ok=True)
                    shutil.copy(rendered, os.path.join(args.out, env, f"{chart}.yaml"))
                status = "OK  "
                if have_kc:
                    kc = subprocess.run(["kubeconform", "-strict", "-summary", "-kubernetes-version", "1.31.0",
                                         "-schema-location", "default", "-schema-location", CRD_SCHEMAS, rendered],
                                        capture_output=True, text=True)
                    if kc.returncode != 0:
                        print(f"FAIL {label}: kubeconform\n{kc.stdout}{kc.stderr}")
                        failures += 1
                        continue
                    status = "OK  "
                print(f"{status}{label:32s} {len(docs):2d} objects  [{kinds}]")
    if failures:
        print(f"\n{failures} chart/environment combination(s) failed")
        sys.exit(1)
    print("\nAll charts rendered" + (" and passed kubeconform" if have_kc else ""))


if __name__ == "__main__":
    main()
