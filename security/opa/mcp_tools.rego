# MCP tool authorization. Every tool call from an AI agent / IDE is evaluated here BEFORE execution.
# Unknown tools, write-capable tools, cross-tenant scopes and oversized queries are denied, and every
# decision is written to the audit log by the MCP server.
#
# input = {
#   "subject": {"id": "...", "tenant_id": "t-1", "roles": ["sre"], "token_tenant_verified": true, "scopes": ["mcp/tools.read"]},
#   "tool":    {"name": "query_logs", "arguments": {"tenant_id": "t-1", "time_range_minutes": 60, "limit": 500}},
#   "rate":    {"calls_last_minute": 12}
# }
package rems.mcp

import rego.v1

default allow := false

# Allow-list of tools. Every tool is read-only by design; there is deliberately no tool that mutates
# infrastructure (no kubectl apply/delete, no AWS write APIs, no shell).
tools := {
	"query_metrics": {"roles": {"sre", "incident-viewer", "tenant-admin"}, "max_range_minutes": 1440, "max_limit": 10000},
	"query_logs": {"roles": {"sre", "tenant-admin"}, "max_range_minutes": 360, "max_limit": 2000},
	"query_traces": {"roles": {"sre", "tenant-admin"}, "max_range_minutes": 360, "max_limit": 500},
	"get_incident": {"roles": {"sre", "incident-viewer", "tenant-admin"}, "max_range_minutes": 0, "max_limit": 1},
	"list_alerts": {"roles": {"sre", "incident-viewer", "tenant-admin"}, "max_range_minutes": 1440, "max_limit": 500},
	"describe_workload": {"roles": {"sre", "tenant-admin"}, "max_range_minutes": 0, "max_limit": 50},
	"search_sops": {"roles": {"sre", "incident-viewer", "tenant-admin"}, "max_range_minutes": 0, "max_limit": 20},
}

# Verbs that must never appear in a tool name, even if someone adds it to the allow-list by mistake.
forbidden_verbs := {"delete", "apply", "patch", "exec", "scale", "restart", "drain", "create", "update", "put", "write", "terminate", "rollback"}

max_calls_per_minute := 60

tool := tools[input.tool.name]

has_scope if "mcp/tools.read" in input.subject.scopes

tenant_scoped if {
	input.subject.token_tenant_verified == true
	input.tool.arguments.tenant_id == input.subject.tenant_id
}

role_ok if {
	some role in input.subject.roles
	role in tool.roles
}

within_limits if {
	object.get(input.tool.arguments, "time_range_minutes", 0) <= tool.max_range_minutes
	object.get(input.tool.arguments, "limit", 1) <= tool.max_limit
}

not_mutating if {
	every verb in forbidden_verbs {
		not contains(lower(input.tool.name), verb)
	}
}

rate_ok if input.rate.calls_last_minute < max_calls_per_minute

allow if {
	has_scope
	tool
	not_mutating
	tenant_scoped
	role_ok
	within_limits
	rate_ok
}

reasons contains "missing scope mcp/tools.read" if not has_scope

reasons contains sprintf("tool %q is not allow-listed", [input.tool.name]) if not tools[input.tool.name]

reasons contains sprintf("tool %q looks mutating - always denied", [input.tool.name]) if not not_mutating

reasons contains "tenant scope mismatch (cross-tenant request)" if not tenant_scoped

reasons contains "role not permitted for tool" if {
	tools[input.tool.name]
	not role_ok
}

reasons contains "query exceeds tool limits" if {
	tools[input.tool.name]
	not within_limits
}

reasons contains "rate limit exceeded" if not rate_ok

# Severity drives alerting: a mutating or cross-tenant attempt is a security event, not a user error.
severity := "critical" if {
	not allow
	some r in reasons
	contains(r, "mutating")
} else := "high" if {
	not allow
	some r in reasons
	contains(r, "cross-tenant")
} else := "info"

decision := {"allow": allow, "reasons": reasons, "severity": severity}
