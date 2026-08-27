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

function setButtonBusy(button, busy, busyLabel) {
  if (busy) {
    button.dataset.label = button.textContent;
    button.textContent = busyLabel;
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    return;
  }
  button.textContent = button.dataset.label || button.textContent;
  button.disabled = false;
  button.removeAttribute('aria-busy');
}

function showStatus(message, { error = false, temporaryPassword = '' } = {}) {
  const box = el('global-status');
  box.hidden = false;
  box.classList.toggle('is-error', error);
  box.textContent = message;
  if (temporaryPassword) {
    box.append(' One-time password: ');
    const code = document.createElement('code');
    code.textContent = temporaryPassword;
    box.appendChild(code);
  }
}

function confirmAction(message, confirmLabel = 'Confirm') {
  const dialog = el('confirmation-dialog');
  el('confirmation-message').textContent = message;
  el('confirmation-submit').textContent = confirmLabel;
  dialog.returnValue = '';
  dialog.showModal();
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), {
      once: true,
    });
  });
}

function userLabel(user) {
  const name = [user.first_name, user.last_name].filter(Boolean).join(' ');
  return name || user.email || `Player ${user.id}`;
}

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

// Multipart upload (photos). Does NOT set Content-Type — the browser adds the
// multipart boundary. Same bearer auth as apiFetch.
async function apiUpload(path, formData) {
  const user = firebase.auth().currentUser;
  if (!user) throw new Error('Not signed in.');
  const token = await user.getIdToken();
  const res = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: formData,
  });
  if (!res.ok) {
    let detail = `Upload failed (${res.status})`;
    try {
      const body = await res.json();
      detail = body.detail || JSON.stringify(body);
    } catch (_) {}
    throw new Error(detail);
  }
  return res.json();
}

// Build a table cell with plain text — never innerHTML with server data, so a
// name/email containing markup can't inject script (audit finding F9).
function textCell(text) {
  const td = document.createElement('td');
  td.textContent = text;
  return td;
}

async function loadUsers() {
  const users = await apiFetch('/api/admin/users/');
  const tbody = el('users-table-body');
  tbody.innerHTML = '';
  const guardianSelect = el('link-guardian');
  const playerSelect = el('link-player');
  const playerGuardianSelect = el('player-guardian');
  guardianSelect.innerHTML = '';
  playerSelect.innerHTML = '';
  playerGuardianSelect.innerHTML = '';
  playerGuardianSelect.add(new Option('— none —', ''));

  for (const u of users) {
    const tr = document.createElement('tr');
    tr.dataset.search = [u.email, u.first_name, u.last_name, u.role_display]
      .filter(Boolean).join(' ').toLowerCase();
    tr.dataset.inactive = String(!u.is_active);
    tr.appendChild(textCell(u.email));
    tr.appendChild(
      textCell([u.first_name, u.last_name].filter(Boolean).join(' ') || '—')
    );

    const roleCell = document.createElement('td');
    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = u.role_display;
    roleCell.appendChild(badge);
    tr.appendChild(roleCell);

    // Photo uploader — players only.
    const photoCell = document.createElement('td');
    if (u.role === 'PLAYER') {
      photoCell.appendChild(buildPhotoUploader(u));
    } else {
      photoCell.textContent = '—';
    }
    tr.appendChild(photoCell);

    tr.appendChild(buildUserActions(u));
    tbody.appendChild(tr);

    if (u.role === 'GUARDIAN') {
      guardianSelect.add(new Option(userLabel(u), u.id));
      playerGuardianSelect.add(new Option(userLabel(u), u.id));
    }
    if (u.role === 'PLAYER') {
      playerSelect.add(new Option(userLabel(u), u.id));
    }
  }
  filterUsers();
}

function filterUsers() {
  const query = el('users-search').value.trim().toLowerCase();
  const rows = [...el('users-table-body').querySelectorAll('tr')];
  let visible = 0;
  for (const row of rows) {
    const matches = !query || row.dataset.search.includes(query);
    row.hidden = !matches;
    if (matches) visible += 1;
  }
  el('users-empty').hidden = visible !== 0;
}

async function loadClubs() {
  const clubs = await apiFetch('/api/admin/clubs/');
  const select = el('create-club');
  select.innerHTML = '';
  for (const club of clubs) {
    if (club.is_active) {
      select.add(new Option(`${club.name} (${club.club_type})`, club.id));
    }
  }
}

