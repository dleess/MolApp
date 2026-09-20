// Run with: node --test tests/viewer_math_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const html = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/viewer.html'), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
// Evaluate the shipped animation definition so its global targeting and completion behavior
// remain part of the regression, rather than reproducing that behavior in a mock.
const bundle = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/molstar/molstar.js'), 'utf8');
const animationStart = bundle.indexOf('name:"built-in.animate-model-index"') - 1;
const trajectoryAnimation = vm.runInNewContext('(' + bundle.slice(animationStart,
  bundle.indexOf(');var ', animationStart)) + ')', {
  Ir: { Generators: { ofTransformer() {} }, findAncestorOfType: (_tree, cells, ref) => cells.get(ref).trajectory.cell },
  Ze: { Model: { ModelFromTrajectory: {} } }, ae: { Molecule: { Trajectory: {} } },
  ht: { State: { Update: async (_plugin, { tree }) => tree.commit() } }
});
const points = [[0, 0, 0], [1, 1, 0], [2, 0, 1], [0, 2, 3]];
const translate = (data, matrix) => ({ units: data.units.map(unit => ({ ...unit,
  points: unit.points.map(p => [0, 1, 2].map(i =>
    matrix[i] * p[0] + matrix[4 + i] * p[1] + matrix[8 + i] * p[2] + matrix[12 + i]))
})) });

function viewer() {
  const structures = [], trajectories = [], cells = new Map();
  let nextRef = 0, insertions = 0, playing;
  const plugin = {
    managers: {
      structure: { hierarchy: { current: { structures, trajectories } } },
      camera: { reset: async () => {} },
      animation: {
        animations: [trajectoryAnimation],
        play: async (animation, params) => { playing = { animation, params }; }
      }
    },
    runTask: async task => task,
    state: { data: { cells, select: () => structures.map(s => s.model.cell),
      updateTree: builder => builder.commit(), build() {
      let target;
      const builder = {
        to(value) { target = typeof value === 'string' ? cells.get(value) : value; return this; },
        update(transformer, edit) {
          if (typeof transformer === 'function') target.params = transformer(target.params);
          else if (edit) edit(target.params);
          else Object.assign(target.params, transformer);
          return this;
        },
        insert(transformer, params) {
          insertions++;
          const s = structures.find(s => s.cell === target);
          const cell = { transform: { ref: 'transform-' + ++nextRef }, params };
          s.transforms.unshift(cell);
          cells.set(cell.transform.ref, cell);
          builder.ref = cell.transform.ref;
          return builder;
        },
        async commit() {
          for (const s of structures) {
            let data = s.cell.obj.data;
            let parent = s.cell.transform.ref;
            for (const cell of s.transforms) {
              cell.transform.parent = parent;
              parent = cell.transform.ref;
              data = translate(data, cell.params.transform.params.data);
              cell.obj = { data };
              s.transform = { cell };
            }
          }
        }
      };
      return builder;
    } } }
  };
  const window = {
    molapp: { viewer: { plugin }, objects: Object.create(null) }, addEventListener() {},
    molstar: { lib: {
      plugin: { StateTransforms: { Model: { TransformStructureConformation: {} } } },
      structure: {
        StructureElement: { Location: { create: () => ({}) } },
        StructureProperties: {
          atom: { label_atom_id: () => 'CA', type_symbol: l => l.unit.symbols?.[l.element] || 'C',
            x: l => l.unit.points[l.element][0], y: l => l.unit.points[l.element][1],
            z: l => l.unit.points[l.element][2] },
          chain: { auth_asym_id: () => 'A' },
          residue: { auth_seq_id: l => l.element + 1, label_comp_id: () => 'ALA' }
        }
      }
    } }
  };
  const context = vm.createContext({ window, console,
    document: { getElementById: () => ({ addEventListener() {} }) } });
  vm.runInContext(script.replace('initializeViewer().catch(showError);',
    'globalThis.core = { commandHandlers, kabschTransform, rmsdAfterTransform };'), context);
  function addStructure(name, offset = 0, frameCount = 1) {
    const trajectory = { cell: { obj: { data: { frameCount } } } };
    const model = { trajectory, cell: { transform: { ref: 'model-' + name }, params: { modelIndex: 0 }, trajectory } };
    const data = { units: [{ kind: 0, elements: points.map((_, i) => i),
      points: points.map(p => [p[0] + offset, p[1], p[2]]) }] };
    const cell = { transform: { ref: name }, state: {}, obj: { label: name, data } };
    const s = { cell, model, transforms: [] };
    cells.set(name, cell);
    cells.set(model.cell.transform.ref, model.cell);
    structures.push(s);
    trajectories.push(trajectory);
    window.molapp.objects[name] = { type: 'structure', structureRef: s };
    return s;
  }
  return { core: context.core, app: window.molapp, plugin, addStructure,
    insertions: () => insertions, playing: () => playing };
}

test('superposition stays aligned when an already transformed structure becomes reference', async () => {
  const { core, addStructure } = viewer();
  addStructure('A');
  const b = addStructure('B', 10), c = addStructure('C', 20);
  await core.commandHandlers.superpose({ targets: ['A', 'B', 'C'] });
  await core.commandHandlers.superpose({ targets: ['B', 'C'] });
  assert.equal(c.transform.cell.obj.data.units[0].points[0][0], b.transform.cell.obj.data.units[0].points[0][0]);
});

