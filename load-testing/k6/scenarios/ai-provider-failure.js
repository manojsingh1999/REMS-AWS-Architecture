// Scenario 5 - AI provider unavailable / rate limiting.
// Run together with load-testing/chaos/run-chaos.sh ai-provider (Bedrock VPC endpoint policy deny for 10 min,
// then the LLM gateway scaled to zero). Expected: phase 1 -> fallback provider (latency up, no errors);
// phase 2 -> degraded non-LLM answers (X-Rems-Degraded), never 5xx storms; core API unaffected.
import { apiMix, chatMessage } from '../lib/requests.js';
import { rps, vusFor } from '../lib/config.js';

export const options = {
  scenarios: {
    chat: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.CHAT_RPS || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '30m',
      preAllocatedVUs: 200,
      maxVUs: 600,
      exec: 'chat',
    },
    api: {
      executor: 'constant-arrival-rate',
      rate: rps(1),
      timeUnit: '1s',
      duration: __ENV.DURATION || '30m',
      preAllocatedVUs: vusFor(rps(1)),
      exec: 'api',
    },
  },
  thresholds: {
    'http_req_failed{scenario:api}': ['rate<0.005'], // blast radius contained to AI features
    'checks{scenario:chat}': ['rate>0.95'],
    rems_chat_latency: ['p(95)<30000'],
  },
  tags: { scenario_group: 'ai-provider-failure' },
};

export function chat() {
  chatMessage();
}

export function api() {
  apiMix();
}
