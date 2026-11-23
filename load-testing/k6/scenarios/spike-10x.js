// Scenario 3 - review scenario: REMS API traffic increases 10x within five minutes.
// Expected behaviour: overprovisioning pause pods are preempted instantly, KEDA scales on RPS within
// ~30 s, Karpenter adds nodes in ~60 s, WAF per-IP limits protect from a single abusive source.
// Pass: error rate < 1 % overall, p95 < 800 ms during the ramp, back under 300 ms within 5 min of plateau.
import { apiMix } from '../lib/requests.js';
import { rps, vusFor } from '../lib/config.js';

const SPIKE = rps(10);

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: rps(1),
      timeUnit: '1s',
      preAllocatedVUs: vusFor(SPIKE),
      maxVUs: vusFor(SPIKE) * 2,
      stages: [
        { target: rps(1), duration: '5m' }, // baseline
        { target: SPIKE, duration: '5m' }, // 10x within five minutes
        { target: SPIKE, duration: '15m' }, // plateau: system must converge
        { target: rps(1), duration: '5m' }, // recovery / scale-in
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{type:read}': ['p(95)<800'],
    checks: ['rate>0.99'],
  },
  tags: { scenario_group: 'spike-10x' },
};

export default function () {
  apiMix();
}
