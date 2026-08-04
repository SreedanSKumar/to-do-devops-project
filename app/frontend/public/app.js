const BACKEND_URL = window.BACKEND_URL || '';

const statusEl = document.getElementById('status');
const statusDot = document.getElementById('statusDot');
const statusLabel = document.getElementById('statusLabel');
const composer = document.getElementById('composer');
const taskInput = document.getElementById('taskInput');
const taskList = document.getElementById('taskList');
const statsEl = document.getElementById('stats');
const emptyState = document.getElementById('emptyState');

function setStatus(state, label) {
  statusEl.className = `status status--${state}`;
  statusLabel.textContent = label;
}

async function checkHealth() {
  try {
    const start = performance.now();
    const res = await fetch(`${BACKEND_URL}/api/health`, { cache: 'no-store' });
    const ms = Math.round(performance.now() - start);
    if (res.ok) setStatus('ok', `backend healthy · ${ms}ms`);
    else setStatus('down', `backend returned ${res.status}`);
  } catch (err) {
    setStatus('down', 'backend unreachable');
  }
}

function timeAgo(iso) {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.round(diffMs / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function renderTasks(tasks) {
  taskList.innerHTML = '';
  emptyState.hidden = tasks.length > 0;

  const done = tasks.filter(t => t.done).length;
  statsEl.innerHTML = `<span><strong>${tasks.length}</strong> total</span><span><strong>${done}</strong> done</span><span><strong>${tasks.length - done}</strong> open</span>`;

  for (const task of tasks) {
    const li = document.createElement('li');
    li.className = `task${task.done ? ' task--done' : ''}`;
    li.innerHTML = `
      <button class="task__check" aria-label="toggle done">${task.done ? '✓' : ''}</button>
      <span class="task__text"></span>
      <span class="task__time">${timeAgo(task.createdAt)}</span>
      <button class="task__delete" aria-label="delete task">&times;</button>
    `;
    li.querySelector('.task__text').textContent = task.text;
    li.querySelector('.task__check').addEventListener('click', () => toggleTask(task.id, !task.done));
    li.querySelector('.task__delete').addEventListener('click', () => deleteTask(task.id));
    taskList.appendChild(li);
  }
}

async function loadTasks() {
  try {
    const res = await fetch(`${BACKEND_URL}/api/tasks`);
    const tasks = await res.json();
    renderTasks(tasks);
  } catch (err) {
    emptyState.hidden = false;
    emptyState.textContent = 'could not load tasks — is the backend running?';
  }
}

async function addTask(text) {
  await fetch(`${BACKEND_URL}/api/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text })
  });
  loadTasks();
}

async function toggleTask(id, done) {
  await fetch(`${BACKEND_URL}/api/tasks/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ done })
  });
  loadTasks();
}

async function deleteTask(id) {
  await fetch(`${BACKEND_URL}/api/tasks/${id}`, { method: 'DELETE' });
  loadTasks();
}

composer.addEventListener('submit', (e) => {
  e.preventDefault();
  const text = taskInput.value.trim();
  if (!text) return;
  taskInput.value = '';
  addTask(text);
});

checkHealth();
loadTasks();
setInterval(checkHealth, 15000);
