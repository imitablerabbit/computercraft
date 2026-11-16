// The 3D view of the world with three.js: blocks as one instanced mesh,
// turtles as small boxes with a face and a label, orbit camera.
// World axes: x east, y north, z up. three.js: x east, y up, z south.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { BLOCKS } from './world.js';

const TURTLE_COLORS = ['#e8c547', '#5fb0e8', '#8ad15f', '#e87f5f', '#c08ae8', '#5fe0d0'];

// How a block is drawn: its size in world axes (east, north, up), how
// far its centre sits below the cell's, and its colour, which for some
// blocks follows their state (a lit lamp, a pressed button, a crop's
// age, powered wire).
function blockShape(type, meta, def) {
  const m = meta || {};
  const box = (sx, sy, sz, color) => ({ sx, sy, sz, dz: -(1 - sz) / 2, color: color || def.color });
  switch (type) {
    case 'torch': return { sx: 0.2, sy: 0.2, sz: 0.6, dz: -0.2, color: def.color };
    case 'wheat': case 'carrots': case 'potatoes': {
      const age = m.age || 0;
      const young = new THREE.Color('#4f9a2c');
      const ripe = new THREE.Color(def.color);
      return box(0.7, 0.7, 0.2 + age * 0.09, '#' + young.lerp(ripe, age / 7).getHexString());
    }
    case 'farmland': return box(1, 1, 0.94);
    case 'rail': return box(0.9, 0.9, 0.08);
    case 'redstone_wire': return box(0.9, 0.9, 0.06, m.power ? '#ff3b22' : '#7a1a10');
    case 'lever': return box(0.25, 0.25, 0.4, m.on ? '#e0c060' : def.color);
    case 'button': return box(0.3, 0.3, 0.15, m.on ? '#e06030' : def.color);
    case 'pressure_plate': return box(0.85, 0.85, m.on ? 0.04 : 0.08, m.on ? '#7a7a7a' : def.color);
    case 'daylight_sensor': return box(1, 1, 0.4);
    case 'redstone_lamp': return box(1, 1, 1, m.lit ? '#ffd56b' : def.color);
    case 'door': {
      // a slab across the doorway when shut, along the side when open
      const across = (m.facing ?? 0) % 2 === 0;
      const thin = across !== !!m.open;
      return { sx: thin ? 1 : 0.2, sy: thin ? 0.2 : 1, sz: 1, dz: 0, color: m.open ? '#9fb0c0' : def.color };
    }
    case 'wireless_modem': return box(0.5, 0.5, 0.5);
    case 'cable': return { sx: 0.35, sy: 0.35, sz: 0.35, dz: 0, color: def.color };
    case 'bundled_cable': return box(0.45, 0.45, 0.25);
    default: return { sx: 1, sy: 1, sz: 1, dz: 0, color: def.color };
  }
}

function labelSprite(text) {
  const canvas = document.createElement('canvas');
  canvas.width = 256; canvas.height = 64;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = 'rgba(0,0,0,0.55)';
  ctx.fillRect(0, 0, 256, 64);
  ctx.font = 'bold 30px system-ui, sans-serif';
  ctx.fillStyle = '#fff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, 128, 32);
  const tex = new THREE.CanvasTexture(canvas);
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false }));
  sprite.scale.set(2, 0.5, 1);
  return sprite;
}

