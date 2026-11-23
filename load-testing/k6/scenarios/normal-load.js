// Scenario 1 - normal traffic: steady 1x baseline (~165 req/s) for DURATION (default 30m).
// Pass: error rate < 0.5 %, read p95 < 300 ms, no HPA at maxReplicas, Aurora CPU < 50 %.
import { apiMix } from '../lib/requests.js';
import { API_THRESHOLDS, DURATION, rps, vusFor } from '../lib/config.js';

const RATE = rps(1);

export const options = {
  scenarios: {
    normal: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: vusFor(RATE),
      maxVUs: vusFor(RATE) * 3,
    },
  },
  thresholds: API_THRESHOLDS,
  tags: { scenario_group: 'normal-load' },
};

export default function () {
  apiMix();
}
