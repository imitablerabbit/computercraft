// The 3D view of the world with three.js: blocks as one instanced mesh,
// turtles as small boxes with a face and a label, orbit camera.
// World axes: x east, y north, z up. three.js: x east, y up, z south.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { BLOCKS, HEADINGS } from './world.js';

const TURTLE_COLORS = ['#e8c547', '#5fb0e8', '#8ad15f', '#e87f5f', '#c08ae8', '#5fe0d0'];

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
    this.blockVersion = -1;
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
    let i = 0;
    for (const [k, type] of world.blocks) {
      const [x, y, z] = k.split(',').map(Number);
      const def = BLOCKS[type] || { color: '#ff00ff' };
      if (type === 'torch') m.compose(this.toScene(x, y, z - 0.2), new THREE.Quaternion(), new THREE.Vector3(0.2, 0.6, 0.2));
      else m.setPosition(this.toScene(x, y, z));
      mesh.setMatrixAt(i, m);
      // a little variation so neighbouring blocks are distinguishable
      color.set(def.color);
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
    const hits = this.raycaster.intersectObjects([...this.turtleMeshes.values()], true);
    for (const h of hits) {
      let o = h.object;
      while (o && o.userData.turtleId === undefined) o = o.parent;
      if (o) { this.onSelectTurtle(o.userData.turtleId); return; }
    }
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
