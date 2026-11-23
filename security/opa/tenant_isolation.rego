# REMS tenant isolation policy, evaluated by the Authorization Service (embedded OPA / sidecar).
#
# input = {
#   "subject":  {"id": "u-1", "tenant_id": "t-1", "roles": ["incident-viewer"], "token_tenant_verified": true},
#   "action":   "read" | "create" | "update" | "delete" | "execute",
#   "resource": {"type": "incident" | "rca" | "alert" | "sop" | "dashboard" | ..., "tenant_id": "t-1", "id": "..."}
# }
# Decision: data.rems.authz.decision -> {"allow": bool, "reasons": [...]}
package rems.authz

import rego.v1

default allow := false

# Role -> permitted actions per resource type (RBAC). Tenants can only be granted these roles.
role_permissions := {
	"tenant-admin": {"*": {"read", "create", "update", "delete", "execute"}},
	"sre": {
		"incident": {"read", "create", "update"},
		"alert": {"read", "update"},
		"rca": {"read", "create", "execute"},
		"sop": {"read", "create", "update"},
		"dashboard": {"read", "create", "update"},
		"chat": {"execute"},
	},
	"incident-viewer": {
		"incident": {"read"},
		"alert": {"read"},
		"rca": {"read"},
		"dashboard": {"read"},
	},
	"governance-officer": {
		"governance-policy": {"read", "create", "update"},
		"scan": {"read", "execute"},
	},
}

# Platform operators (REMS staff) are not a tenant role; they may read only support metadata, never tenant data.
platform_readable := {"tenant-metadata", "usage"}

same_tenant if {
	input.subject.token_tenant_verified == true
	input.subject.tenant_id != ""
	input.subject.tenant_id == input.resource.tenant_id
}

role_allows(role) if {
	perms := role_permissions[role]
	input.action in perms[input.resource.type]
}

role_allows(role) if {
	perms := role_permissions[role]
	input.action in perms["*"]
}

allow if {
	same_tenant
	some role in input.subject.roles
	role_allows(role)
}

allow if {
	"platform-operator" in input.subject.roles
	input.action == "read"
	input.resource.type in platform_readable
}

reasons contains "cross-tenant access denied" if {
	not same_tenant
	not "platform-operator" in input.subject.roles
}

reasons contains "tenant claim not verified" if {
	input.subject.token_tenant_verified != true
}

reasons contains sprintf("no role grants %s on %s", [input.action, input.resource.type]) if {
	same_tenant
	not allow
}

decision := {"allow": allow, "reasons": reasons}
