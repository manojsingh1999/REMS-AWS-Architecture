// Scenario 7 - single Availability Zone failure. Run with: load-testing/chaos/run-chaos.sh az <az-name>
// (AWS FIS: network disruption of the AZ's subnets + Aurora failover + ElastiCache AZ power interruption
// + termination of EKS nodes in the AZ). Load at 2x baseline so the remaining 2 AZs carry real traffic.
// Pass (99.95 % design): error rate < 0.5 % over the run, p95 < 500 ms after 5 min, no manual action.
import { apiMix } from '../lib/requests.js';
import { rps, vusFor } from '../lib/config.js';

const RATE = rps(2);

export const options = {
  scenarios: {
    az: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '45m',
      preAllocatedVUs: vusFor(RATE, 1),
      maxVUs: vusFor(RATE, 1) * 2,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.005'],
    'http_req_duration{type:read}': ['p(95)<500'],
    checks: ['rate>0.995'],
  },
  tags: { scenario_group: 'az-failure' },
};

export default function () {
  apiMix();
}
