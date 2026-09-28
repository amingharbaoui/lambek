import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { CSS2DObject, CSS2DRenderer } from "three/addons/renderers/CSS2DRenderer.js";
import { Line2 } from "three/addons/lines/Line2.js";
import { LineGeometry } from "three/addons/lines/LineGeometry.js";
import { LineMaterial } from "three/addons/lines/LineMaterial.js";
import { Crosshair, Pause, Play, Waypoints, X } from "lucide-react";

const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));
const EASE = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

// Fresnel glow: the rim takes the color, the core stays dark
const GLOW_VERTEX = `
varying vec3 vNormal;
varying vec3 vView;
void main() {
  vec4 viewPosition = modelViewMatrix * vec4(position, 1.0);
  vNormal = normalize(normalMatrix * normal);
  vView = normalize(-viewPosition.xyz);
  gl_Position = projectionMatrix * viewPosition;
}`;
const GLOW_FRAGMENT = `
uniform vec3 uColor;
uniform vec3 uCore;
uniform float uPower;
uniform float uHot;
varying vec3 vNormal;
varying vec3 vView;
void main() {
  float rim = pow(1.0 - max(dot(vNormal, vView), 0.0), uPower);
  vec3 color = mix(uCore, uColor, clamp(rim * 0.9 + 0.1 + uHot * 0.25, 0.0, 1.0));
  gl_FragColor = vec4(color * (0.9 + rim * 0.25 + uHot * 0.2), 1.0);
}`;

function cssColor(name) {
  return new THREE.Color(getComputedStyle(document.documentElement).getPropertyValue(name).trim());
}

function readColors() {
  return {
    bg: cssColor("--bg"),
    text: cssColor("--text"),
    text2: cssColor("--text-2"),
    muted: cssColor("--muted"),
    line: cssColor("--line-strong"),
    accent: cssColor("--accent"),
    warn: cssColor("--warn"),
    danger: cssColor("--danger"),
  };
}

function statusColor(step, colors) {
  if (!step.action) return colors.muted;
  if (step.status === "Ready") return colors.accent;
  if (["Blocked", "Invalid", "Unsupported"].includes(step.status)) return colors.danger;
  return colors.warn;
}

// Deterministic layout: steps on a golden-angle staircase, parameters on a Fibonacci sphere
function layout(plan, title, showParameters) {
  const levelOf = new Map();
  plan.levels.forEach((level, index) => level.forEach((number) => levelOf.set(number, index)));
  const order = plan.order.length > 0 ? plan.order : plan.steps.map((step) => step.step);

  const nodes = [{ id: "request", kind: "request", position: new THREE.Vector3(0, 13, 0), label: title || plan.answer.split("\n")[0] }];
  const links = [];

  plan.steps.forEach((step) => {
    const index = Math.max(0, order.indexOf(step.step));
    const angle = index * GOLDEN_ANGLE;
    const radius = 21 + 8 * Math.sqrt(index);
    const y = -(levelOf.get(step.step) ?? index) * 13;
    const position = new THREE.Vector3(Math.cos(angle) * radius, y, Math.sin(angle) * radius);
    const id = `step-${step.step}`;
    nodes.push({ id, kind: "step", step, position });
    links.push({ from: "request", to: id, kind: "contains" });

    if (!showParameters) return;
    const names = Object.keys(step.parameters);
    names.forEach((name, i) => {
      const phi = Math.acos(1 - (2 * (i + 0.5)) / names.length);
      const theta = GOLDEN_ANGLE * i + angle;
      const offset = new THREE.Vector3(Math.sin(phi) * Math.cos(theta), Math.cos(phi) * 0.8, Math.sin(phi) * Math.sin(theta)).multiplyScalar(8);
      const parameterId = `${id}-${name}`;
      nodes.push({ id: parameterId, kind: "parameter", step, name, position: position.clone().add(offset), label: `${name} ${step.parameters[name]}` });
      links.push({ from: id, to: parameterId, kind: "parameter" });
    });
  });

  plan.edges.forEach((edge) => links.push({ from: `step-${edge.from}`, to: `step-${edge.to}`, kind: "dependency" }));
  return { nodes, links };
}

