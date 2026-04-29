// ============================================================
// Doctor Battery — cinematic animations layer
// ============================================================

(function () {
  'use strict';

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const TWEAKS = window.__TWEAKS__ || {};

  // ---------- Custom cursor ----------
  const dot = document.getElementById('cursorDot');
  const ring = document.getElementById('cursorRing');
  let mx = window.innerWidth / 2, my = window.innerHeight / 2;
  let rx = mx, ry = my;
  let cursorEnabled = TWEAKS.showCursor !== false && window.innerWidth > 900;

  function setCursorEnabled(on) {
    cursorEnabled = on && window.innerWidth > 900;
    if (dot) dot.style.display = cursorEnabled ? 'block' : 'none';
    if (ring) ring.style.display = cursorEnabled ? 'block' : 'none';
    document.body.style.cursor = cursorEnabled ? 'none' : 'auto';
  }
  setCursorEnabled(cursorEnabled);

  window.addEventListener('mousemove', (e) => {
    mx = e.clientX; my = e.clientY;
    if (cursorEnabled && dot) {
      dot.style.transform = `translate(${mx}px, ${my}px) translate(-50%, -50%)`;
    }
  });
  function rafCursor() {
    rx += (mx - rx) * 0.18;
    ry += (my - ry) * 0.18;
    if (cursorEnabled && ring) {
      ring.style.transform = `translate(${rx}px, ${ry}px) translate(-50%, -50%)`;
    }
    requestAnimationFrame(rafCursor);
  }
  rafCursor();

  // hover detection
  document.querySelectorAll('a, button, .feature, .device-row, .install-card, [data-magnet], .screenshot-card').forEach(el => {
    el.addEventListener('mouseenter', () => ring && ring.classList.add('hover'));
    el.addEventListener('mouseleave', () => ring && ring.classList.remove('hover'));
  });

  // ---------- Magnetic buttons ----------
  function initMagnets() {
    document.querySelectorAll('[data-magnet]').forEach(el => {
      let active = TWEAKS.magnetic !== false;
      el.addEventListener('mousemove', (e) => {
        if (!active) return;
        const r = el.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        const dx = (e.clientX - cx) * 0.25;
        const dy = (e.clientY - cy) * 0.4;
        el.style.transform = `translate(${dx}px, ${dy}px)`;
      });
      el.addEventListener('mouseleave', () => {
        el.style.transform = '';
      });
      // ripple
      el.addEventListener('click', (e) => {
        const r = el.getBoundingClientRect();
        const ripple = document.createElement('span');
        ripple.className = 'ripple';
        const size = Math.max(r.width, r.height);
        ripple.style.width = ripple.style.height = size + 'px';
        ripple.style.left = (e.clientX - r.left - size / 2) + 'px';
        ripple.style.top = (e.clientY - r.top - size / 2) + 'px';
        el.appendChild(ripple);
        setTimeout(() => ripple.remove(), 700);
      });
    });
  }
  initMagnets();

  // ---------- Smooth scroll ----------
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (id.length < 2) return;
      const target = document.querySelector(id);
      if (target) {
        e.preventDefault();
        const top = target.getBoundingClientRect().top + window.scrollY - 40;
        smoothScrollTo(top, 1100);
      }
    });
  });
  function smoothScrollTo(target, duration) {
    if (reduced) { window.scrollTo(0, target); return; }
    const start = window.scrollY;
    const dist = target - start;
    const t0 = performance.now();
    function ease(t) { return t < 0.5 ? 2*t*t : 1 - Math.pow(-2*t+2,3)/2; }
    function tick(now) {
      const t = Math.min(1, (now - t0) / duration);
      window.scrollTo(0, start + dist * ease(t));
      if (t < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  // ---------- Nav scroll state ----------
  const nav = document.getElementById('nav');
  function onScrollNav() {
    if (window.scrollY > 30) nav.classList.add('scrolled');
    else nav.classList.remove('scrolled');
  }
  window.addEventListener('scroll', onScrollNav, { passive: true });
  onScrollNav();

  // ---------- Hero entrance ----------
  const hero = document.getElementById('hero');
  const heroTitle = document.getElementById('heroTitle');
  setTimeout(() => {
    heroTitle.classList.add('in');
    hero.classList.add('in');
    // stagger word delays
    heroTitle.querySelectorAll('.word > span').forEach((w, i) => {
      w.style.transitionDelay = (i * 0.07) + 's';
    });
  }, 100);

  // ---------- Hero MacBook tilt on scroll ----------
  const macbook = document.getElementById('macbook');
  function onScrollHero() {
    if (!macbook) return;
    const sc = window.scrollY;
    const max = window.innerHeight;
    const p = Math.max(0, Math.min(1, sc / max));
    const rot = -10 + p * 14; // -10deg to +4deg
    const sc2 = 1 - p * 0.05;
    macbook.style.transform = `rotateX(${rot}deg) scale(${sc2})`;
  }
  window.addEventListener('scroll', onScrollHero, { passive: true });
  onScrollHero();

  // ---------- Counters ----------
  function animateCounter(el, target, decimals = 0) {
    if (reduced) {
      el.textContent = decimals ? target.toFixed(decimals) : target;
      return;
    }
    const t0 = performance.now();
    const dur = 1800;
    function tick(now) {
      const t = Math.min(1, (now - t0) / dur);
      const eased = 1 - Math.pow(1 - t, 3);
      const v = target * eased;
      el.textContent = decimals ? v.toFixed(decimals) : Math.round(v);
      if (t < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  // Trigger when in viewport
  const counterIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        e.target.querySelectorAll('[data-counter], [data-counter-show]').forEach(el => {
          if (el.dataset.fired) return;
          el.dataset.fired = '1';
          const target = parseFloat(el.dataset.target);
          const dec = parseInt(el.dataset.decimals || '0', 10);
          // If inside the hero macbook, wait for lid-open
          const inHeroMac = el.closest('#macbook');
          const startDelay = inHeroMac ? 2000 : 0;
          setTimeout(() => animateCounter(el, target, dec), startDelay);
        });
        // device % suffix
        e.target.querySelectorAll('.device-pct').forEach(el => {
          const inHeroMac = el.closest('#macbook');
          const delay = inHeroMac ? 3900 : 1900;
          setTimeout(() => {
            if (!el.textContent.includes('%')) el.textContent = el.textContent + '%';
          }, delay);
        });
        counterIO.unobserve(e.target);
      }
    });
  }, { threshold: 0.3 });
  document.querySelectorAll('.dashboard, .stats-row, .big-battery, .ring-wrap').forEach(el => counterIO.observe(el));

  // ---------- Hero ring + chart fill ----------
  const heroRing = document.getElementById('heroRing');
  function fillHeroRing() {
    if (!heroRing) return;
    const C = 2 * Math.PI * 26; // 163.36
    heroRing.style.strokeDashoffset = C * (1 - 0.94);
  }
  setTimeout(fillHeroRing, 2400);

  // Build hero chart path
  const chartLine = document.getElementById('heroChartLine');
  const chartArea = document.getElementById('heroChartArea');
  if (chartLine) {
    const pts = [];
    const W = 600, H = 160;
    let val = 100;
    for (let i = 0; i <= 12; i++) {
      val -= Math.random() * 0.8 + 0.2;
      const x = (i / 12) * W;
      const y = H - ((val - 80) / 20) * H * 0.85;
      pts.push([x, Math.max(20, Math.min(140, y))]);
    }
    const linePath = pts.map((p, i) => (i === 0 ? `M ${p[0]} ${p[1]}` : `L ${p[0]} ${p[1]}`)).join(' ');
    const areaPath = linePath + ` L ${W} ${H} L 0 ${H} Z`;
    chartLine.setAttribute('d', linePath);
    chartArea.setAttribute('d', areaPath);
    setTimeout(() => {
      chartLine.style.strokeDashoffset = '0';
      chartArea.style.transition = 'opacity 1.5s ease 0.5s';
      chartArea.style.opacity = '1';
    }, 2600);
  }

  // ---------- Reveal on scroll ----------
  const revealIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        e.target.classList.add('in');
        revealIO.unobserve(e.target);
      }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -50px 0px' });
  document.querySelectorAll('.reveal').forEach(el => revealIO.observe(el));

  // ---------- Feature cards stagger + tilt + spotlight ----------
  const featureIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        const cards = document.querySelectorAll('.feature');
        cards.forEach((c, i) => {
          setTimeout(() => c.classList.add('in'), i * 80);
        });
        featureIO.unobserve(e.target);
      }
    });
  }, { threshold: 0.1 });
  const featuresGrid = document.querySelector('.features-grid');
  if (featuresGrid) featureIO.observe(featuresGrid);

  document.querySelectorAll('.feature').forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const r = card.getBoundingClientRect();
      const x = e.clientX - r.left;
      const y = e.clientY - r.top;
      const px = (x / r.width - 0.5);
      const py = (y / r.height - 0.5);
      card.style.setProperty('--mx', x + 'px');
      card.style.setProperty('--my', y + 'px');
      card.style.transform = `perspective(900px) rotateY(${px * 6}deg) rotateX(${-py * 6}deg) translateY(-3px)`;
    });
    card.addEventListener('mouseleave', () => {
      card.style.transform = '';
    });
  });

  // Same effect on screenshot cards
  document.querySelectorAll('.screenshot-card').forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const r = card.getBoundingClientRect();
      const x = e.clientX - r.left;
      const y = e.clientY - r.top;
      const px = (x / r.width - 0.5);
      const py = (y / r.height - 0.5);
      card.style.setProperty('--mx', x + 'px');
      card.style.setProperty('--my', y + 'px');
      card.style.transform = `perspective(1000px) rotateY(${px * 8}deg) rotateX(${-py * 8}deg) translateY(-4px) scale(1.01)`;
    });
    card.addEventListener('mouseleave', () => {
      card.style.transform = '';
    });
  });

  // Install cards reveal
  const installIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        document.querySelectorAll('.install-card').forEach((c, i) => {
          setTimeout(() => c.classList.add('in'), i * 120);
        });
        installIO.unobserve(e.target);
      }
    });
  }, { threshold: 0.2 });
  const installGrid = document.querySelector('.install-grid');
  if (installGrid) installIO.observe(installGrid);

  // Screenshot cards reveal
  const ssIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        document.querySelectorAll('.screenshot-card').forEach((c, i) => {
          setTimeout(() => c.classList.add('in'), i * 140);
        });
        ssIO.unobserve(e.target);
      }
    });
  }, { threshold: 0.15 });
  const ssGrid = document.querySelector('.screenshots-grid');
  if (ssGrid) ssIO.observe(ssGrid);

  // ---------- Sticky showcase logic ----------
  const showcase = document.getElementById('showcase');
  const progFill = document.getElementById('progFill');
  const dots = document.querySelectorAll('.showcase-dot');
  const textSteps = document.querySelectorAll('.showcase-step');
  const visSteps = document.querySelectorAll('.showcase-vis-step');
  const bigBatteryFill = document.getElementById('bigBatteryFill');
  const forecastLine = document.getElementById('forecastLine');
  const forecastArea = document.getElementById('forecastArea');
  const forecastDots = document.querySelectorAll('.forecast-dot');
  const bigRingCyan = document.getElementById('bigRingCyan');
  const bigRingGreen = document.getElementById('bigRingGreen');

  let lastStep = -1;
  function activateStep(step) {
    if (step === lastStep) return;
    lastStep = step;
    textSteps.forEach(el => el.classList.toggle('active', +el.dataset.step === step));
    visSteps.forEach(el => el.classList.toggle('active', +el.dataset.step === step));
    dots.forEach((d, i) => d.classList.toggle('active', i <= step));

    if (step === 0 && bigBatteryFill) {
      bigBatteryFill.style.width = '94%';
    }
    if (step === 1 && forecastLine) {
      forecastLine.classList.add('in');
      forecastArea.classList.add('in');
      forecastDots.forEach((d, i) => setTimeout(() => d.classList.add('in'), 1000 + i * 200));
    }
    if (step === 2 && bigRingCyan) {
      const C1 = 2 * Math.PI * 130; // 817
      const C2 = 2 * Math.PI * 105; // 660
      bigRingCyan.style.strokeDashoffset = C1 * (1 - 0.94);
      bigRingGreen.style.strokeDashoffset = C2 * (1 - 0.78);
    }
  }

  function onScrollShowcase() {
    if (!showcase) return;
    const r = showcase.getBoundingClientRect();
    const total = showcase.offsetHeight - window.innerHeight;
    const scrolled = -r.top;
    const p = Math.max(0, Math.min(1, scrolled / total));

    if (progFill) progFill.style.height = (p * 100) + '%';

    let step = 0;
    if (p < 0.33) step = 0;
    else if (p < 0.66) step = 1;
    else step = 2;

    if (r.top < window.innerHeight && r.bottom > 0) {
      activateStep(step);
    }
  }
  window.addEventListener('scroll', onScrollShowcase, { passive: true });
  onScrollShowcase();

  // ---------- Particles ----------
  const canvas = document.getElementById('particles');
  const ctx = canvas ? canvas.getContext('2d') : null;
  let particles = [];
  let particlesOn = TWEAKS.particles !== false;

  function resizeCanvas() {
    if (!canvas) return;
    canvas.width = window.innerWidth * window.devicePixelRatio;
    canvas.height = window.innerHeight * window.devicePixelRatio;
    canvas.style.width = window.innerWidth + 'px';
    canvas.style.height = window.innerHeight + 'px';
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  }
  // Mouse tracking for ion attraction
  let mouseX = -9999, mouseY = -9999;
  window.addEventListener('mousemove', (e) => { mouseX = e.clientX; mouseY = e.clientY; });
  window.addEventListener('mouseout', () => { mouseX = -9999; mouseY = -9999; });

  let arcs = []; // electric arcs between nearby ions
  let sparks = []; // brief flashes

  function spawnParticles() {
    particles = [];
    const n = window.innerWidth < 700 ? 36 : 72;
    for (let i = 0; i < n; i++) {
      particles.push({
        x: Math.random() * window.innerWidth,
        y: Math.random() * window.innerHeight,
        vx: (Math.random() - 0.5) * 0.4,
        vy: (Math.random() - 0.5) * 0.4,
        r: Math.random() * 1.4 + 0.4,
        a: Math.random() * 0.5 + 0.15,
        phase: Math.random() * Math.PI * 2,
        charge: Math.random() < 0.5 ? 1 : -1, // green vs cyan
        hue: Math.random() < 0.85 ? 'g' : 'c'
      });
    }
  }

  function drawLightning(x1, y1, x2, y2, alpha, color) {
    // Recursive midpoint displacement for jagged line
    const segs = [[x1, y1, x2, y2]];
    for (let i = 0; i < 3; i++) {
      const next = [];
      for (const [ax, ay, bx, by] of segs) {
        const mx = (ax + bx) / 2 + (Math.random() - 0.5) * 8;
        const my = (ay + by) / 2 + (Math.random() - 0.5) * 8;
        next.push([ax, ay, mx, my]);
        next.push([mx, my, bx, by]);
      }
      segs.length = 0; segs.push(...next);
    }
    ctx.strokeStyle = color.replace('A', alpha);
    ctx.lineWidth = 0.7;
    ctx.beginPath();
    ctx.moveTo(segs[0][0], segs[0][1]);
    for (const [, , bx, by] of segs) ctx.lineTo(bx, by);
    ctx.stroke();
  }

  let frame = 0;
  function drawParticles() {
    if (!ctx || !particlesOn) {
      if (ctx) ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
      requestAnimationFrame(drawParticles);
      return;
    }
    frame++;
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    const W = window.innerWidth, H = window.innerHeight;

    // Update + draw ions
    particles.forEach((p, idx) => {
      // Cursor repulsion/attraction
      const dx = p.x - mouseX, dy = p.y - mouseY;
      const d2 = dx * dx + dy * dy;
      if (d2 < 22500) { // 150px radius
        const d = Math.sqrt(d2) || 1;
        const force = (1 - d / 150) * 0.5 * p.charge;
        p.vx += (dx / d) * force;
        p.vy += (dy / d) * force;
      }

      // Drift + damping
      p.vx *= 0.96; p.vy *= 0.96;
      p.vx += (Math.random() - 0.5) * 0.02;
      p.vy += (Math.random() - 0.5) * 0.02;
      p.x += p.vx; p.y += p.vy;
      p.phase += 0.04;

      // Wrap
      if (p.x < 0) p.x = W;
      if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H;
      if (p.y > H) p.y = 0;

      const pulse = 0.6 + Math.sin(p.phase) * 0.4;
      const radius = p.r * (1 + pulse * 0.4);
      const baseColor = p.hue === 'g' ? '48, 209, 88' : '0, 212, 255';

      // Glow
      const grad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, radius * 6);
      grad.addColorStop(0, `rgba(${baseColor}, ${p.a * pulse})`);
      grad.addColorStop(1, `rgba(${baseColor}, 0)`);
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(p.x, p.y, radius * 6, 0, Math.PI * 2);
      ctx.fill();

      // Core
      ctx.fillStyle = `rgba(${baseColor}, ${Math.min(1, p.a * 2)})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
      ctx.fill();
    });

    // Connect close particles with electric arcs
    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const a = particles[i], b = particles[j];
        const dx = a.x - b.x, dy = a.y - b.y;
        const d2 = dx * dx + dy * dy;
        if (d2 < 14400) { // 120px
          const alpha = (1 - Math.sqrt(d2) / 120) * 0.18;
          const sameHue = a.hue === b.hue;
          const color = sameHue
            ? (a.hue === 'g' ? 'rgba(48, 209, 88, A)' : 'rgba(0, 212, 255, A)')
            : 'rgba(140, 230, 200, A)';
          // Occasional jagged lightning between very close pairs
          if (d2 < 3600 && Math.random() < 0.04) {
            drawLightning(a.x, a.y, b.x, b.y, alpha * 4, color);
          } else {
            ctx.strokeStyle = color.replace('A', alpha);
            ctx.lineWidth = 0.5;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
    }

    // Cursor energy field — radial bolts
    if (mouseX > 0 && frame % 6 === 0 && Math.random() < 0.5) {
      sparks.push({
        x: mouseX, y: mouseY,
        angle: Math.random() * Math.PI * 2,
        len: 30 + Math.random() * 40,
        life: 1
      });
    }
    sparks = sparks.filter(s => {
      s.life -= 0.08;
      if (s.life <= 0) return false;
      const ex = s.x + Math.cos(s.angle) * s.len * (1 - s.life);
      const ey = s.y + Math.sin(s.angle) * s.len * (1 - s.life);
      drawLightning(s.x, s.y, ex, ey, s.life * 0.5, 'rgba(48, 209, 88, A)');
      return true;
    });

    requestAnimationFrame(drawParticles);
  }
  if (canvas) {
    resizeCanvas();
    spawnParticles();
    drawParticles();
    window.addEventListener('resize', () => { resizeCanvas(); spawnParticles(); });
  }

  // ---------- Terminal typewriter (build section) ----------
  const termBody = document.getElementById('termBody');
  const termIO = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (e.isIntersecting && termBody && !termBody.dataset.fired) {
        termBody.dataset.fired = '1';
        const lines = Array.from(termBody.querySelectorAll('.term-line'));
        const originals = lines.map(l => l.innerHTML);
        lines.forEach(l => l.style.opacity = '0');
        let delay = 0;
        lines.forEach((l, i) => {
          setTimeout(() => {
            l.style.opacity = '1';
            l.style.transition = 'opacity 0.3s';
          }, delay);
          delay += 350;
        });
        termIO.unobserve(termBody);
      }
    });
  }, { threshold: 0.3 });
  if (termBody) termIO.observe(termBody);

  // ---------- Aurora toggle ----------
  function setAurora(on) {
    const aurora = document.getElementById('aurora');
    if (aurora) aurora.style.display = on ? '' : 'none';
  }
  setAurora(TWEAKS.auroraOn !== false);

  // ---------- Expose API for tweaks ----------
  window.__DBApi__ = {
    setAccent(hex) {
      document.documentElement.style.setProperty('--accent', hex);
      // try to derive glow
      try {
        const r = parseInt(hex.slice(1, 3), 16);
        const g = parseInt(hex.slice(3, 5), 16);
        const b = parseInt(hex.slice(5, 7), 16);
        document.documentElement.style.setProperty('--glow', `rgba(${r},${g},${b},0.45)`);
      } catch (e) {}
    },
    setIntensity(v) {
      // affects particle alpha + magnet strength via data attrs not strictly needed
      const factor = v / 7;
      particles.forEach(p => p.a = Math.min(0.7, p.a * factor));
    },
    setCursor(on) { setCursorEnabled(on); },
    setMagnetic(on) {
      // re-bind ignored; just toggles on next move via TWEAKS
      TWEAKS.magnetic = on;
      if (!on) document.querySelectorAll('[data-magnet]').forEach(el => el.style.transform = '');
    },
    setParticles(on) { particlesOn = on; },
    setAurora,
    setStickyShowcase(on) {
      const sc = document.getElementById('showcase');
      if (!sc) return;
      sc.style.minHeight = on ? '380vh' : '100vh';
      sc.querySelector('.showcase-pin').style.position = on ? 'sticky' : 'static';
    }
  };

  // Apply initial tweaks
  if (TWEAKS.accent) window.__DBApi__.setAccent(TWEAKS.accent);
})();