test('superposition reuses a decorator restored from a saved state without a JS ref cache', async () => {
  const { core, app, addStructure, insertions } = viewer();
  addStructure('A');
  const b = addStructure('B', 10);
  await core.commandHandlers.superpose({ targets: ['A', 'B'] });
  delete app.superposeRefs; // A fresh viewer has no transient ref cache after loading a snapshot.
  await core.commandHandlers.superpose({ targets: ['A', 'B'] });
  assert.equal(insertions(), 1, 'an existing Mol* decorator must be updated rather than inserted again');
  assert.equal(b.transform.cell.obj.data.units[0].points[0][0], 0);
});

test('superposition refits saved structures with multiple decorators', async () => {
  const { core, plugin, addStructure, insertions } = viewer();
  addStructure('A');
  const b = addStructure('B', 10);
  await core.commandHandlers.superpose({ targets: ['A', 'B'] });
  const matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -10, 0, 0, 1];
  // Older saved states could contain repeated decorators after a cold restore and refit.
  await plugin.state.data.build().to(b.cell).insert({}, {
    transform: { name: 'matrix', params: { data: matrix, transpose: false } }
  }).commit();
  assert.equal(b.transform.cell.obj.data.units[0].points[0][0], -10);
  for (let i = 0; i < 2; i++) {
    await core.commandHandlers.superpose({ targets: ['A', 'B'] });
    assert.equal(b.transform.cell.obj.data.units[0].points[0][0], 0);
  }
  assert.equal(insertions(), 2, 'reuse the last decorator without removing prior state nodes');
});

test('Kabsch recovers rigid rotations and translations', () => {
  const { core } = viewer();
  for (let i = 0; i < 12; i++) {
    const a = i * Math.PI / 6, c = Math.cos(a), s = Math.sin(a);
    const reference = points.map(([x, y, z]) => [c * x - s * y + 7, s * x + c * y - 4, z + 3]);
    assert.ok(core.rmsdAfterTransform(points, reference, core.kabschTransform(points, reference)) < 1e-10);
  }
});

test('superposition excludes calcium ions named CA from the C-alpha core', async () => {
  const { core, app, addStructure } = viewer();
  const reference = addStructure('reference'), mobile = addStructure('mobile', 10);
  for (const structure of [reference, mobile]) {
    const unit = structure.cell.obj.data.units[0];
    unit.elements.push(4);
    unit.points.push([structure === mobile ? 12.5 : 2, 2, 2]);
    unit.symbols = ['C', 'C', 'C', 'C', 'CA'];
  }
  await core.commandHandlers.superpose({ targets: ['reference', 'mobile'] });
  assert.equal(app.superposeCore, 4);
  assert.ok(app.superposeRmsd < 1e-10, 'calcium positions must not distort the protein alignment');

  reference.cell.obj.data.units[0].symbols.fill('CA');
  await assert.rejects(core.commandHandlers.superpose({ targets: ['reference', 'mobile'] }), /no Cα/);
});

test('non-looping morph uses a finite animation mode', async () => {
  const { core, addStructure, playing } = viewer();
  addStructure('ensemble', 0, 5);
  await core.commandHandlers.startMorph({ targets: ['ensemble'], loop: false });
  assert.equal(playing().params.mode.name, 'once');
});

test('morph rejects a static target even if an unrelated ensemble is loaded', async () => {
  const { core, addStructure } = viewer();
  addStructure('static');
  addStructure('hidden-ensemble', 0, 5);
  await assert.rejects(core.commandHandlers.startMorph({ targets: ['static'] }), /multi-model/);
});

test('morph advances only targeted models and finishes after the requested duration', async () => {
  const { core, plugin, addStructure, playing } = viewer();
  const visible = addStructure('visible', 0, 5), hidden = addStructure('hidden', 0, 8);
  await core.commandHandlers.startMorph({ targets: ['visible'], loop: false, durationInS: 5 });
  const { animation, params } = playing();
  const half = await animation.apply({}, { current: 2500 }, { plugin, params });
  assert.equal(half.kind, 'next');
  assert.equal(visible.model.cell.params.modelIndex, 2);
  assert.equal(hidden.model.cell.params.modelIndex, 0);
  const end = await animation.apply({}, { current: 5000 }, { plugin, params });
  assert.equal(end.kind, 'finished');
  assert.equal(visible.model.cell.params.modelIndex, 4);
});

test('looping morph wraps only its targets', async () => {
  const { core, plugin, addStructure, playing } = viewer();
  const visible = addStructure('visible', 0, 5), hidden = addStructure('hidden', 0, 8);
  await core.commandHandlers.startMorph({ targets: ['visible'], loop: true, durationInS: 5 });
  const { animation, params } = playing();
  const result = await animation.apply({}, { current: 6250 }, { plugin, params });
  assert.equal(hidden.model.cell.params.modelIndex, 0);
  assert.equal(visible.model.cell.params.modelIndex, 1);
  assert.equal(result.kind, 'next');
});

test('morph rejects invalid duration before starting', async () => {
  const { core, addStructure } = viewer();
  addStructure('ensemble', 0, 5);
  for (const durationInS of [0, -1, '5', Infinity]) {
    await assert.rejects(core.commandHandlers.startMorph({ targets: ['ensemble'], durationInS }), /duration/i);
  }
});
