// Team-interest form. Posts to the form endpoint in data-endpoint
// (a Formspree form URL, https://formspree.io/f/<id>). Nothing else on the
// page sends data anywhere.
(function () {
  const form = document.getElementById('team-form');
  if (!form) return;

  const teamOnly = form.querySelector('.team-only');
  const status = form.querySelector('.form-status');
  const button = form.querySelector('button[type="submit"]');

  function showTeamQuestions() {
    const use = form.querySelector('input[name="use"]:checked');
    teamOnly.hidden = !use || use.value === 'personal';
  }
  form.addEventListener('change', (e) => {
    if (e.target.name === 'use') showTeamQuestions();
  });
  showTeamQuestions();

  function say(text, kind) {
    status.textContent = text;
    status.className = 'form-status' + (kind ? ' ' + kind : '');
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    if (!form.querySelector('input[name="use"]:checked')) {
      say('Pick how you would use DevVault first.', 'err');
      form.querySelector('input[name="use"]').focus();
      return;
    }
    const email = form.querySelector('input[name="email"]');
    if (email.value && !email.checkValidity()) {
      say('That email address doesn’t look right.', 'err');
      email.focus();
      return;
    }

    const endpoint = form.dataset.endpoint;
    if (!endpoint) {
      say('The form isn’t connected yet. Please open an issue on GitHub instead.', 'err');
      return;
    }

    const data = new FormData(form);
    // Team questions that were hidden don't belong in a personal answer.
    if (teamOnly.hidden) {
      ['team_size', 'needs', 'pay'].forEach((k) => data.delete(k));
    }
    data.set('needs', data.getAll('needs').join(', '));

    button.disabled = true;
    say('Sending…');
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        body: data,
        headers: { Accept: 'application/json' },
      });
      if (!res.ok) throw new Error(String(res.status));
      form.classList.add('sent');
      say('Thanks! Your answer helps decide whether a team version gets built.', 'ok');
    } catch (_) {
      button.disabled = false;
      say('Couldn’t send that. Check your connection and try again.', 'err');
    }
  });
})();
