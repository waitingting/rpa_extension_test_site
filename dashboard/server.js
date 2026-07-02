const childProcess = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const root = path.resolve(__dirname, '..');
const publicDir = path.join(__dirname, 'public');

const config = {
  port: Number(process.env.RPA_TEST_DASHBOARD_PORT || 8787),
  rpadRepo: process.env.RPAD_REPO || 'C:\\workspace\\rpad',
  extensionRepo: process.env.RPAD_EXTENSION_REPO || 'C:\\workspace\\web_extension_unified',
  extensionBuild: process.env.RPAD_EXTENSION_BUILD || 'C:\\workspace\\web_extension_unified\\build-mv3-rpad-e2e-3',
  vmHost: process.env.RPA_VM_HOST || '192.168.150.129',
  vmUser: process.env.RPA_VM_USER || 'wpwor',
  vmPassword: process.env.RPA_VM_PASSWORD || '1',
  qihu360Path: process.env.RPA_QIHU360_PATH || 'C:\\Users\\wpwor\\AppData\\Roaming\\360se6\\Application\\360se.exe'
};

const runs = [];
let activeRun = null;
let nextRunId = 1;

function psQuote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function createPowerShellCommand(command) {
  return {
    file: 'powershell.exe',
    args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command]
  };
}

function createCmdCommand(command) {
  return {
    file: 'cmd.exe',
    args: ['/d', '/s', '/c', command]
  };
}

function localExe(relativePath, extra = '') {
  const exe = path.join(config.rpadRepo, relativePath);
  return createPowerShellCommand(`& ${psQuote(exe)} ${extra}`.trim());
}

function vmStartCommand(extraArgs = []) {
  const script = path.join(root, 'labs\\vmware_browser_lab\\start-desktop-tests.ps1');
  const args = [
    '-ComputerName', psQuote(config.vmHost),
    '-UserName', psQuote(config.vmUser),
    '-Password', psQuote(config.vmPassword),
    '-TestSiteRepo', psQuote(root),
    '-RpadRepo', psQuote(config.rpadRepo),
    '-ExtensionRepo', psQuote(config.extensionRepo),
    '-ExtensionBuild', psQuote(config.extensionBuild),
    '-ExtensionId', "''",
    '-Qihu360Path', psQuote(config.qihu360Path),
    ...extraArgs
  ];
  return createPowerShellCommand(`& ${psQuote(script)} ${args.join(' ')}`);
}

const testDefinitions = [
  {
    id: 'local_chrome_unit',
    group: 'local',
    name: 'Chrome Provider Unit',
    description: '运行 chrome_unit_test.exe，覆盖 provider 工具函数、窗口 id、坐标、协议解析等单元测试。',
    command: () => localExe('build\\src\\providers\\chrome\\test\\chrome_unit_test.exe')
  },
  {
    id: 'local_browser_manager_unit',
    group: 'local',
    name: 'Browser Manager Unit',
    description: '运行 browser_manager_unit_test.exe，覆盖插件安装管理、native host JSON、Preferences 修改逻辑。',
    command: () => localExe('build\\src\\features\\browser_extension\\manager\\browser_manager_unit_test.exe')
  },
  {
    id: 'local_fixture',
    group: 'local',
    name: 'Fixture Site Functional',
    description: '本机运行 fixture-site.spec.js，验证测试站点、表单控件、同源/跨源 frame。',
    command: () => createCmdCommand('npx playwright test fixture-site.spec.js --reporter=line')
  },
  {
    id: 'local_browser_smoke',
    group: 'local',
    name: 'Browser Click/Input Smoke',
    description: '本机运行 browser-smoke.spec.js，验证 Chromium/Firefox 点击与输入自动化。',
    command: () => createCmdCommand('npx playwright test browser-smoke.spec.js --reporter=line')
  },
  {
    id: 'local_extension_smoke',
    group: 'local',
    name: 'Unpacked Extension Smoke',
    description: '本机加载插件构建目录，验证 unpacked extension 可启动并访问 options 页面。',
    env: { RPAD_EXTENSION_BUILD: config.extensionBuild },
    command: () => createCmdCommand('npx playwright test rpad-extension-smoke.spec.js --reporter=line')
  },
  {
    id: 'vm_full',
    group: 'vm',
    name: 'VM Full Regression',
    description: 'VM 完整回归：单元测试、fixture、Chrome/Firefox/360、插件加载、安装验证、ChromeScenario、CaptureAuto。',
    vm: true,
    command: () => vmStartCommand(['-Include360Smoke'])
  },
  {
    id: 'vm_units',
    group: 'vm',
    name: 'VM Unit Tests Only',
    description: '只在 VM 执行 chrome_unit_test 与 browser_manager_unit_test。',
    vm: true,
    command: () => vmStartCommand(['-SkipBrowserSmoke', '-SkipExtensionSmoke', '-SkipProviderAutoCapture'])
  },
  {
    id: 'vm_browser_smoke',
    group: 'vm',
    name: 'VM Browser Smoke',
    description: 'VM 执行 fixture、Chromium/Firefox 点击输入、360 原生鼠标键盘 smoke。',
    vm: true,
    command: () => vmStartCommand(['-Include360Smoke', '-SkipProviderUnit', '-SkipBrowserManagerUnit', '-SkipExtensionSmoke', '-SkipProviderAutoCapture'])
  },
  {
    id: 'vm_extension_smoke',
    group: 'vm',
    name: 'VM Extension Smoke',
    description: 'VM 执行 fixture、浏览器 smoke 和 unpacked extension 加载 smoke。',
    vm: true,
    command: () => vmStartCommand(['-SkipProviderUnit', '-SkipBrowserManagerUnit', '-SkipProviderAutoCapture'])
  },
  {
    id: 'vm_provider_capture',
    group: 'vm',
    name: 'VM Provider Scenario + Capture',
    description: 'VM 执行 browser_manager 安装验证、ChromeScenario.* 和 Chrome.CaptureAuto。',
    vm: true,
    command: () => vmStartCommand(['-SkipProviderUnit', '-SkipBrowserManagerUnit', '-SkipBrowserSmoke', '-SkipExtensionSmoke'])
  }
];

