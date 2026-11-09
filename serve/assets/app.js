// Bootstrap Server - Dashboard JavaScript
// ORIGIN will be overridden by server-config.json if BOOTSTRAP_PUBLIC_URL is set
let ORIGIN = window.location.origin;

// Fetch server config to get the correct public URL (critical for remote VMs)
fetch('/server-config.json')
    .then(r => r.json())
    .then(config => {
        if (config.public_url && config.public_url.length > 0) {
            ORIGIN = config.public_url.replace(/\/+$/, ''); // strip trailing slash
        }
        // Warn if using localhost (useless for remote VMs)
        if (ORIGIN.includes('localhost') || ORIGIN.includes('127.0.0.1')) {
            showWarning('You are viewing via localhost. Set BOOTSTRAP_PUBLIC_URL in docker-compose.yml so commands use your LAN IP (e.g. http://192.168.1.50:9090).');
        }
        // Re-render commands with corrected URL
        selectRole(currentRole);
    })
    .catch(() => {
        // No config file, fall back to window.location.origin (fine if user browses by LAN IP)
    });

const ROLES = {
    'vm': { playbook: 'playbooks/vm-setup.yml', extra: '', desc: 'Full VM setup' },
    'lxc-host': { playbook: 'playbooks/lxc-setup.yml', extra: '', desc: 'LXC host configuration' },
    'lxc-container': { playbook: 'playbooks/vm-setup.yml', extra: '', desc: 'Minimal LXC container' },
    'security': { playbook: 'playbooks/security-only.yml', extra: '', desc: 'Security hardening only' },
    'docker': { playbook: 'playbooks/vm-setup.yml', extra: '', desc: 'Docker install only' },
    'minimal': { playbook: 'playbooks/vm-setup.yml', extra: '', desc: 'Base packages only' }
};

let currentRole = 'vm';

function buildCommand(role) {
    const r = ROLES[role];
    return `curl -fS --connect-timeout 10 ${ORIGIN}/bootstrap.sh -o /tmp/bootstrap.sh && sudo bash /tmp/bootstrap.sh --server ${ORIGIN} --role ${role}${r.extra}`;
}

function selectRole(role) {
    currentRole = role;
    document.querySelectorAll('.role-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.role === role);
    });
    document.getElementById('main-command').textContent = buildCommand(role);
    document.getElementById('step0-cmd').textContent =
        `# 0. Test connectivity from the new VM (must succeed first)\ncurl -v ${ORIGIN}/api/health`;
    document.getElementById('step2-cmd').textContent =
        `# 2. Download the bootstrap script\ncurl -fS --connect-timeout 10 ${ORIGIN}/bootstrap.sh -o /tmp/bootstrap.sh`;
    document.getElementById('step3-cmd').textContent =
        `# 3. Run the bootstrap script\nsudo bash /tmp/bootstrap.sh --server ${ORIGIN} --role ${role}`;
}

function copyCommand(elementId) {
    const text = document.getElementById(elementId).textContent;
    navigator.clipboard.writeText(text).then(() => {
        const btn = document.getElementById(elementId).closest('.command-block').querySelector('.copy-btn');
        btn.textContent = '✅ Copied!';
        setTimeout(() => { btn.textContent = '📋 Copy'; }, 2000);
    }).catch(() => {
        // Fallback for non-HTTPS contexts
        const ta = document.createElement('textarea');
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
        const btn = document.getElementById(elementId).closest('.command-block').querySelector('.copy-btn');
        btn.textContent = '✅ Copied!';
        setTimeout(() => { btn.textContent = '📋 Copy'; }, 2000);
    });
}

// Initialize with VM role selected
selectRole('vm');

function showWarning(msg) {
    const banner = document.getElementById('warning-banner');
    document.getElementById('warning-text').textContent = msg;
    banner.style.display = 'flex';
}

// Fetch build info
fetch('/build-info.json')
    .then(r => r.json())
    .then(info => {
        document.getElementById('version-badge').textContent = `${info.git_branch}@${info.git_sha}`;
        document.getElementById('footer-info').textContent =
            `Built: ${info.build_time} | Commit: ${info.git_sha} (${info.git_branch})`;
    })
    .catch(() => {
        document.getElementById('version-badge').textContent = 'dev';
        document.getElementById('footer-info').textContent = 'Development mode — bind-mounted volume';
    });

// Fetch playbook list
fetch('/playbooks-index.json')
    .then(r => r.json())
    .then(data => {
        const list = document.getElementById('playbook-list');
        list.innerHTML = data.playbooks.map(p =>
            `<li><a href="/playbooks/${p}">${p}</a></li>`
        ).join('');
    })
    .catch(() => {
        document.getElementById('playbook-list').innerHTML =
            '<li><a href="/playbooks/site.yml">site.yml</a></li>' +
            '<li><a href="/playbooks/vm-setup.yml">vm-setup.yml</a></li>' +
            '<li><a href="/playbooks/lxc-setup.yml">lxc-setup.yml</a></li>' +
            '<li><a href="/playbooks/security-only.yml">security-only.yml</a></li>';
    });
