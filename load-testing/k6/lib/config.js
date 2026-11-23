// Shared configuration for all REMS k6 scenarios.
// Capacity baseline (documentation/05-capacity-plan.md):
//   50 M events/day = 579 events/s average, ingested in batches of 40 -> ~15 ingest requests/s
//   + ~150 user-facing API requests/s at 100 tenants (assumption A5)
//   => ~165 requests/s average. Peak = 5x (825 req/s). Review scenario spike = 10x (1650 req/s) within 5 minutes.

export const BASE_URL = __ENV.BASE_URL || 'https://app.staging.rems.example.com';
export const ACCESS_TOKEN = __ENV.ACCESS_TOKEN || '';
export const BASE_RPS = Number(__ENV.BASE_RPS || 165);
export const DURATION = __ENV.DURATION || '30m';

// Endpoint catalogue (PLACEHOLDER routes until the OpenAPI spec is available).
export const ENDPOINTS = JSON.parse(open(__ENV.ENDPOINTS || '../../config/endpoints.example.json'));

export function headers(extra) {
  const h = {
    'Content-Type': 'application/json',
    'User-Agent': 'rems-k6-loadtest',
    'X-Load-Test': 'true', // lets WAF/analytics exclude synthetic traffic
  };
  if (ACCESS_TOKEN) {
    h.Authorization = `Bearer ${ACCESS_TOKEN}`; // synthetic test tenant only - never a real tenant
  }
  return Object.assign(h, extra || {});
}

// SLO-aligned thresholds (monitoring/slo/slos.md). abortOnFail stops a run that is clearly breaking the system.
export const API_THRESHOLDS = {
  http_req_failed: [{ threshold: 'rate<0.005', abortOnFail: true, delayAbortEval: '2m' }],
  'http_req_duration{type:read}': ['p(95)<300', 'p(99)<500'],
  'http_req_duration{type:write}': ['p(95)<500', 'p(99)<1000'],
  checks: ['rate>0.995'],
};

export function rps(multiplier) {
  return Math.ceil(BASE_RPS * multiplier);
}

// Pre-allocated VUs: rate x expected p99 latency (s) x safety factor.
export function vusFor(rate, p99Seconds = 0.5) {
  return Math.max(20, Math.ceil(rate * p99Seconds * 2));
}
