// Dynamic API URL configuration - use same origin for both frontend and API
const API_URL = window.location.origin;

let pollAttempts = 0;
let pollDelay = 2000; // Start at 2 seconds

// Helper function to safely escape HTML
function escapeHtml(text) {
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  };
  return text.replace(/[&<>"']/g, m => map[m]);
}

async function checkHealth() {
  try {
    const response = await fetch(`${API_URL}/health`, { mode: 'cors' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    alert(`✅ API is healthy!\n\nUptime: ${data.uptime.toFixed(2)} seconds`);
  } catch (error) {
    alert(`❌ API is not responding\nError: ${error.message}`);
  }
}

async function viewMetrics() {
  window.open(`${API_URL}/metrics`, '_blank');
}

async function viewData() {
  try {
    const response = await fetch(`${API_URL}/api/data`, { mode: 'cors' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    alert('📊 Data:\n\n' + JSON.stringify(data, null, 2));
  } catch (error) {
    alert(`❌ Could not fetch data\nError: ${error.message}`);
  }
}

async function updateStatus() {
  try {
    const response = await fetch(`${API_URL}/api/status`, { mode: 'cors', timeout: 5000 });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();

    // Reset error tracking on success
    pollAttempts = 0;
    pollDelay = 2000;

    // Update cards
    document.getElementById('api-status').textContent = '✓';
    document.getElementById('uptime').textContent = data.uptime.toFixed(1) + 's';
    document.getElementById('memory').textContent = (data.memory.heapUsed / 1024 / 1024).toFixed(1) + ' MB';

    // Safely escape and update info list
    const infoHtml = `
      <li><span>Hostname</span><span>${escapeHtml(data.hostname || 'N/A')}</span></li>
      <li><span>Platform</span><span>${escapeHtml(data.platform || 'N/A')}</span></li>
      <li><span>Node Version</span><span>${escapeHtml(data.nodeVersion || 'N/A')}</span></li>
      <li><span>Last Update</span><span>${new Date().toLocaleTimeString()}</span></li>
    `;
    document.getElementById('system-info').innerHTML = infoHtml;
  } catch (error) {
    pollAttempts++;

    // Exponential backoff: 2s, 4s, 8s, 16s (max)
    pollDelay = Math.min(2000 * Math.pow(2, pollAttempts - 1), 16000);

    document.getElementById('api-status').textContent = '✗';
    document.getElementById('system-info').innerHTML = `<li><span>Status</span><span>Reconnecting (attempt ${pollAttempts})...</span></li>`;
  }
}

// Start polling with dynamic intervals
let pollInterval;
function startPolling() {
  updateStatus();
  pollInterval = setInterval(updateStatus, pollDelay);
}

startPolling();

// Attach button event listeners
document.getElementById('btn-health').addEventListener('click', checkHealth);
document.getElementById('btn-metrics').addEventListener('click', viewMetrics);
document.getElementById('btn-data').addEventListener('click', viewData);

// Pause polling when tab is hidden, resume when visible
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    clearInterval(pollInterval);
  } else {
    startPolling();
  }
});
