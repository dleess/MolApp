// Run with: node --test tests/viewer_state_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const script = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/viewer.html'), 'utf8')
  .match(/<script>\s*([\s\S]*?)<\/script>/)[1];

function viewer() {
  const events = [], marked = new Set(), structures = [], cells = new Map();
  let focus = null;
  const interactivity = {
    props: { granularity: 'residue' },
    setProps(props) { this.props = { ...this.props, ...props }; },
    lociHighlights: { clearHighlights() {}, highlightOnly() {} },
    lociSelects: {
      deselectAll: () => marked.clear(),
      select: ({ loci }) => marked.add(loci.id),
      deselect: ({ loci }) => marked.delete(loci.id)
    }
  };
  const lib = {
    Structure: { toStructureElementLoci: data => ({ structure: data }) },
    StructureElement: {
      Bundle: { fromLoci: loci => ({ hash: loci.structure.hashCode }) },
      Loci: {
        is: loci => loci.kind === 'element-loci', isEmpty: () => false,
        firstElement: loci => loci, areEqual: (a, b) => a.id === b.id,
        remap: (loci, structure) => ({ ...loci, structure }), getFirstLocation: loci => loci
      }
    },
    StructureProperties: {
      atom: { label_atom_id: loc => loc.id },
      residue: { label_comp_id: () => 'ALA', auth_seq_id: () => 1 },
      chain: { auth_asym_id: () => 'A' }, unit: { model_num: () => 1 }
    }
  };
  const plugin = {
    managers: { interactivity, animation: { async stop() {} }, structure: {
      hierarchy: { current: { structures } }, measurement: {},
      focus: { clear: () => { focus = null; } }
    } },
    canvas3d: { props: { renderer: { backgroundColor: 0xFFFFFF } },
      setProps(props) { this.props = { ...this.props, ...props }; } },
    state: {
      getSnapshot: () => ({
        interactivity: { props: { ...interactivity.props } }, structureFocus: focus,
        canvas3d: { props: structuredClone(plugin.canvas3d.props) }
      }),
      async setSnapshot(snap) {
        if (snap.interactivity) interactivity.setProps(snap.interactivity.props);
        focus = snap.structureFocus;
        if (snap.canvas3d) plugin.canvas3d.setProps(snap.canvas3d.props);
      },
      data: { cells, build() {
        const refs = [];
        return { delete(ref) { refs.push(ref); return this; }, async commit() {
          refs.forEach(ref => cells.delete(ref));
        } };
      } }
    }
  };
  const app = { viewer: { plugin }, objects: Object.create(null), ligandResns: [], visibility: {},
    undoStack: [], redoStack: [], measurePending: [], measureMode: false, backgroundColor: '#FFFFFF' };
  const window = { molapp: app, molstar: { lib: { structure: lib } }, addEventListener() {},
    molappPostMessage: json => events.push(JSON.parse(json)) };
  const element = { addEventListener() {}, classList: { add() {} } };
  const context = vm.createContext({ window, console, setTimeout, document: { getElementById: () => element } });
  vm.runInContext(script.replace('initializeViewer().catch(showError);',
    'globalThis.state = { snapshotMolApp, restoreMolApp, serializeMolAppState, deserializeMolAppState, handleMeasurePick, handleNativeCommand };'), context);
  return { state: context.state, app, plugin, events, marked, cells, structures,
    setFocus: value => { focus = value; }, getFocus: () => focus };
}

for (const method of ['restoreMolApp', 'deserializeMolAppState']) {
  test(method + ' clears transient measure granularity and Mol* focus', async () => {
    const h = viewer();
    h.app.measureMode = true;
    h.app.prevGranularity = 'residue';
    h.plugin.managers.interactivity.setProps({ granularity: 'element' });
    h.setFocus('focused residue');
    const saved = method === 'restoreMolApp' ? h.state.snapshotMolApp() : await h.state.serializeMolAppState();
    await h.state[method](saved);
    assert.equal(h.app.measureMode, false);
    assert.equal(h.plugin.managers.interactivity.props.granularity, 'residue');
    assert.equal(h.getFocus(), null);
  });
}

test('undo restores background metadata before saving the restored scene', async () => {
  const h = viewer();
  const snapshot = h.state.snapshotMolApp();
  h.app.backgroundColor = '#000000';
  h.plugin.canvas3d.setProps({ renderer: { backgroundColor: 0 } });
  await h.state.restoreMolApp(snapshot);
  const saved = JSON.parse(await h.state.serializeMolAppState());
  assert.equal(saved.backgroundColor, '#FFFFFF');
  assert.equal(saved.molstar.canvas3d.props.renderer.backgroundColor, 0xFFFFFF);
});

test('state loads rebuild selection bundles on the current parent and retain ligand identity', async () => {
  const h = viewer();
  const parent = { cell: { transform: { ref: 'parent' }, state: {}, obj: { label: 'parent', data: { hashCode: 100 } } }, components: [] };
  const component = { cell: { transform: { ref: 'component', tags: ['structure-component-molapp-ATP'] }, state: {}, obj: { label: 'ATP', data: { hashCode: 200 } } } };
  parent.components.push(component);
  h.structures.push(parent);
  await h.state.deserializeMolAppState(JSON.stringify({ version: 1, molstar: {}, visibility: {}, ligandResns: ['ATP'], objects: [
    { name: 'parent', type: 'structure', structureRef: 'parent', isVisible: true },
    { name: 'ATP', type: 'selection', parentRef: 'parent', ligandResn: 'ATP', isVisible: true }
  ] }));
  assert.equal(h.app.objects.ATP.bundle.hash, 100);
  assert.equal(h.app.objects.ATP.loci.structure, parent.cell.obj.data);
  assert.equal(h.app.objects.ATP.parentRef, 'parent');
  assert.equal(h.app.objects.ATP.ligandResn, 'ATP');
});