function curveBetween(from, to, lift) {
  const middle = from.clone().add(to).multiplyScalar(0.5);
  middle.y += lift;
  return new THREE.QuadraticBezierCurve3(from, middle, to);
}

function makeLine(points, color, width, opacity, size) {
  const geometry = new LineGeometry();
  geometry.setPositions(points.flatMap((point) => [point.x, point.y, point.z]));
  const material = new LineMaterial({ color, linewidth: width, transparent: true, opacity, depthWrite: false });
  material.resolution.set(size.x, size.y);
  return new Line2(geometry, material);
}

function makeLabel(className, html) {
  const element = document.createElement("div");
  element.className = `node-label ${className}`;
  element.innerHTML = html;
  return new CSS2DObject(element);
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[character]);
}

// Builds every object of one plan in a group
function buildScene(plan, title, colors, showParameters, size, light) {
  const group = new THREE.Group();
  const pickable = [];
  const flows = [];
  const spinning = [];
  const { nodes, links } = layout(plan, title, showParameters);
  const byId = new Map(nodes.map((node) => [node.id, node]));

  nodes.forEach((node, index) => {
    const holder = new THREE.Group();
    holder.position.copy(node.position);
    holder.userData = { node, appearAt: index * 55, scale: 1 };
    group.add(holder);

    if (node.kind === "request") {
      const edges = new THREE.LineSegments(
        new THREE.EdgesGeometry(new THREE.IcosahedronGeometry(4.2, 1)),
        new THREE.LineBasicMaterial({ color: colors.accent, transparent: true, opacity: 0.55 }),
      );
      const core = new THREE.Mesh(
        new THREE.SphereGeometry(1.6, 32, 16),
        new THREE.ShaderMaterial({
          vertexShader: GLOW_VERTEX,
          fragmentShader: GLOW_FRAGMENT,
          uniforms: { uColor: { value: colors.text }, uCore: { value: colors.accent }, uPower: { value: 1.6 }, uHot: { value: 0 } },
        }),
      );
      holder.add(edges, core);
      spinning.push(edges);
      core.userData.node = node;
      pickable.push(core);
      const label = makeLabel("request", escapeHtml(node.label.length > 55 ? `${node.label.slice(0, 54)}…` : node.label));
      label.position.set(0, 7.5, 0);
      holder.add(label);
      holder.userData.label = label;
      return;
    }

    const isStep = node.kind === "step";
    const color = isStep ? statusColor(node.step, colors) : colors.text2;
    const radius = isStep ? 2.6 : 0.9;
    const sphere = new THREE.Mesh(
      new THREE.SphereGeometry(radius, 48, 24),
      new THREE.ShaderMaterial({
        vertexShader: GLOW_VERTEX,
        fragmentShader: GLOW_FRAGMENT,
        uniforms: light
          ? { uColor: { value: color.clone().multiplyScalar(0.45) }, uCore: { value: color.clone().lerp(colors.bg, 0.1) }, uPower: { value: 1.3 }, uHot: { value: 0 } }
          : { uColor: { value: color }, uCore: { value: colors.bg.clone().lerp(color, 0.12) }, uPower: { value: 2.2 }, uHot: { value: 0 } },
      }),
    );
    sphere.userData.node = node;
    holder.add(sphere);
    pickable.push(sphere);
    holder.userData.sphere = sphere;

    if (isStep) {
      const ring = new THREE.Mesh(
        new THREE.TorusGeometry(radius * 1.618, 0.05, 8, 96),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.34 }),
      );
      ring.rotation.x = Math.PI / 2;
      holder.add(ring);
      spinning.push(ring);
      holder.userData.ring = ring;
    }

    const html = isStep
      ? `<i>${node.step.step}</i>${escapeHtml(node.step.action ?? "no action")}`
      : escapeHtml(node.label.length > 34 ? `${node.label.slice(0, 33)}…` : node.label);
    const label = makeLabel(node.kind, html);
    label.position.set(0, radius + (isStep ? 2.6 : 1.4), 0);
    holder.add(label);
    holder.userData.label = label;
  });

  links.forEach((link) => {
    const from = byId.get(link.from).position;
    const to = byId.get(link.to).position;
    if (link.kind === "parameter") {
      group.add(makeLine([from, to], colors.line, 1, 0.55, size));
      return;
    }
    const isDependency = link.kind === "dependency";
    const curve = curveBetween(from, to, isDependency ? 8 : 5);
    const points = curve.getPoints(55);
    group.add(makeLine(points, isDependency ? colors.accent : colors.line, isDependency ? 2 : 1.2, isDependency ? 0.9 : 0.7, size));

    // Particles flow along dependencies, in execution order
    if (isDependency) {
      for (let i = 0; i < 3; i++) {
        const particle = new THREE.Mesh(new THREE.SphereGeometry(0.34, 12, 8), new THREE.MeshBasicMaterial({ color: colors.accent }));
        group.add(particle);
        flows.push({ particle, curve, offset: i / 3 });
      }
    }
  });

  // Polar grid under the plan
  const box = new THREE.Box3();
  nodes.forEach((node) => box.expandByPoint(node.position));
  const grid = new THREE.PolarGridHelper(Math.max(55, box.getSize(new THREE.Vector3()).length() * 0.8), 16, 8, 89, colors.line, colors.line);
  grid.position.y = box.min.y - 8;
  grid.material.transparent = true;
  grid.material.opacity = 0.34;
  grid.material.depthWrite = false;
  group.add(grid);

  return { group, pickable, flows, spinning, bounds: box.getBoundingSphere(new THREE.Sphere()) };
}

