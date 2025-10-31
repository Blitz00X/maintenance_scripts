#!/usr/bin/env node
/**
 * Convenience runner so VS Code (F5) can execute the LMS bash script.
 */
const { spawn } = require('child_process');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const lmsScript = path.join(projectRoot, 'lms.sh');
const args = process.argv.slice(2);

const child = spawn('bash', [lmsScript, ...args], {
  cwd: projectRoot,
  stdio: 'inherit',
  env: process.env,
});

child.on('exit', (code, signal) => {
  if (signal) {
    console.error(`LMS terminated by signal: ${signal}`);
    process.exit(1);
  }
  process.exit(code ?? 0);
});

child.on('error', (error) => {
  console.error('Failed to start LMS:', error);
  process.exit(1);
});