// Role switcher + activate/deactivate for one user row. Role changes are
// limited to Coach / School Staff / Guardian — the server enforces the same
// rule (players and coordinators are structurally tied to their role).
const SWITCHABLE_ROLES = [
  ['COACH', 'Coach'],
  ['SCHOOL_STAFF', 'School Staff'],
  ['GUARDIAN', 'Guardian'],
];

async function patchUser(id, payload) {
  const result = await apiFetch(`/api/admin/users/${id}/`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
  if (result.temporary_password) {
    showStatus(result.note || 'Account updated.', {
      temporaryPassword: result.temporary_password,
    });
  }
  await loadUsers();
  return result;
}

function buildUserActions(user) {
  const cell = document.createElement('td');
  const switchable = SWITCHABLE_ROLES.some(([value]) => value === user.role);

  if (switchable) {
    const select = document.createElement('select');
    for (const [value, label] of SWITCHABLE_ROLES) {
      select.add(new Option(label, value, false, value === user.role));
    }
    select.addEventListener('change', async () => {
      if (select.value === user.role) return;
      const confirmed = await confirmAction(
        `Change ${user.email} to ${select.options[select.selectedIndex].text}?`,
        'Change role'
      );
      if (!confirmed) {
        select.value = user.role;
        return;
      }
      try {
        const result = await patchUser(user.id, { role: select.value });
        if (!result.temporary_password) showStatus(`${user.email} was updated.`);
      } catch (e) {
        showStatus(e.message || String(e), { error: true });
        select.value = user.role;
      }
    });
    cell.appendChild(select);
  }

  const toggle = document.createElement('button');
  toggle.textContent = user.is_active ? 'Deactivate' : 'Activate';
  toggle.type = 'button';
  toggle.className = user.is_active ? 'button button-danger' : 'button button-ghost';
  toggle.addEventListener('click', async () => {
    const verb = user.is_active ? 'Deactivate' : 'Activate';
    if (!await confirmAction(`${verb} ${user.email}?`, verb)) return;
    try {
      const result = await patchUser(user.id, { is_active: !user.is_active });
      if (!result.temporary_password) {
        showStatus(`${user.email} was ${verb.toLowerCase()}d.`);
      }
    } catch (e) {
      showStatus(e.message || String(e), { error: true });
    }
  });
  cell.appendChild(toggle);
  return cell;
}

// A file picker + Upload button that POSTs a photo to Supabase Storage (via the
// Django admin endpoint) for one player.
function buildPhotoUploader(user) {
  const wrap = document.createElement('div');
  wrap.className = 'photo-uploader';
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.setAttribute('aria-label', `Choose a photo for ${userLabel(user)}`);

  const button = document.createElement('button');
  button.textContent = 'Upload';
  button.type = 'button';
  button.className = 'button button-ghost';

  const status = document.createElement('span');
  status.className = 'photo-status';
  status.setAttribute('aria-live', 'polite');

  button.addEventListener('click', async () => {
    if (!input.files || !input.files[0]) {
      status.textContent = 'Pick a file first.';
      return;
    }
    const formData = new FormData();
    formData.append('photo', input.files[0]);
    setButtonBusy(button, true, 'Uploading…');
    status.textContent = 'Uploading…';
    try {
      await apiUpload(`/api/admin/players/${user.id}/photo/`, formData);
      status.textContent = 'Saved ✓';
    } catch (e) {
      status.textContent = e.message;
    } finally {
      setButtonBusy(button, false);
    }
  });

  wrap.appendChild(input);
  wrap.appendChild(button);
  wrap.appendChild(status);
  return wrap;
}

async function loadLinks() {
  const links = await apiFetch('/api/admin/guardian-links/');
  const tbody = el('links-table-body');
  tbody.innerHTML = '';
  for (const link of links) {
    const tr = document.createElement('tr');
    tr.appendChild(textCell(userLabel(link.guardian)));
    tr.appendChild(textCell(userLabel(link.player)));

    const actionCell = document.createElement('td');
    const btn = document.createElement('button');
    btn.className = 'button button-danger';
    btn.type = 'button';
    btn.textContent = 'Unlink';
    btn.addEventListener('click', async () => {
      const message = `Remove the link between ${userLabel(link.guardian)} and ${userLabel(link.player)}?`;
      if (!await confirmAction(message, 'Remove link')) return;
      try {
        await apiFetch(`/api/admin/guardian-links/${link.id}/`, { method: 'DELETE' });
        await loadLinks();
        showStatus('Guardian link removed.');
      } catch (e) {
        showStatus(e.message || String(e), { error: true });
      }
    });
    actionCell.appendChild(btn);
    tr.appendChild(actionCell);

    tbody.appendChild(tr);
  }
}

let disputesCache = [];

async function loadDisputes() {
  disputesCache = await apiFetch('/api/disputes/');
  const tbody = el('disputes-table-body');
  tbody.innerHTML = '';
  const select = el('respond-dispute');
  const previous = select.value;
  select.innerHTML = '';

  for (const d of disputesCache) {
    const tr = document.createElement('tr');
    tr.appendChild(textCell(d.summary));
    tr.appendChild(textCell(d.category));

    const statusCell = document.createElement('td');
    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = d.status;
    statusCell.appendChild(badge);
    tr.appendChild(statusCell);

    tr.appendChild(textCell(d.raisedByName || '—'));
    tr.appendChild(textCell(d.subjectPlayerName || '—'));
    tr.appendChild(textCell(String(d.responses.length)));
    tbody.appendChild(tr);

    select.add(new Option(`${d.summary} (${d.status})`, d.id));
  }
  if (previous) select.value = previous;
  renderDisputeThread();
}

// The thread for the dispute picked in the respond form — plain text nodes
// only (server data never goes through innerHTML, audit finding F9).
function renderDisputeThread() {
  const container = el('dispute-thread');
  container.innerHTML = '';
  const dispute = disputesCache.find(
    (d) => d.id === el('respond-dispute').value
  );
  if (!dispute) return;

  const detail = document.createElement('p');
  detail.textContent = dispute.detail || '(no detail)';
  detail.style.fontStyle = 'italic';
  container.appendChild(detail);

  if (!dispute.responses.length) {
    const empty = document.createElement('p');
    empty.textContent = 'No responses yet.';
    container.appendChild(empty);
    return;
  }
  for (const r of dispute.responses) {
    const p = document.createElement('p');
    const when = new Date(r.createdAt).toLocaleString();
    const status = r.statusChangeTo ? ` → ${r.statusChangeTo}` : '';
    p.textContent = `${r.authorName || '—'} (${r.authorRole || '?'}) · ${when}${status}: ${r.body}`;
    container.appendChild(p);
  }
}

async function loadAgeTiers() {
  const tiers = await apiFetch('/api/age-tiers/');
  const tbody = el('age-tiers-table-body');
  tbody.innerHTML = '';
  for (const t of tiers) {
    const tr = document.createElement('tr');
    tr.appendChild(textCell(t.tier));
    for (const key of ['minAge', 'maxAge']) {
      const td = document.createElement('td');
      const input = document.createElement('input');
      input.type = 'number';
      input.min = '1';
      input.max = '99';
      input.value = t[key];
      input.dataset.tier = t.tier;
      input.dataset.key = key;
      td.appendChild(input);
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
}

async function refreshDashboard() {
  await Promise.all([
    loadClubs(), loadUsers(), loadLinks(), loadDisputes(), loadAgeTiers(),
  ]);
}

async function showApp(profile) {
  loginSection.hidden = true;
  appSection.hidden = false;
  el('current-user-email').textContent = profile.email;
  await refreshDashboard();
}

function showLogin(message) {
  loginSection.hidden = false;
  appSection.hidden = true;
  el('login-error').textContent = message || '';
}

el('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('login-button');
  el('login-error').textContent = '';
  setButtonBusy(button, true, 'Signing in…');
  try {
    await firebase.auth().signInWithEmailAndPassword(
      el('login-email').value.trim(),
      el('login-password').value
    );
    // onAuthStateChanged below picks up the result.
  } catch (e) {
    el('login-error').textContent = 'Sign-in failed: ' + (e.message || e.code || e);
  } finally {
    setButtonBusy(button, false);
  }
});

document.querySelector('.password-toggle').addEventListener('click', (event) => {
  const input = el(event.currentTarget.getAttribute('aria-controls'));
  const showing = input.type === 'text';
  input.type = showing ? 'password' : 'text';
  event.currentTarget.textContent = showing ? 'Show' : 'Hide';
  event.currentTarget.setAttribute('aria-pressed', String(!showing));
});

el('users-search').addEventListener('input', filterUsers);
el('signout-button').addEventListener('click', () => firebase.auth().signOut());

el('age-tiers-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('age-tiers-save-button');
  el('age-tiers-error').textContent = '';
  setButtonBusy(button, true, 'Saving…');
  try {
    const rows = {};
    for (const input of el('age-tiers-table-body').querySelectorAll('input')) {
      const tier = input.dataset.tier;
      rows[tier] = rows[tier] || { tier };
      rows[tier][input.dataset.key] = Number(input.value);
    }
    await apiFetch('/api/age-tiers/', {
      method: 'PUT',
      body: JSON.stringify(Object.values(rows)),
    });
    await loadAgeTiers();
    showStatus('Age tiers saved.');
  } catch (e) {
    el('age-tiers-error').textContent = e.message || String(e);
  } finally {
    setButtonBusy(button, false);
  }
});

el('create-user-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('create-user-button');
  el('create-user-error').textContent = '';
  el('create-user-result').hidden = true;
  setButtonBusy(button, true, 'Creating…');
  try {
    const payload = {
      email: el('create-email').value.trim(),
      first_name: el('create-first-name').value.trim(),
      last_name: el('create-last-name').value.trim(),
      role: el('create-role').value,
      club_id: Number(el('create-club').value),
    };
    const result = await apiFetch('/api/admin/users/', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    const box = el('create-user-result');
    box.hidden = false;
    box.textContent = '';
    box.append(`Account created for `);
    const emailStrong = document.createElement('strong');
    emailStrong.textContent = result.user.email;
    box.append(emailStrong, '. ');
    if (result.temporary_password) {
      box.append('Temporary password (shown once): ');
      const code = document.createElement('code');
      code.textContent = result.temporary_password;
      box.append(code);
    } else {
      box.append(result.note);
    }
    el('create-user-form').reset();
    await loadUsers();
  } catch (e) {
    el('create-user-error').textContent = e.message;
  } finally {
    setButtonBusy(button, false);
  }
});

el('add-player-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('add-player-button');
  el('add-player-error').textContent = '';
  el('add-player-result').hidden = true;
  try {
    const guardianId = el('player-guardian').value;
    if (!guardianId) {
      el('add-player-error').textContent =
        'Select the guardian before adding a player.';
      return;
    }
    setButtonBusy(button, true, 'Adding…');
    const payload = {
      email: el('player-email').value.trim(),
      first_name: el('player-first-name').value.trim(),
      last_name: el('player-family-name').value.trim(),
      middle_initial: el('player-mi').value.trim(),
      date_of_birth: el('player-dob').value,
    };
    payload.guardian_id = guardianId;

    const result = await apiFetch('/api/admin/players/', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    const box = el('add-player-result');
    box.hidden = false;
    box.textContent = '';
    box.append('Player created for ');
    const emailStrong = document.createElement('strong');
    emailStrong.textContent =
      result.player.name || result.user.email || 'managed player profile';
    box.append(emailStrong, '. ');
    if (result.temporary_password) {
      box.append('Temporary password (shown once): ');
      const code = document.createElement('code');
      code.textContent = result.temporary_password;
      box.append(code);
    } else {
      box.append(result.note);
    }
    el('add-player-form').reset();
    await loadUsers();
    await loadLinks();
  } catch (e) {
    el('add-player-error').textContent = e.message;
  } finally {
    setButtonBusy(button, false);
  }
});

el('link-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('link-button');
  el('link-error').textContent = '';
  try {
    const guardianId = el('link-guardian').value;
    const playerId = el('link-player').value;
    if (!guardianId || !playerId) {
      el('link-error').textContent = 'Select both a guardian and a player.';
      return;
    }
    setButtonBusy(button, true, 'Linking…');
    await apiFetch('/api/admin/guardian-links/', {
      method: 'POST',
      body: JSON.stringify({ guardian_id: guardianId, player_id: playerId }),
    });
    await loadLinks();
    showStatus('Guardian link created.');
  } catch (e) {
    el('link-error').textContent = e.message;
  } finally {
    setButtonBusy(button, false);
  }
});

el('respond-dispute').addEventListener('change', renderDisputeThread);

el('respond-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = el('respond-button');
  el('respond-error').textContent = '';
  try {
    const disputeId = el('respond-dispute').value;
    const body = el('respond-body').value.trim();
    if (!disputeId || !body) {
      el('respond-error').textContent = 'Pick a dispute and write a response.';
      return;
    }
    setButtonBusy(button, true, 'Posting…');
    const payload = { body };
    const statusChange = el('respond-status').value;
    if (statusChange) payload.statusChangeTo = statusChange;
    await apiFetch(`/api/disputes/${disputeId}/responses/`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    el('respond-body').value = '';
    el('respond-status').value = '';
    await loadDisputes();
    showStatus('Dispute response posted.');
  } catch (e) {
    el('respond-error').textContent = e.message;
  } finally {
    setButtonBusy(button, false);
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
