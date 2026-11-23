// Scenario 2 - 5x peak (PDF: peak incoming event rate = 5x average).
// Ramp 1x -> 5x over 10 min, hold 30 min, ramp down. Verifies HPA/KEDA + Karpenter keep SLOs at sustained peak.
import { apiMix } from '../lib/requests.js';
import { API_THRESHOLDS, rps, vusFor } from '../lib/config.js';

const PEAK = rps(5);

export const options = {
  scenarios: {
    peak: {
      executor: 'ramping-arrival-rate',
      startRate: rps(1),
      timeUnit: '1s',
      preAllocatedVUs: vusFor(PEAK),
      maxVUs: vusFor(PEAK) * 2,
      stages: [
        { target: rps(1), duration: '5m' },
        { target: PEAK, duration: '10m' },
        { target: PEAK, duration: '30m' },
        { target: rps(1), duration: '5m' },
      ],
    },
  },
  thresholds: API_THRESHOLDS,
  tags: { scenario_group: 'peak-5x' },
};

export default function () {
  apiMix();
}
