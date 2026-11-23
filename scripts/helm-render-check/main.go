// helm-render-check: renders REMS Helm charts WITHOUT the helm binary (air-gapped CI or
// restricted workstations). It implements the subset of Helm/Sprig used by rems-common so
// template errors (bad paths, missing `required` values, YAML indentation) surface early.
// It is a safety net, not a replacement: CI still runs `helm lint` and `helm template`.
//
// Usage: go run ./scripts/helm-render-check <chart-dir> <library-dir> <values.json> <release-name> <namespace>
// values.json is the merged values (see helm_render_check.py which performs Helm-style merging).
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"text/template"
)

func strval(v interface{}) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	default:
		return fmt.Sprint(t)
	}
}

func empty(v interface{}) bool {
	if v == nil {
		return true
	}
	rv := reflect.ValueOf(v)
	switch rv.Kind() {
	case reflect.String, reflect.Map, reflect.Slice, reflect.Array:
		return rv.Len() == 0
	case reflect.Bool:
		return !rv.Bool()
	case reflect.Float64, reflect.Float32:
		return rv.Float() == 0
	case reflect.Int, reflect.Int64, reflect.Int32:
		return rv.Int() == 0
	}
	return false
}

// ---------------------------------------------------------------- minimal YAML emitter (sorted keys like sigs.k8s.io/yaml)
func needsQuote(s string) bool {
	if s == "" {
		return true
	}
	lower := strings.ToLower(s)
	switch lower {
	case "true", "false", "yes", "no", "on", "off", "null", "~", "y", "n":
		return true
	}
	if _, err := strconv.ParseFloat(s, 64); err == nil {
		return true
	}
	if strings.ContainsAny(s, ":#{}[],&*!|>'\"%@`\n\t") || strings.HasPrefix(s, "-") || strings.HasPrefix(s, " ") || strings.HasSuffix(s, " ") || strings.HasPrefix(s, "?") {
		return true
	}
	return false
}

func scalar(v interface{}) string {
	switch t := v.(type) {
	case nil:
		return "null"
	case bool:
		return strconv.FormatBool(t)
	case float64:
		return strval(t)
	case string:
		if needsQuote(t) {
			b, _ := json.Marshal(t)
			return string(b)
		}
		return t
	}
	return fmt.Sprint(v)
}

func toYAML(v interface{}, indent int, b *strings.Builder) {
	pad := strings.Repeat("  ", indent)
	switch t := v.(type) {
	case map[string]interface{}:
		if len(t) == 0 {
			b.WriteString(pad + "{}\n")
			return
		}
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			val := t[k]
			switch c := val.(type) {
			case map[string]interface{}:
				if len(c) == 0 {
					b.WriteString(pad + scalar(k) + ": {}\n")
				} else {
					b.WriteString(pad + scalar(k) + ":\n")
					toYAML(c, indent+1, b)
				}
			case []interface{}:
				if len(c) == 0 {
					b.WriteString(pad + scalar(k) + ": []\n")
				} else {
					b.WriteString(pad + scalar(k) + ":\n")
					toYAML(c, indent, b)
				}
			default:
				b.WriteString(pad + scalar(k) + ": " + scalar(c) + "\n")
			}
		}
	case []interface{}:
		if len(t) == 0 {
			b.WriteString(pad + "[]\n")
			return
		}
		for _, item := range t {
			var sub strings.Builder
			switch item.(type) {
			case map[string]interface{}, []interface{}:
				toYAML(item, 0, &sub)
				lines := strings.Split(strings.TrimRight(sub.String(), "\n"), "\n")
				b.WriteString(pad + "- " + lines[0] + "\n")
				for _, l := range lines[1:] {
					b.WriteString(pad + "  " + l + "\n")
				}
			default:
				b.WriteString(pad + "- " + scalar(item) + "\n")
			}
		}
	default:
		b.WriteString(pad + scalar(t) + "\n")
	}
}

func indentStr(n int, s string) string {
	pad := strings.Repeat(" ", n)
	return pad + strings.ReplaceAll(s, "\n", "\n"+pad)
}

