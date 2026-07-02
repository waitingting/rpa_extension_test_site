let selectedTestId = '';
let selectedRunId = null;
let tests = [];
let pollTimer = null;

const testList = document.getElementById('testList');
const runButton = document.getElementById('runButton');
const refreshButton = document.getElementById('refreshButton');
const logOutput = document.getElementById('logOutput');
const runTitle = document.getElementById('runTitle');
const runMeta = document.getElementById('runMeta');
const activeState = document.getElementById('activeState');
const envLine = document.getElementById('envLine');

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'content-type': 'application/json' },
    ...options
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body.error || response.statusText);
  }
  return body;
}

function renderTests() {
  const groups = [
    ['local', 'Local'],
    ['vm', 'VMware VM']
  ];
  testList.innerHTML = '';
  for (const [groupId, groupName] of groups) {
    const groupTests = tests.filter((test) => test.group === groupId);
    if (!groupTests.length) {
      continue;
    }
    const label = document.createElement('div');
    label.className = 'group-label';
    label.textContent = groupName;
    testList.appendChild(label);

    for (const test of groupTests) {
      const item = document.createElement('button');
      item.type = 'button';
      item.className = `test-item${test.id === selectedTestId ? ' selected' : ''}`;
      item.innerHTML = `<strong>${escapeHtml(test.name)}</strong><span>${escapeHtml(test.description)}</span>`;
      item.addEventListener('click', () => {
        selectedTestId = test.id;
        runButton.disabled = false;
        renderTests();
      });
      testList.appendChild(item);
    }
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function statusText(status) {
  if (status === 'running') return 'Running';
  if (status === 'passed') return 'Passed';
  if (status === 'failed') return 'Failed';
  return 'Idle';
}

async function refreshRuns() {
  const data = await api('/api/runs');
  const activeRun = data.runs.find((run) => run.id === data.activeRunId);
  activeState.textContent = activeRun ? `Running #${activeRun.id}` : 'Idle';
  if (!selectedRunId && data.runs.length) {
    selectedRunId = data.runs[0].id;
  }
  if (selectedRunId) {
    await loadLog(selectedRunId);
  }
}

async function loadLog(runId) {
  const data = await api(`/api/runs/${runId}/log`);
  const run = data.run;
  runTitle.textContent = `#${run.id} ${run.testName}`;
  const pieces = [statusText(run.status), run.startedAt];
  if (run.vmLogPath) pieces.push(run.vmLogPath);
  if (run.error) pieces.push(run.error);
  runMeta.textContent = pieces.join(' | ');
  logOutput.textContent = data.log || '等待输出...';
  logOutput.scrollTop = logOutput.scrollHeight;
}

async function startSelectedRun() {
  if (!selectedTestId) {
    return;
  }
  runButton.disabled = true;
  try {
    const data = await api('/api/runs', {
      method: 'POST',
      body: JSON.stringify({ testId: selectedTestId })
    });
    selectedRunId = data.run.id;
    await loadLog(selectedRunId);
  } catch (error) {
    logOutput.textContent = error.message;
  } finally {
    runButton.disabled = false;
  }
}

async function boot() {
  const data = await api('/api/tests');
  tests = data.tests;
  envLine.textContent = `Rpad: ${data.config.rpadRepo} | VM: ${data.config.vmHost} | Extension: ${data.config.extensionBuild}`;
  renderTests();
  await refreshRuns();
  pollTimer = setInterval(refreshRuns, 2500);
}

runButton.addEventListener('click', startSelectedRun);
refreshButton.addEventListener('click', refreshRuns);

window.addEventListener('beforeunload', () => {
  if (pollTimer) clearInterval(pollTimer);
});

boot().catch((error) => {
  logOutput.textContent = error.stack || error.message;
});
