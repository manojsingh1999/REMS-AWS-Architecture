import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { BASE_URL, ENDPOINTS, headers } from './config.js';

export const degradedResponses = new Counter('rems_degraded_responses');
export const chatLatency = new Trend('rems_chat_latency', true);

function pickWeighted(list) {
  const total = list.reduce((s, e) => s + e.weight, 0);
  let r = Math.random() * total;
  for (const e of list) {
    r -= e.weight;
    if (r <= 0) {
      return e;
    }
  }
  return list[list.length - 1];
}

function eventBatch(size) {
  const now = new Date().toISOString();
  const events = [];
  for (let i = 0; i < size; i += 1) {
    events.push({
      // Synthetic event body - PLACEHOLDER schema until the ingest API contract is confirmed.
      timestamp: now,
      source: 'k6',
      severity: ['info', 'warning', 'critical'][i % 3],
      message: `synthetic load-test event ${__VU}-${__ITER}-${i}`,
    });
  }
  return JSON.stringify({ events });
}

function call(ep, type, body) {
  const params = { headers: headers(), tags: { name: ep.name, type }, timeout: type === 'ai' ? '120s' : '30s' };
  const url = `${BASE_URL}${ep.path}`;
  const res = ep.method === 'POST' ? http.post(url, body || '{}', params) : http.get(url, params);
  check(res, {
    [`${ep.name} status 2xx`]: (r) => r.status >= 200 && r.status < 300,
  });
  return res;
}

// Mixed user + ingest traffic: 90 % reads, 10 % event batches.
export function apiMix() {
  if (Math.random() < 0.9) {
    return call(pickWeighted(ENDPOINTS.read), 'read');
  }
  const ep = pickWeighted(ENDPOINTS.write);
  return call(ep, 'write', eventBatch(ep.batch_size || 40));
}

export function dbHeavy() {
  return call(pickWeighted(ENDPOINTS.db_heavy), 'read');
}

// AI requests: success OR an explicit degraded answer (provider down -> non-LLM fallback) both count as handled.
export function chatMessage() {
  const res = call(ENDPOINTS.chat, 'ai', JSON.stringify({ message: 'Why did checkout latency increase in the last 30 minutes?' }));
  chatLatency.add(res.timings.duration);
  // PLACEHOLDER contract: services signal degraded mode with this header.
  if (res.headers['X-Rems-Degraded'] === 'true') {
    degradedResponses.add(1);
  }
  check(res, { 'chat not 5xx': (r) => r.status < 500 });
  return res;
}