export class View3D {
  constructor(container, sim, onSelectTurtle) {
    this.container = container;
    this.sim = sim;
    this.onSelectTurtle = onSelectTurtle;
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    container.appendChild(this.renderer.domElement);
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#1b2330');
    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, 500);
    this.camera.position.set(14, 16, 18);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.1;
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.55));
    const sun = new THREE.DirectionalLight(0xffffff, 1.1);
    sun.position.set(20, 40, 10);
    this.scene.add(sun);
    const fill = new THREE.DirectionalLight(0x99aaff, 0.35);
    fill.position.set(-20, 10, -30);
    this.scene.add(fill);
    this.blockMesh = null;
    this.blockKeys = [];
    this.blockVersion = -1;
    this.tool = 'select';      // select | place | use | remove | turtle | computer | monitor
    this.placeType = 'stone';
    // onEdit({ tool, x, y, z, normal, turtleId }): x, y, z is the clicked
    // block (remove, use) or the free cell in front of the clicked face
    // (the others); normal is the face direction in world axes.
    this.onEdit = null;
    this.turtleMeshes = new Map();
    this.selectedTurtle = null;
    this.follow = false;
    this.raycaster = new THREE.Raycaster();
    this.resize();
    new ResizeObserver(() => this.resize()).observe(container);
    this.renderer.domElement.addEventListener('pointerdown', (e) => { this._down = [e.clientX, e.clientY]; });
    this.renderer.domElement.addEventListener('pointerup', (e) => {
      if (!this._down || Math.hypot(e.clientX - this._down[0], e.clientY - this._down[1]) > 4) return;
      this.pick(e);
    });
  }

  resize() {
    const w = this.container.clientWidth || 1, h = this.container.clientHeight || 1;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // Called after a scenario loads: point the camera at the world.
  reset() {
    this.blockVersion = -1;
    for (const m of this.turtleMeshes.values()) this.scene.remove(m);
    this.turtleMeshes.clear();
    const world = this.sim.world;
    let cx = 0, cy = 0, cz = 0, n = 0;
    for (const t of world.turtles.values()) { cx += t.x; cy += t.y; cz += t.z; n++; }
    if (n === 0) { cx = 0; cy = 0; cz = 1; n = 1; }
    const target = this.toScene(cx / n, cy / n, cz / n);
    this.controls.target.copy(target);
    this.camera.position.set(target.x + 12, target.y + 12, target.z + 14);
    this.controls.update();
  }

  toScene(x, y, z) { return new THREE.Vector3(x, z, -y); }

  rebuildBlocks() {
    const world = this.sim.world;
    if (this.blockMesh) { this.scene.remove(this.blockMesh); this.blockMesh.geometry.dispose(); this.blockMesh.material.dispose(); }
    const count = world.blocks.size;
    const geometry = new THREE.BoxGeometry(1, 1, 1);
    const material = new THREE.MeshLambertMaterial();
    const mesh = new THREE.InstancedMesh(geometry, material, Math.max(1, count));
    const m = new THREE.Matrix4();
    const color = new THREE.Color();
    const quaternion = new THREE.Quaternion();
    let i = 0;
    this.blockKeys = [];
    for (const [k, type] of world.blocks) {
      this.blockKeys[i] = k;
      const [x, y, z] = k.split(',').map(Number);
      const def = BLOCKS[type] || { color: '#ff00ff' };
      const shape = blockShape(type, world.meta.get(k), def);
      // scene axes: x east, y up, z south
      m.compose(this.toScene(x, y, z + shape.dz), quaternion, new THREE.Vector3(shape.sx, shape.sz, shape.sy));
      mesh.setMatrixAt(i, m);
      // a little variation so neighbouring blocks are distinguishable
      color.set(shape.color);
      const h = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 0xff;
      color.offsetHSL(0, 0, (h / 255 - 0.5) * 0.06);
      mesh.setColorAt(i, color);
      i++;
    }
    mesh.count = count;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    this.scene.add(mesh);
    this.blockMesh = mesh;
    this.blockVersion = world.version;
  }

  turtleMesh(t) {
    let g = this.turtleMeshes.get(t.id);
    if (g) return g;
    g = new THREE.Group();
    const color = TURTLE_COLORS[t.id % TURTLE_COLORS.length];
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.8, 0.8), new THREE.MeshLambertMaterial({ color }));
    g.add(body);
    const face = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.06), new THREE.MeshLambertMaterial({ color: '#222' }));
    face.position.set(0, 0, -0.42);
    g.add(face);
    const eye = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.12, 0.04), new THREE.MeshBasicMaterial({ color: '#7fe3ff' }));
    eye.position.set(0, 0.08, -0.46);
    g.add(eye);
    const label = labelSprite(`${t.label || 'Turtle'} #${t.id}`);
    label.position.set(0, 0.9, 0);
    g.add(label);
    g.userData.turtleId = t.id;
    this.scene.add(g);
    this.turtleMeshes.set(t.id, g);
    return g;
  }

  pick(e) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    const p = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    this.raycaster.setFromCamera(p, this.camera);
    const turtleHit = () => {
      const hits = this.raycaster.intersectObjects([...this.turtleMeshes.values()], true);
      for (const h of hits) {
        let o = h.object;
        while (o && o.userData.turtleId === undefined) o = o.parent;
        if (o) return { id: o.userData.turtleId, distance: h.distance };
      }
      return null;
    };
    if (this.tool === 'select') {
      const t = turtleHit();
      if (t) this.onSelectTurtle(t.id);
      return;
    }
    if (!this.blockMesh || !this.onEdit) return;
    const hit = this.raycaster.intersectObject(this.blockMesh)[0];
    const t = turtleHit();
    if (this.tool === 'remove') {
      if (t && (!hit || t.distance < hit.distance)) { this.onEdit({ tool: 'remove', turtleId: t.id }); return; }
      if (!hit || hit.instanceId === undefined) return;
      const [x, y, z] = this.blockKeys[hit.instanceId].split(',').map(Number);
      this.onEdit({ tool: 'remove', x, y, z });
      return;
    }
    if (!hit || hit.instanceId === undefined) return;
    const [x, y, z] = this.blockKeys[hit.instanceId].split(',').map(Number);
    if (this.tool === 'use') { this.onEdit({ tool: 'use', x, y, z }); return; }
    // the clicked face's normal, back in world axes (scene y is up,
    // scene z points south)
    const n = hit.face.normal;
    const normal = { x: Math.round(n.x), y: Math.round(-n.z), z: Math.round(n.y) };
    this.onEdit({ tool: this.tool, x: x + normal.x, y: y + normal.y, z: z + normal.z, normal });
  }

  setSelected(id) {
    this.selectedTurtle = id;
    for (const [tid, g] of this.turtleMeshes) {
      g.children[0].material.emissive = new THREE.Color(tid === id ? '#443300' : '#000000');
    }
  }

  update() {
    const world = this.sim.world;
    if (world.version !== this.blockVersion) this.rebuildBlocks();
    for (const [id, g] of this.turtleMeshes) {
      if (!world.turtles.has(id)) { this.scene.remove(g); this.turtleMeshes.delete(id); }
    }
    for (const t of world.turtles.values()) {
      const g = this.turtleMesh(t);
      const pose = world.turtlePose(t, this.sim.clock);
      g.position.copy(this.toScene(pose.x, pose.y, pose.z));
      g.rotation.y = -pose.heading * Math.PI / 2;
      if (this.follow && t.id === this.selectedTurtle) {
        const target = g.position.clone();
        const delta = target.clone().sub(this.controls.target);
        this.controls.target.copy(target);
        this.camera.position.add(delta);
      }
    }
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }
}
