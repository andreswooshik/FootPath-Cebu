// Reuses the same public Firebase Web config as footpath_cebu/lib/firebase_options.dart.
// Firebase web API keys are not secret — access is controlled by the backend's
// FirebaseAuthentication + IsAdmin permission, not by hiding this config.
const firebaseConfig = {
  apiKey: 'AIzaSyDgHeJwmqiXuYbjAsi0-jjwF3i6nbfgLyc',
  appId: '1:155194186459:web:02f9e43d070c98fc8ecafe',
  messagingSenderId: '155194186459',
  projectId: 'footpath-cebu',
  authDomain: 'footpath-cebu.firebaseapp.com',
  storageBucket: 'footpath-cebu.firebasestorage.app',
};
firebase.initializeApp(firebaseConfig);

const API_BASE = window.location.origin;

const el = (id) => document.getElementById(id);
const loginSection = el('login-section');
const appSection = el('app-section');

async function apiFetch(path, options = {}) {
  const user = firebase.auth().currentUser;
  if (!user) throw new Error('Not signed in.');
  const token = await user.getIdToken();
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...(options.headers || {}),
    },
  });
  if (!res.ok) {
    let detail = `Request failed (${res.status})`;
    try {
      const body = await res.json();
      detail = body.detail || JSON.stringify(body);
    } catch (_) {}
    throw new Error(detail);
  }
  if (res.status === 204) return null;
  return res.json();
}

async function loadUsers() {
  const users = await apiFetch('/api/admin/users/');
  const tbody = el('users-table-body');
  tbody.innerHTML = '';
  const guardianSelect = el('link-guardian');
  const playerSelect = el('link-player');
  guardianSelect.innerHTML = '';
  playerSelect.innerHTML = '';

  for (const u of users) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${u.email}</td>
      <td>${[u.first_name, u.last_name].filter(Boolean).join(' ') || '—'}</td>
      <td><span class="badge">${u.role_display}</span></td>
    `;
    tbody.appendChild(tr);

    if (u.role === 'GUARDIAN') {
      const opt = new Option(u.email, u.id);
      guardianSelect.add(opt);
    }
    if (u.role === 'PLAYER') {
      const opt = new Option(u.email, u.id);
      playerSelect.add(opt);
    }
  }
}

async function loadLinks() {
  const links = await apiFetch('/api/admin/guardian-links/');
  const tbody = el('links-table-body');
  tbody.innerHTML = '';
  for (const link of links) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${link.guardian.email}</td>
      <td>${link.player.email}</td>
      <td><button data-id="${link.id}" class="secondary unlink-button">Unlink</button></td>
    `;
    tbody.appendChild(tr);
  }
  tbody.querySelectorAll('.unlink-button').forEach((btn) => {
    btn.addEventListener('click', async () => {
      await apiFetch(`/api/admin/guardian-links/${btn.dataset.id}/`, { method: 'DELETE' });
      await loadLinks();
    });
  });
}

async function refreshDashboard() {
  await loadUsers();
  await loadLinks();
}

async function showApp(profile) {
  loginSection.style.display = 'none';
  appSection.style.display = 'block';
  el('current-user-email').textContent = profile.email;
  await refreshDashboard();
}

function showLogin(message) {
  loginSection.style.display = 'block';
  appSection.style.display = 'none';
  el('login-error').textContent = message || '';
}

el('login-button').addEventListener('click', async () => {
  el('login-error').textContent = '';
  try {
    await firebase.auth().signInWithEmailAndPassword(
      el('login-email').value.trim(),
      el('login-password').value
    );
    // onAuthStateChanged below picks up the result.
  } catch (e) {
    el('login-error').textContent = 'Sign-in failed: ' + (e.message || e.code || e);
  }
});

el('signout-button').addEventListener('click', () => firebase.auth().signOut());

el('create-user-button').addEventListener('click', async () => {
  el('create-user-error').textContent = '';
  el('create-user-result').style.display = 'none';
  try {
    const payload = {
      email: el('create-email').value.trim(),
      first_name: el('create-first-name').value.trim(),
      last_name: el('create-last-name').value.trim(),
      role: el('create-role').value,
    };
    const result = await apiFetch('/api/admin/users/', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    const box = el('create-user-result');
    box.style.display = 'block';
    if (result.temporary_password) {
      box.innerHTML = `Account created for <strong>${result.user.email}</strong>. Temporary password (shown once): <code>${result.temporary_password}</code>`;
    } else {
      box.innerHTML = `Account created for <strong>${result.user.email}</strong>. ${result.note}`;
    }
    el('create-email').value = '';
    el('create-first-name').value = '';
    el('create-last-name').value = '';
    await loadUsers();
  } catch (e) {
    el('create-user-error').textContent = e.message;
  }
});

el('link-button').addEventListener('click', async () => {
  el('link-error').textContent = '';
  try {
    const guardianId = el('link-guardian').value;
    const playerId = el('link-player').value;
    if (!guardianId || !playerId) {
      el('link-error').textContent = 'Select both a guardian and a player.';
      return;
    }
    await apiFetch('/api/admin/guardian-links/', {
      method: 'POST',
      body: JSON.stringify({ guardian_id: guardianId, player_id: playerId }),
    });
    await loadLinks();
  } catch (e) {
    el('link-error').textContent = e.message;
  }
});

firebase.auth().onAuthStateChanged(async (user) => {
  if (!user) {
    showLogin();
    return;
  }
  try {
    const token = await user.getIdToken();
    const res = await fetch(`${API_BASE}/api/auth/me/`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      await firebase.auth().signOut();
      showLogin('Access denied. Admin accounts only.');
      return;
    }
    const profile = await res.json();
    if (profile.role !== 'ADMIN') {
      await firebase.auth().signOut();
      showLogin('Access denied. Admin accounts only.');
      return;
    }
    await showApp(profile);
  } catch (e) {
    await firebase.auth().signOut();
    showLogin('Could not verify session: ' + e.message);
  }
});