function publicTests() {
  return testDefinitions.map(({ id, group, name, description, vm }) => ({
    id,
    group,
    name,
    description,
    vm: Boolean(vm)
  }));
}

function append(run, text) {
  if (!text) {
    return;
  }
  run.output += text;
  run.updatedAt = new Date().toISOString();
}

function summarizeRun(run) {
  return {
    id: run.id,
    testId: run.testId,
    testName: run.testName,
    status: run.status,
    exitCode: run.exitCode,
    startedAt: run.startedAt,
    updatedAt: run.updatedAt,
    finishedAt: run.finishedAt,
    vmLogPath: run.vmLogPath || '',
    error: run.error || ''
  };
}

function startRun(testId) {
  if (activeRun && activeRun.status === 'running') {
    const error = new Error('已有测试正在运行，请等待结束后再启动新的测试。');
    error.statusCode = 409;
    throw error;
  }

  const definition = testDefinitions.find((test) => test.id === testId);
  if (!definition) {
    const error = new Error(`未知测试: ${testId}`);
    error.statusCode = 404;
    throw error;
  }

  const run = {
    id: nextRunId++,
    testId,
    testName: definition.name,
    status: 'running',
    exitCode: null,
    output: '',
    vmOutput: '',
    vmLogPath: '',
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    finishedAt: null,
    error: '',
    vm: Boolean(definition.vm)
  };
  runs.unshift(run);
  activeRun = run;

  const command = definition.command();
  const env = {
    ...process.env,
    RPAD_EXTENSION_BUILD: config.extensionBuild,
    ...(definition.env || {})
  };

  append(run, `$ ${command.file} ${command.args.join(' ')}\n\n`);

  const child = childProcess.spawn(command.file, command.args, {
    cwd: root,
    env,
    windowsHide: true
  });

  run.child = child;
  child.stdout.on('data', (chunk) => append(run, chunk.toString()));
  child.stderr.on('data', (chunk) => append(run, chunk.toString()));
  child.on('error', (error) => {
    run.status = 'failed';
    run.error = error.message;
    append(run, `\n[dashboard] failed to start: ${error.message}\n`);
    finishRun(run, null);
  });
  child.on('close', (code) => {
    append(run, `\n[dashboard] launcher exited with code ${code}\n`);
    if (run.vm && code === 0) {
      run.status = 'running';
      pollVmUntilDone(run);
      return;
    }
    run.status = code === 0 ? 'passed' : 'failed';
    finishRun(run, code);
  });

  return summarizeRun(run);
}

function finishRun(run, code) {
  run.exitCode = code;
  run.finishedAt = new Date().toISOString();
  run.updatedAt = run.finishedAt;
  if (activeRun && activeRun.id === run.id) {
    activeRun = null;
  }
}

function pollVmUntilDone(run) {
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    fetchVmStatus((error, result) => {
      if (error) {
        run.error = error.message;
        append(run, `\n[dashboard] VM poll error: ${error.message}\n`);
        if (attempts >= 3) {
          clearInterval(timer);
          run.status = 'failed';
          finishRun(run, 1);
        }
        return;
      }

      run.vmLogPath = result.log || run.vmLogPath;
      run.vmOutput = result.tail || run.vmOutput;
      run.updatedAt = new Date().toISOString();

      const taskResult = Number(result.lastTaskResult);
      const completed = /Desktop tests completed\./.test(run.vmOutput);
      if (completed && taskResult === 0) {
        clearInterval(timer);
        run.status = 'passed';
        finishRun(run, 0);
        return;
      }
      if (taskResult !== 267009 && taskResult !== 0 && attempts > 2) {
        clearInterval(timer);
        run.status = 'failed';
        finishRun(run, taskResult || 1);
      }
      if (attempts > 240) {
        clearInterval(timer);
        run.status = 'failed';
        run.error = 'VM 测试轮询超时。';
        finishRun(run, 1);
      }
    });
  }, 5000);
}

