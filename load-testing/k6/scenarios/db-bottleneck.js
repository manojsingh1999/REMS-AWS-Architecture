// Scenario 4 - PostgreSQL as the bottleneck. Step-load DB-heavy endpoints until latency breaks, to find the
// saturation point and verify mitigations: RDS Proxy queueing (no connection storms), reader auto scaling
// (2 -> 5), statement_timeout guardrails, Redis cache hit ratio. Watch the Aurora dashboard + Performance Insights.
// The test aborts itself once p95 > 2 s so it never hurts shared staging for long.
import { apiMix, dbHeavy } from '../lib/requests.js';
import { rps, vusFor } from '../lib/config.js';

const MAX = rps(8);

export const options = {
  scenarios: {
    background: {
      executor: 'constant-arrival-rate',
      rate: rps(1),
      timeUnit: '1s',
      duration: '40m',
      preAllocatedVUs: vusFor(rps(1)),
      exec: 'background',
    },
    db_steps: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: vusFor(MAX, 1),
      maxVUs: vusFor(MAX, 1) * 2,
      stages: [
        { target: rps(1), duration: '5m' },
        { target: rps(2), duration: '5m' },
        { target: rps(4), duration: '10m' },
        { target: MAX, duration: '10m' },
        { target: MAX, duration: '10m' },
      ],
      exec: 'heavy',
    },
  },
  thresholds: {
    'http_req_duration{type:read}': [{ threshold: 'p(95)<2000', abortOnFail: true, delayAbortEval: '1m' }],
    'http_req_failed{scenario:background}': ['rate<0.01'], // user traffic must survive DB pressure
  },
  tags: { scenario_group: 'db-bottleneck' },
};

export function background() {
  apiMix();
}

export function heavy() {
  dbHeavy();
}