function dispose(object) {
  object.traverse((child) => {
    child.geometry?.dispose();
    if (child.material) [].concat(child.material).forEach((material) => material.dispose());
    if (child.isCSS2DObject) child.element.remove();
  });
}

export default function Graph3D({ plan, title, theme, selected, onSelect, onEdit, caption, onClose }) {
  const container = useRef(null);
  const labels = useRef(null);
  const world = useRef(null);
  const [showParameters, setShowParameters] = useState(true);
  const [rotate, setRotate] = useState(true);

  // Renderer, camera, controls, and bloom: created once
  useEffect(() => {
    const element = container.current;
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    element.appendChild(renderer.domElement);

    const labelRenderer = new CSS2DRenderer({ element: labels.current });
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 2000);
    camera.position.set(34, 34, 89);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.autoRotateSpeed = 0.34;
    controls.minDistance = 8;
    controls.maxDistance = 610;

    const composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.55, 0.34, 0.5);
    composer.addPass(bloom);
    composer.addPass(new OutputPass());

    const state = { renderer, labelRenderer, scene, camera, controls, composer, bloom, content: null, flight: null, hovered: null, size: new THREE.Vector2(1, 1), started: performance.now() };
    world.current = state;

    function resize() {
      const width = element.clientWidth;
      const height = element.clientHeight;
      state.size.set(width, height);
      renderer.setSize(width, height);
      composer.setSize(width, height);
      bloom.resolution.set(width / 2, height / 2);
      labelRenderer.setSize(width, height);
      camera.aspect = width / Math.max(height, 1);
      camera.updateProjectionMatrix();
      state.content?.group.traverse((child) => child.material?.resolution?.set(width, height));
    }
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    resize();

    // Picking: hover highlights, a click selects a step
    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    let down = null;

    function pick(event) {
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.set(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1);
      raycaster.setFromCamera(pointer, camera);
      return raycaster.intersectObjects(state.content?.pickable ?? [], false)[0]?.object.userData.node ?? null;
    }

    function onMove(event) {
      const node = pick(event);
      if (node?.id === state.hovered?.id) return;
      state.hovered = node;
      renderer.domElement.style.cursor = node ? "pointer" : "grab";
    }
    function onDown(event) {
      down = { x: event.clientX, y: event.clientY };
      controls.autoRotate = false;
    }
    function onUp(event) {
      if (!down || Math.hypot(event.clientX - down.x, event.clientY - down.y) > 4) return;
      const node = pick(event);
      state.onSelect?.(node && node.kind !== "request" ? node.step.step : null);
    }
    renderer.domElement.addEventListener("pointermove", onMove);
    renderer.domElement.addEventListener("pointerdown", onDown);
    renderer.domElement.addEventListener("pointerup", onUp);

    // Frame loop
    let frame = 0;
    function tick(now) {
      frame = requestAnimationFrame(tick);
      if (document.hidden) return;
      const content = state.content;
      if (content) {
        const age = now - content.builtAt;
        content.group.children.forEach((child) => {
          const data = child.userData;
          if (!data.node) return;
          const appear = EASE(Math.min(1, Math.max(0, (age - data.appearAt) / 377)));
          const hot = state.hovered?.id === data.node.id || (data.node.step && data.node.step.step === state.selected);
          data.scale += ((hot ? 1.18 : 1) - data.scale) * 0.18;
          child.scale.setScalar(Math.max(0.001, appear * data.scale));
          if (data.sphere) data.sphere.material.uniforms.uHot.value = hot ? 1 : 0;
          if (data.ring) data.ring.material.opacity = hot ? 0.9 : 0.34;
          if (data.label) data.label.element.classList.toggle("hot", Boolean(hot));
          // Parameter labels appear with their step
          if (data.node.kind === "parameter") {
            const near = hot || state.hovered?.step?.step === data.node.step.step || state.selected === data.node.step.step;
            data.label.element.classList.toggle("hidden", !near);
          }
        });
        content.spinning.forEach((object, index) => (object.rotation.z += 0.002 + index * 0.0002));
        content.flows.forEach((flow) => flow.particle.position.copy(flow.curve.getPoint(((now / 1597 + flow.offset) % 1))));
      }

      // Camera flight to a node
      if (state.flight) {
        const t = EASE(Math.min(1, (now - state.flight.start) / 610));
        camera.position.lerpVectors(state.flight.fromCamera, state.flight.toCamera, t);
        controls.target.lerpVectors(state.flight.fromTarget, state.flight.toTarget, t);
        if (t >= 1) state.flight = null;
      }

      controls.update();
      composer.render();
      labelRenderer.render(scene, camera);
    }
    frame = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      renderer.domElement.removeEventListener("pointermove", onMove);
      renderer.domElement.removeEventListener("pointerdown", onDown);
      renderer.domElement.removeEventListener("pointerup", onUp);
      if (state.content) dispose(state.content.group);
      controls.dispose();
      composer.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  // Plan, theme, or parameters changed: rebuild the objects, keep the camera
  useEffect(() => {
    const state = world.current;
    const colors = readColors();
    const firstBuild = !state.content;
    if (state.content) {
      state.scene.remove(state.content.group);
      dispose(state.content.group);
    }

    // Bloom only on dark backgrounds, where light can glow
    state.scene.background = colors.bg;
    state.scene.fog = new THREE.Fog(colors.bg, 89, 377);
    state.bloom.enabled = theme !== "light";
    state.content = { ...buildScene(plan, title, colors, showParameters, state.size, theme === "light"), builtAt: firstBuild ? performance.now() : performance.now() - 2000 };
    state.scene.add(state.content.group);
    if (firstBuild) fit(false);
  }, [plan, title, theme, showParameters]);

  useEffect(() => {
    world.current.onSelect = onSelect;
  }, [onSelect]);

  useEffect(() => {
    world.current.controls.autoRotate = rotate;
  }, [rotate]);

  // Selection: fly to the step
  useEffect(() => {
    const state = world.current;
    state.selected = selected;
    if (!selected) return;
    const holder = state.content?.group.children.find((child) => child.userData.node?.step?.step === selected && child.userData.node.kind === "step");
    if (!holder) return;
    const target = holder.position.clone();
    const direction = state.camera.position.clone().sub(state.controls.target).normalize();
    state.flight = {
      start: performance.now(),
      fromCamera: state.camera.position.clone(),
      toCamera: target.clone().add(direction.multiplyScalar(55)),
      fromTarget: state.controls.target.clone(),
      toTarget: target,
    };
    setRotate(false);
  }, [selected]);

  function fit(animate = true) {
    const state = world.current;
    const sphere = state.content.bounds;
    const distance = Math.max(55, ((sphere.radius + 13) / Math.sin(THREE.MathUtils.degToRad(state.camera.fov / 2))) * 0.8);
    const toCamera = sphere.center.clone().add(new THREE.Vector3(0.45, 0.5, 1).normalize().multiplyScalar(distance));
    if (!animate) {
      state.camera.position.copy(toCamera);
      state.controls.target.copy(sphere.center);
      return;
    }
    state.flight = { start: performance.now(), fromCamera: state.camera.position.clone(), toCamera, fromTarget: state.controls.target.clone(), toTarget: sphere.center };
  }

  const step = plan.steps.find((item) => item.step === selected);

  return (
    <section className="graph" aria-label="Nodes">
      <div className="graph-canvas" ref={container} />
      <div className="graph-labels" ref={labels} />

      <div className="graph-toolbar">
        <button className="icon-button" onClick={() => fit()} title="Fit" aria-label="Fit">
          <Crosshair size={16} />
        </button>
        <button className={`icon-button ${showParameters ? "active" : ""}`} onClick={() => setShowParameters(!showParameters)} title="Parameters" aria-label="Parameters">
          <Waypoints size={16} />
        </button>
        <button className="icon-button" onClick={() => setRotate(!rotate)} title={rotate ? "Stop rotation" : "Rotate"} aria-label="Rotation">
          {rotate ? <Pause size={15} /> : <Play size={15} />}
        </button>
        <button className="icon-button" onClick={onClose} title="Close (Esc)" aria-label="Close">
          <X size={17} />
        </button>
      </div>

      {!step && (
        <div className="graph-legend">
          <span>
            <i style={{ background: "var(--accent)" }} /> ready
          </span>
          <span>
            <i style={{ background: "var(--warn)" }} /> needs input
          </span>
          <span>
            <i style={{ background: "var(--danger)" }} /> blocked
          </span>
        </div>
      )}

      {caption && (
        <div className="caption">
          {caption.split("\n").map((line, index) => (
            <p key={index}>{line}</p>
          ))}
        </div>
      )}

      {step && <NodePanel key={`${plan.id}-${step.step}`} step={step} onEdit={onEdit} onClose={() => onSelect(null)} />}
    </section>
  );
}

