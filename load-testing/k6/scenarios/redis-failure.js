// Scenario 6 - Redis/Valkey primary failure. Run with: load-testing/chaos/run-chaos.sh redis
// (aws elasticache test-failover on one shard, then FIS AZ power interruption of the cache).
// Expected: brief latency increase (cache misses fall through to Postgres), error rate < 1 %,
// full recovery within ~2 min of replica promotion; no pod restarts.
import { apiMix } from '../lib/requests.js';
import { rps, vusFor } from '../lib/config.js';

const RATE = rps(2);

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '20m',
      preAllocatedVUs: vusFor(RATE, 1),
      maxVUs: vusFor(RATE, 1) * 2,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{type:read}': ['p(95)<600'],
  },
  tags: { scenario_group: 'redis-failure' },
};

export default function () {
  apiMix();
}
