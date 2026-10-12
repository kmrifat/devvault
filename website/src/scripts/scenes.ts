// Drives the animated scenes.
//
// A scene is an element with data-scene and data-steps="t1,t2,…" (ms from
// the start). At each time it gains the class s1, s2, … in turn, so CSS can
// say ".s3 .sheet { … }" and every later step keeps it. data-loop (ms) is
// when it fades and starts again. Scenes only run while on screen, and with
// reduced motion they jump to their last step and stay there.
//
// A .fit box holds a fixed-size .stage (data-w × data-h) scaled to fit.

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function fitStages() {
  const ro = new ResizeObserver((entries) => {
    for (const e of entries) {
      const box = e.target as HTMLElement;
      const w = Number(box.dataset.w);
      box.style.setProperty('--k', String(box.clientWidth / w));
    }
  });
  document.querySelectorAll<HTMLElement>('.fit').forEach((box) => {
    const w = Number(box.dataset.w);
    const h = Number(box.dataset.h);
    box.style.aspectRatio = `${w} / ${h}`;
    const stage = box.querySelector<HTMLElement>('.stage');
    if (stage) {
      stage.style.width = `${w}px`;
      stage.style.height = `${h}px`;
    }
    ro.observe(box);
  });
}

class Scene {
  private timers: number[] = [];
  private running = false;
  private readonly steps: number[];
  private readonly loop: number;

  constructor(private readonly el: HTMLElement) {
    this.steps = (el.dataset.steps ?? '').split(',').filter(Boolean).map(Number);
    this.loop = Number(el.dataset.loop ?? 0);
  }

  private clear() {
    this.timers.forEach(clearTimeout);
    this.timers = [];
  }

  private reset() {
    this.steps.forEach((_, i) => this.el.classList.remove(`s${i + 1}`));
    this.el.classList.remove('fade');
  }

  showEnd() {
    this.steps.forEach((_, i) => this.el.classList.add(`s${i + 1}`));
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.reset();
    this.steps.forEach((t, i) => {
      this.timers.push(window.setTimeout(() => this.el.classList.add(`s${i + 1}`), t));
    });
    if (this.loop) {
      this.timers.push(window.setTimeout(() => this.el.classList.add('fade'), this.loop - 500));
      this.timers.push(
        window.setTimeout(() => {
          this.running = false;
          this.clear();
          this.start();
        }, this.loop),
      );
    }
  }

  stop() {
    this.running = false;
    this.clear();
  }
}

function runScenes() {
  const scenes = new Map<Element, Scene>();
  document.querySelectorAll<HTMLElement>('[data-scene]').forEach((el) => {
    scenes.set(el, new Scene(el));
  });
  if (reduced) {
    scenes.forEach((s) => s.showEnd());
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        const s = scenes.get(e.target);
        if (!s) continue;
        if (e.isIntersecting) s.start();
        else s.stop();
      }
    },
    { threshold: 0.35 },
  );
  scenes.forEach((_, el) => io.observe(el));
}

fitStages();
runScenes();
