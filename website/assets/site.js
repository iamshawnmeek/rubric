// Rubric public site: the only script. Three small behaviours, all of them
// off for prefers-reduced-motion:
//   1. sections rise and fade in once as they enter the viewport;
//   2. the hero device and its cards drift a few pixels against the scroll;
//   3. the nav gains a frosted backdrop once the page has scrolled.
(() => {
  const root = document.documentElement;
  const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
  root.classList.add('js');

  const year = document.querySelector('[data-year]');
  if (year) year.textContent = String(new Date().getFullYear());

  const nav = document.querySelector('[data-nav]');
  const onScrollNav = () => nav && nav.classList.toggle('is-scrolled', scrollY > 8);
  onScrollNav();
  addEventListener('scroll', onScrollNav, { passive: true });

  const reveal = (el) => {
    el.classList.add('is-in');
    el.querySelectorAll('[data-meter]').forEach((m) => { m.style.width = m.dataset.meter + '%'; });
  };
  const items = document.querySelectorAll('.reveal');
  if (calm || !('IntersectionObserver' in window)) {
    items.forEach(reveal);
  } else {
    // Siblings that arrive together stagger by 70 ms, so a grid settles in
    // a gentle wave instead of all at once.
    const io = new IntersectionObserver((entries) => {
      let i = 0;
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.style.transitionDelay = `${Math.min(i++ * 70, 350)}ms`;
        reveal(e.target);
        io.unobserve(e.target);
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    items.forEach((el) => {
      // Already on screen at load: show it now rather than wait for the
      // observer's first callback.
      const r = el.getBoundingClientRect();
      if (r.top < innerHeight && r.bottom > 0) reveal(el);
      else io.observe(el);
    });
  }

  // The hero's floating cards also count as "in" with the device.
  document.querySelectorAll('.hero__device .float-card').forEach((c) => {
    if (calm) { reveal(c); return; }
    setTimeout(() => reveal(c), 700);
  });

  if (calm) return;
  const layers = [...document.querySelectorAll('[data-parallax]')];
  if (!layers.length) return;
  let ticking = false;
  const parallax = () => {
    ticking = false;
    const y = scrollY;
    if (y > innerHeight * 1.5) return; // the hero is long gone
    for (const el of layers) {
      el.style.transform = `translate3d(0, ${(y * parseFloat(el.dataset.parallax)).toFixed(1)}px, 0)`;
    }
  };
  addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(parallax); }
  }, { passive: true });
})();
