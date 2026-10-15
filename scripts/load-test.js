// Load test for the Poll application (k6).
//
// Usage:
//   POLL=http://<ip> RESULT=http://<ip> \
//   docker run --rm -i -e POLL -e RESULT grafana/k6 run - < scripts/load-test.js
//
// Each virtual user loads the voting page, votes, then loads the result page.
import http from 'k6/http';
import { check, sleep } from 'k6';

const POLL = __ENV.POLL;
const RESULT = __ENV.RESULT;

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],     // less than 1 % errors
    http_req_duration: ['p(95)<500'],   // 95 % of requests under 500 ms
  },
};

export default function () {
  const page = http.get(`${POLL}/`, { tags: { name: 'poll GET' } });
  check(page, { 'poll page 200': (r) => r.status === 200 });

  const choice = ['a', 'b', 'c', 'd'][Math.floor(Math.random() * 4)];
  const vote = http.post(`${POLL}/`, { vote: choice }, { tags: { name: 'poll POST' } });
  check(vote, { 'vote 200': (r) => r.status === 200 });

  const result = http.get(`${RESULT}/`, { tags: { name: 'result GET' } });
  check(result, { 'result page 200': (r) => r.status === 200 });

  sleep(1);
}
