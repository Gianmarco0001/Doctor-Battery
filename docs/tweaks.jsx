// Tweaks panel for Doctor Battery
const { useState, useEffect } = React;

function DBTweaks() {
  const [t, setTweak] = window.useTweaks(window.__TWEAKS__);

  useEffect(() => {
    const api = window.__DBApi__;
    if (!api) return;
    api.setAccent(t.accent);
    api.setIntensity(t.intensity);
    api.setCursor(t.showCursor);
    api.setMagnetic(t.magnetic);
    api.setParticles(t.particles);
    api.setAurora(t.auroraOn);
    api.setStickyShowcase(t.stickyShowcase);
  }, [t]);

  return (
    <window.TweaksPanel title="Tweaks">
      <window.TweakSection title="Aspetto">
        <window.TweakColor
          label="Colore accento"
          value={t.accent}
          onChange={(v) => setTweak('accent', v)}
          presets={['#30d158', '#00d4ff', '#ff9f0a', '#bf5af2', '#ff453a']}
        />
        <window.TweakSlider
          label="Intensità movimento"
          min={1} max={10} step={1}
          value={t.intensity}
          onChange={(v) => setTweak('intensity', v)}
        />
      </window.TweakSection>

      <window.TweakSection title="Effetti">
        <window.TweakToggle
          label="Cursore custom"
          value={t.showCursor}
          onChange={(v) => setTweak('showCursor', v)}
        />
        <window.TweakToggle
          label="Magnetic buttons"
          value={t.magnetic}
          onChange={(v) => setTweak('magnetic', v)}
        />
        <window.TweakToggle
          label="Particelle ambient"
          value={t.particles}
          onChange={(v) => setTweak('particles', v)}
        />
        <window.TweakToggle
          label="Aurora background"
          value={t.auroraOn}
          onChange={(v) => setTweak('auroraOn', v)}
        />
        <window.TweakToggle
          label="Sticky showcase"
          value={t.stickyShowcase}
          onChange={(v) => setTweak('stickyShowcase', v)}
        />
      </window.TweakSection>
    </window.TweaksPanel>
  );
}

const root = document.createElement('div');
document.body.appendChild(root);
ReactDOM.createRoot(root).render(<DBTweaks />);