function fetchVmStatus(callback) {
  const script = `
$secure = ConvertTo-SecureString ${psQuote(config.vmPassword)} -AsPlainText -Force
$cred = [pscredential]::new(${psQuote(`${config.vmHost}\\${config.vmUser}`)}, $secure)
Invoke-Command -ComputerName ${psQuote(config.vmHost)} -Credential $cred -Authentication Negotiate -ScriptBlock {
  $task = Get-ScheduledTaskInfo -TaskName 'RpadBrowserDesktopTests' -ErrorAction SilentlyContinue
  $latest = Get-ChildItem C:\\browser-e2e\\logs -Filter 'desktop-tests-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  [pscustomobject]@{
    lastTaskResult = if ($task) { $task.LastTaskResult } else { -1 }
    lastRunTime = if ($task) { $task.LastRunTime.ToString('s') } else { '' }
    log = if ($latest) { $latest.FullName } else { '' }
    tail = if ($latest) { (Get-Content -LiteralPath $latest.FullName -Tail 500) -join [Environment]::NewLine } else { '' }
  } | ConvertTo-Json -Compress
}
`;
  childProcess.execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], {
    cwd: root,
    windowsHide: true,
    maxBuffer: 1024 * 1024 * 5
  }, (error, stdout, stderr) => {
    if (error) {
      callback(new Error(`${error.message}${stderr ? `\n${stderr}` : ''}`));
      return;
    }
    try {
      const line = stdout.trim().split(/\r?\n/).filter(Boolean).pop() || '{}';
      callback(null, JSON.parse(line));
    } catch (parseError) {
      callback(new Error(`解析 VM 状态失败: ${parseError.message}\n${stdout}`));
    }
  });
}

function sendJson(response, status, body) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  response.end(JSON.stringify(body));
}

function readBody(request, callback) {
  let body = '';
  request.on('data', (chunk) => {
    body += chunk;
    if (body.length > 1024 * 1024) {
      request.destroy();
    }
  });
  request.on('end', () => {
    try {
      callback(null, body ? JSON.parse(body) : {});
    } catch (error) {
      callback(error);
    }
  });
}

function serveStatic(request, response) {
  const parsed = url.parse(request.url);
  const pathname = decodeURIComponent(parsed.pathname === '/' ? '/index.html' : parsed.pathname);
  const filePath = path.normalize(path.join(publicDir, pathname));
  if (!filePath.startsWith(publicDir)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const type = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8'
    }[ext] || 'application/octet-stream';
    response.writeHead(200, { 'content-type': type });
    response.end(data);
  });
}

const server = http.createServer((request, response) => {
  const parsed = url.parse(request.url, true);

  if (request.method === 'GET' && parsed.pathname === '/api/tests') {
    sendJson(response, 200, { tests: publicTests(), config });
    return;
  }

  if (request.method === 'GET' && parsed.pathname === '/api/runs') {
    sendJson(response, 200, { runs: runs.slice(0, 20).map(summarizeRun), activeRunId: activeRun ? activeRun.id : null });
    return;
  }

  if (request.method === 'POST' && parsed.pathname === '/api/runs') {
    readBody(request, (error, body) => {
      if (error) {
        sendJson(response, 400, { error: error.message });
        return;
      }
      try {
        sendJson(response, 201, { run: startRun(body.testId) });
      } catch (startError) {
        sendJson(response, startError.statusCode || 500, { error: startError.message });
      }
    });
    return;
  }

  const logMatch = parsed.pathname.match(/^\/api\/runs\/(\d+)\/log$/);
  if (request.method === 'GET' && logMatch) {
    const run = runs.find((item) => item.id === Number(logMatch[1]));
    if (!run) {
      sendJson(response, 404, { error: 'run not found' });
      return;
    }
    sendJson(response, 200, {
      run: summarizeRun(run),
      log: `${run.output}${run.vmOutput ? `\n\n--- VM LOG: ${run.vmLogPath || 'latest'} ---\n${run.vmOutput}` : ''}`
    });
    return;
  }

  serveStatic(request, response);
});

server.listen(config.port, '127.0.0.1', () => {
  console.log(`RPA test dashboard: http://127.0.0.1:${config.port}`);
});
