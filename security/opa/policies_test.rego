package rems_test

import rego.v1

import data.rems.authz
import data.rems.mcp

# ---------------------------------------------------------------- tenant isolation
sre_t1 := {"id": "u1", "tenant_id": "t1", "roles": ["sre"], "token_tenant_verified": true}

test_same_tenant_read_allowed if {
	authz.allow with input as {"subject": sre_t1, "action": "read", "resource": {"type": "incident", "tenant_id": "t1"}}
}

test_cross_tenant_read_denied if {
	d := authz.decision with input as {"subject": sre_t1, "action": "read", "resource": {"type": "rca", "tenant_id": "t2"}}
	d.allow == false
	"cross-tenant access denied" in d.reasons
}

test_unverified_tenant_claim_denied if {
	s := object.union(sre_t1, {"token_tenant_verified": false})
	not authz.allow with input as {"subject": s, "action": "read", "resource": {"type": "incident", "tenant_id": "t1"}}
}

test_viewer_cannot_delete if {
	s := object.union(sre_t1, {"roles": ["incident-viewer"]})
	not authz.allow with input as {"subject": s, "action": "delete", "resource": {"type": "incident", "tenant_id": "t1"}}
}

test_tenant_admin_wildcard if {
	s := object.union(sre_t1, {"roles": ["tenant-admin"]})
	authz.allow with input as {"subject": s, "action": "delete", "resource": {"type": "sop", "tenant_id": "t1"}}
}

test_platform_operator_cannot_read_tenant_incidents if {
	s := {"id": "ops", "tenant_id": "", "roles": ["platform-operator"], "token_tenant_verified": true}
	not authz.allow with input as {"subject": s, "action": "read", "resource": {"type": "incident", "tenant_id": "t1"}}
}

# ---------------------------------------------------------------- MCP tools
mcp_subject := object.union(sre_t1, {"scopes": ["mcp/tools.read"]})

test_mcp_read_tool_allowed if {
	mcp.allow with input as {
		"subject": mcp_subject,
		"tool": {"name": "query_logs", "arguments": {"tenant_id": "t1", "time_range_minutes": 60, "limit": 100}},
		"rate": {"calls_last_minute": 3},
	}
}

test_mcp_unknown_mutating_tool_denied_critical if {
	d := mcp.decision with input as {
		"subject": mcp_subject,
		"tool": {"name": "delete_deployment", "arguments": {"tenant_id": "t1"}},
		"rate": {"calls_last_minute": 1},
	}
	d.allow == false
	d.severity == "critical"
}

test_mcp_cross_tenant_denied_high if {
	d := mcp.decision with input as {
		"subject": mcp_subject,
		"tool": {"name": "query_traces", "arguments": {"tenant_id": "t2", "time_range_minutes": 10, "limit": 10}},
		"rate": {"calls_last_minute": 1},
	}
	d.allow == false
	d.severity == "high"
}

test_mcp_limits_enforced if {
	not mcp.allow with input as {
		"subject": mcp_subject,
		"tool": {"name": "query_logs", "arguments": {"tenant_id": "t1", "time_range_minutes": 100000, "limit": 100}},
		"rate": {"calls_last_minute": 1},
	}
}

test_mcp_rate_limited if {
	not mcp.allow with input as {
		"subject": mcp_subject,
		"tool": {"name": "list_alerts", "arguments": {"tenant_id": "t1"}},
		"rate": {"calls_last_minute": 500},
	}
}

test_mcp_scope_required if {
	s := object.union(sre_t1, {"scopes": []})
	not mcp.allow with input as {
		"subject": s,
		"tool": {"name": "list_alerts", "arguments": {"tenant_id": "t1"}},
		"rate": {"calls_last_minute": 1},
	}
}
