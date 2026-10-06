// The pages Rubric's account emails link to: reset-password.html and
// verify-email.html. Each link ends in ?s=<one-time token>.
//
// - The token is read once and then removed from the address bar, so it
//   doesn't linger in history or get shared by copying the URL.
// - Nothing is sent until the teacher presses the button. Mail scanners that
//   open links ahead of the reader would otherwise use up a one-time link.
// - The request goes to this site's own /api/auth/confirm, which Caddy
//   forwards to the API (tool/deploy/host/website.caddy.template). Same
//   origin, so the site's CSP stays `connect-src 'self'` and the API needs
//   no CORS.
// tool/email/email_flow.dart posts the same JSON to the same server
// endpoint, so the wire format here is tested end to end.
(() => {
  const card = document.querySelector('[data-flow]');
  if (!card) return;
  const flow = card.dataset.flow;

  const show = (state) => {
    card.querySelectorAll('[data-state]').forEach((s) => {
      s.hidden = s.dataset.state !== state;
    });
    const heading = card.querySelector(`[data-state="${state}"] h1`);
    if (heading) {
      heading.tabIndex = -1;
      heading.focus({ preventScroll: true });
    }
  };

  const token = new URLSearchParams(location.search).get('s');
  if (location.search) history.replaceState(null, '', location.pathname);
  if (!token) {
    show('missing');
    return;
  }

  // 200 → done. 4xx → the token is spent, expired or wrong (the server does
  // not say which, and the remedy is the same: a new email). 422 on a reset
  // is the exception: the new password is the one the account already has,
  // and the token is NOT used up, so the form stays.
  const send = async (body) => {
    try {
      const res = await fetch('/api/auth/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
      });
      return res.status;
    } catch {
      return 0;
    }
  };

  const outcome = (status) => {
    if (status >= 200 && status < 300) return 'done';
    if (status === 0 || status >= 500) return 'offline';
    return 'expired';
  };

  let retry = () => {};
  card.querySelector('[data-retry]')?.addEventListener('click', () => retry());

  if (flow === 'verify') {
    const button = card.querySelector('[data-confirm]');
    const confirm = async () => {
      button.disabled = true;
      const status = await send({ type: 'confirmVerifyEmail', token });
      button.disabled = false;
      show(outcome(status));
    };
    retry = () => show('form');
    button.addEventListener('click', confirm);
    show('form');
    return;
  }

  // flow === 'reset'
  const form = card.querySelector('[data-form]');
  const error = card.querySelector('[data-error]');
  const submit = form.querySelector('[type="submit"]');
  const fail = (message) => {
    error.textContent = message;
    error.hidden = false;
  };
  retry = () => show('form');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    error.hidden = true;
    const password = form.elements.password.value;
    if (password.length < 8) return fail('Use at least 8 characters.');
    if (password !== form.elements.confirm.value) {
      return fail('The two passwords don’t match.');
    }
    submit.disabled = true;
    const status = await send({
      type: 'confirmResetPassword',
      token,
      newPassword: password,
    });
    submit.disabled = false;
    if (status === 422) {
      return fail('That’s your current password. Choose a different one.');
    }
    show(outcome(status));
  });
  show('form');
})();