func main() {
	if len(os.Args) != 6 {
		fmt.Fprintln(os.Stderr, "usage: helm-render-check <chart> <library> <values.json> <release> <namespace>")
		os.Exit(2)
	}
	chartDir, libDir, valuesFile, release, namespace := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5]

	raw, err := os.ReadFile(valuesFile)
	must(err)
	var values map[string]interface{}
	must(json.Unmarshal(raw, &values))

	chartMeta := map[string]interface{}{}
	metaRaw, err := os.ReadFile(filepath.Join(chartDir, "Chart.json"))
	must(err)
	must(json.Unmarshal(metaRaw, &chartMeta))

	root := template.New("root").Option("missingkey=zero")
	funcs := template.FuncMap{
		"include": func(name string, data interface{}) (string, error) {
			var buf bytes.Buffer
			err := root.ExecuteTemplate(&buf, name, data)
			return buf.String(), err
		},
		"toYaml": func(v interface{}) string {
			var b strings.Builder
			toYAML(v, 0, &b)
			return strings.TrimSuffix(b.String(), "\n")
		},
		"toJson": func(v interface{}) string { b, _ := json.Marshal(v); return string(b) },
		"nindent": func(n int, s string) string { return "\n" + indentStr(n, s) },
		"indent":  indentStr,
		"default": func(d interface{}, given ...interface{}) interface{} {
			if len(given) == 0 || empty(given[0]) {
				return d
			}
			return given[0]
		},
		"quote": func(v ...interface{}) string {
			out := []string{}
			for _, s := range v {
				if s != nil {
					out = append(out, strconv.Quote(strval(s)))
				}
			}
			return strings.Join(out, " ")
		},
		"required": func(msg string, v interface{}) (interface{}, error) {
			if v == nil || (reflect.TypeOf(v).Kind() == reflect.String && v.(string) == "") {
				return nil, fmt.Errorf("required: %s", msg)
			}
			return v, nil
		},
		"trunc": func(n int, s string) string {
			if len(s) > n {
				return s[:n]
			}
			return s
		},
		"trimSuffix": func(suf, s string) string { return strings.TrimSuffix(s, suf) },
		"trim":       strings.TrimSpace,
		"replace":    func(old, new, s string) string { return strings.ReplaceAll(s, old, new) },
		"dict": func(kv ...interface{}) map[string]interface{} {
			m := map[string]interface{}{}
			for i := 0; i+1 < len(kv); i += 2 {
				m[strval(kv[i])] = kv[i+1]
			}
			return m
		},
		"list":   func(v ...interface{}) []interface{} { return v },
		"append": func(l []interface{}, v interface{}) []interface{} { return append(append([]interface{}{}, l...), v) },
		"hasKey": func(m map[string]interface{}, k string) bool { _, ok := m[k]; return ok },
		"has": func(needle interface{}, hay []interface{}) bool {
			for _, h := range hay {
				if reflect.DeepEqual(h, needle) {
					return true
				}
			}
			return false
		},
		"ternary": func(a, b interface{}, c bool) interface{} {
			if c {
				return a
			}
			return b
		},
		"sha256sum": func(s string) string { h := sha256.Sum256([]byte(s)); return hex.EncodeToString(h[:]) },
	}
	root.Funcs(funcs)

	var files []string
	for _, dir := range []string{filepath.Join(libDir, "templates"), filepath.Join(chartDir, "templates")} {
		entries, err := os.ReadDir(dir)
		must(err)
		for _, e := range entries {
			if !e.IsDir() {
				files = append(files, filepath.Join(dir, e.Name()))
			}
		}
	}
	for _, f := range files {
		body, err := os.ReadFile(f)
		must(err)
		_, err = root.New(filepath.Base(f)).Parse(string(body))
		if err != nil {
			fmt.Fprintf(os.Stderr, "PARSE ERROR %s: %v\n", f, err)
			os.Exit(1)
		}
	}

	ctx := map[string]interface{}{
		"Values":  values,
		"Chart":   map[string]interface{}{"Name": chartMeta["name"], "Version": chartMeta["version"], "AppVersion": chartMeta["appVersion"]},
		"Release": map[string]interface{}{"Name": release, "Namespace": namespace, "Service": "Helm"},
	}
	for _, f := range files {
		base := filepath.Base(f)
		if strings.HasPrefix(base, "_") || !strings.HasSuffix(base, ".yaml") {
			continue
		}
		var out bytes.Buffer
		if err := root.ExecuteTemplate(&out, base, ctx); err != nil {
			fmt.Fprintf(os.Stderr, "RENDER ERROR %s: %v\n", base, err)
			os.Exit(1)
		}
		fmt.Print(strings.ReplaceAll(out.String(), "<no value>", ""))
	}
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