test('undo reports unavailable structures without restoring phantom object rows', async () => {
  const h = viewer();
  const parent = { cell: { transform: { ref: 'missing' }, state: {}, obj: { label: 'offline.pdb' } }, components: [] };
  h.structures.push(parent);
  h.app.objects['offline.pdb'] = { type: 'structure', structureRef: parent };
  const snapshot = h.state.snapshotMolApp();
  h.plugin.state.setSnapshot = async () => { h.structures.length = 0; };
  await assert.rejects(h.state.restoreMolApp(snapshot), /Could not load: offline.pdb/);
  assert.equal(Object.keys(h.app.objects).length, 0);
});

test('a completed atom pair is queued before Clear Measurements and Save', async () => {
  const h = viewer();
  h.app.measureMode = true;
  h.app.measureKind = 'distance';
  let finish;
  h.plugin.managers.structure.measurement.addDistance = () => new Promise(resolve => {
    finish = () => {
      h.cells.set('distance', { transform: { ref: 'distance', tags: ['measurement-group'] } });
      resolve();
    };
  });
  h.state.handleMeasurePick({ kind: 'element-loci', id: 'A' });
  h.state.handleMeasurePick({ kind: 'element-loci', id: 'B' });
  await Promise.resolve();
  let saved = false;
  const saving = h.state.serializeMolAppState().then(() => { saved = true; });
  const clearing = h.state.handleNativeCommand({ command: 'clearMeasurements', payload: {} });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(saved, false, 'Save must wait for the in-flight measurement');
  finish();
  await Promise.all([saving, clearing]);
  assert.equal(h.cells.size, 0, 'late measurement must not resurrect after Clear Measurements');
});

test('a repeated atom starting the next measurement keeps its pending mark', async () => {
  const h = viewer();
  h.app.measureMode = true;
  h.app.measureKind = 'distance';
  let finish;
  h.plugin.managers.structure.measurement.addDistance = () => new Promise(resolve => { finish = resolve; });
  h.state.handleMeasurePick({ kind: 'element-loci', id: 'A' });
  h.state.handleMeasurePick({ kind: 'element-loci', id: 'B' });
  await Promise.resolve();
  h.state.handleMeasurePick({ kind: 'element-loci', id: 'A' });
  finish();
  await h.state.serializeMolAppState();
  assert.equal(h.app.measurePending.length, 1);
  assert.ok(h.marked.has('A'), 'completion must not remove the new pending mark on atom A');
});

for (const command of ['undo', 'redo']) {
  test(command + ' retains a recovery snapshot when a restore partially mutates the scene', async () => {
    const h = viewer();
    const source = command === 'undo' ? h.app.undoStack : h.app.redoStack;
    const destination = command === 'undo' ? h.app.redoStack : h.app.undoStack;
    const target = { version: 1, molstar: {}, objects: [
      { name: 'offline.pdb', type: 'structure', structureRef: 'unavailable' }
    ], ligandResns: [], visibility: {}, backgroundColor: '#000000' };
    source.push(target);
    h.plugin.state.setSnapshot = async () => {};
    await h.state.handleNativeCommand({ command, payload: {} });
    assert.equal(h.events.at(-1).success, false);
    assert.equal(h.app.backgroundColor, '#000000', 'the failing restore partially applied its scene');
    assert.equal(source.length, 0, 'the partially applied entry must not be attempted repeatedly');
    assert.equal(destination.length, 1, 'the opposite action must restore the pre-attempt scene');
    await h.state.handleNativeCommand({ command: command === 'undo' ? 'redo' : 'undo', payload: {} });
    assert.equal(h.events.at(-1).success, true);
    assert.equal(h.app.backgroundColor, '#FFFFFF');
  });

  test(command + ' retains its existing history when snapshot restoration rejects without mutation', async () => {
    const h = viewer();
    const source = command === 'undo' ? h.app.undoStack : h.app.redoStack;
    const destination = command === 'undo' ? h.app.redoStack : h.app.undoStack;
    const target = h.state.snapshotMolApp();
    source.push(target);
    h.plugin.state.setSnapshot = async () => { throw new Error('restore rejected'); };
    await h.state.handleNativeCommand({ command, payload: {} });
    assert.equal(h.events.at(-1).success, false);
    assert.equal(source.length, 1);
    assert.equal(source[0], target);
    assert.equal(destination.length, 0);
  });
}

test('saved states omit transient animations and legacy states cannot restart them', async () => {
  const h = viewer();
  const getSnapshot = h.plugin.state.getSnapshot;
  h.plugin.state.getSnapshot = options => ({ ...getSnapshot(),
    animation: options?.animation === false ? undefined : { state: { animationState: 'playing' } }
  });
  const snapshot = h.state.snapshotMolApp();
  assert.equal(snapshot.molstar.animation, undefined, 'new snapshots must exclude transient morph state');
  let animating = false;
  h.plugin.state.setSnapshot = async saved => {
    // Mol* AnimationManager.setSnapshot resumes animationState:playing independently of startAnimation.
    animating = Boolean(saved.animation) || saved.startAnimation === true || Boolean(saved.transition?.autoplay);
  };
  const legacy = { ...snapshot, molstar: { animation: { state: { animationState: 'playing' } }, startAnimation: true, transition: { autoplay: true } } };
  await h.state.deserializeMolAppState(JSON.stringify(legacy));
  assert.equal(animating, false);
  assert.equal(h.app.morphing, false);
});