// Choices use their exact value, other fields the readable one (5 GB, 30 days)
function initialValue(step, item) {
  const source = item.kind === "choice" ? step.exact : step.parameters;
  return source[item.name] ?? "";
}

function NodePanel({ step, onEdit, onClose }) {
  const [values, setValues] = useState(() => Object.fromEntries(step.schema.map((item) => [item.name, initialValue(step, item)])));
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(null);

  async function apply(name) {
    setSaving(name);
    setError(null);
    try {
      await onEdit(step.step, name, values[name]);
    } catch (problem) {
      setError(String(problem));
    } finally {
      setSaving(null);
    }
  }

  return (
    <aside className="node-panel">
      <header>
        <div>
          <span className="eyebrow">Step {step.step}</span>
          <h3>{step.action ?? "no action"}</h3>
        </div>
        <button className="icon-button small" onClick={onClose} title="Close" aria-label="Close">
          <X size={13} />
        </button>
      </header>

      <p className="detail">{step.clause}</p>
      {step.types && <code>{step.types}</code>}

      {step.schema.map((item) => (
        <label key={item.name} className="node-field">
          <span>
            {item.name}
            {item.required && <em> · required</em>}
          </span>
          <div className="node-input">
            {item.kind === "choice" ? (
              <select value={values[item.name]} onChange={(event) => setValues({ ...values, [item.name]: event.target.value })}>
                <option value="">—</option>
                {item.choices.map((choice) => (
                  <option key={choice} value={choice}>
                    {choice}
                  </option>
                ))}
              </select>
            ) : (
              <input
                value={values[item.name]}
                placeholder={item.kind === "size" ? "5 GB" : item.kind === "duration" ? "30 days" : ""}
                onChange={(event) => setValues({ ...values, [item.name]: event.target.value })}
                onKeyDown={(event) => event.key === "Enter" && apply(item.name)}
              />
            )}
            <button className="button" onClick={() => apply(item.name)} disabled={saving !== null || values[item.name] === initialValue(step, item)}>
              {saving === item.name ? "…" : "Set"}
            </button>
          </div>
        </label>
      ))}

      {error && <p className="error">{error}</p>}
      {step.questions.length > 0 && <p className="node-note">{step.questions.join(" ")}</p>}
    </aside>
  );
}
