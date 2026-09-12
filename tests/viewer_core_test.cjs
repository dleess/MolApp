// Run with: node --test tests/viewer_core_test.cjs
// Exercise the canonical inline script; only Mol* and browser boundaries are stubbed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const html = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/viewer.html'), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];

function viewer() {
  const events = [];
  const structures = [];
  let nextRef = 0;
  const lib = {
    StructureProperties: { residue: { label_comp_id: loc => loc.element.resn } },
    Queries: { generators: { atoms: value => value } },
    StructureElement: {
      Location: { create: () => ({}) },
      Loci: {
        fromQuery: (data, query) => ({ units: data.units.map(unit => ({
          ...unit, elements: unit.elements.filter(element => query.residueTest({ element: { element } }))
        })) }),
        isEmpty: loci => loci.units.every(unit => !unit.elements.length)
      },
      Bundle: { fromLoci: loci => loci }
    },
    Structure: { toStructureElementLoci: data => data }
  };
  const plugin = {
    representation: { structure: { themes: { colorThemeRegistry: { get: () => ({ name: 'molapp-esp' }) } } } },
    managers: {
      structure: {
        hierarchy: { current: { structures }, toggleVisibility: items => {
          for (const item of items) {
            item.cell.state.isHidden = !item.cell.state.isHidden;
            for (const comp of item.components) comp.cell.state.isHidden = item.cell.state.isHidden;
          }
        } },
        component: {
          toggleVisibility: items => {
            for (const item of items) item.cell.state.isHidden = !item.cell.state.isHidden;
          },
          removeRepresentations: async items => {
            for (const item of items) item.representations = [];
          },
          updateRepresentationsTheme: async (items, theme) => {
            for (const item of items) {
              const sizeTheme = { name: item.representations[0]?.size || 'physical', params: {} };
              item.theme = typeof theme === 'function'
                ? theme(item, { cell: { transform: { params: { sizeTheme } } } }) : theme;
            }
          },
          applyPreset: async items => {
            for (const item of items) item.components = [{
              cell: { transform: { ref: 'polymer-' + ++nextRef, tags: ['structure-component-static-polymer'] },
                state: {}, obj: { data: item.cell.obj.data } }, representations: []
            }];
          }
        },
        focus: { clear() {} }
      },
      animation: { stop: async () => {} },
      interactivity: {
        lociHighlights: { clearHighlights() {} },
        lociSelects: { deselectAll() {} }
      }
    },
    builders: { structure: {
      tryCreateComponent: async (cell, params, key) => {
        const parent = structures.find(s => s.cell === cell);
        const tag = 'structure-component-' + key;
        const existing = parent.components.find(c => c.cell.transform.tags.includes(tag));
        if (existing) return existing;
        const comp = { cell: { transform: { ref: 'component-' + ++nextRef, tags: ['structure-component-' + key] },
          state: {}, obj: { label: params.label, data: params.type.name === 'static' ? cell.obj.data : params.type.params } }, representations: [] };
        comp.ref = comp.cell.transform.ref;
        parent.components.push(comp);
        return comp;
      },
      tryCreateComponentStatic: async (cell, kind, options) => plugin.builders.structure.tryCreateComponent(
        cell, { type: { name: 'static', params: kind }, label: options?.label || '' }, 'static-' + kind),
      representation: { addRepresentation: async (cell, params) => {
        const comp = structures.flatMap(s => s.components).find(c => c.cell === cell);
        comp.representations.push(params);
      } }
    } },
    state: {
      getSnapshot: () => ({ marker: 'snapshot' }),
      data: { build: () => {
        const refs = [];
        return { delete(ref) { refs.push(ref); return this; }, async commit() {
          for (const s of structures) s.components = s.components.filter(c => !refs.includes(c.cell.transform.ref));
        } };
      } }
    }
  };
  const window = {
    molstar: { lib: { structure: lib } },
    molapp: { viewer: { plugin }, objects: Object.create(null), ligandResns: [], visibility: {}, undoStack: [], redoStack: [] },
    molappPostMessage: json => events.push(JSON.parse(json)),
    addEventListener() {}
  };
  const element = { addEventListener() {}, classList: { add() {} } };
  const context = vm.createContext({ window, console, setTimeout, document: { getElementById: () => element } });
  vm.runInContext(script.replace('initializeViewer().catch(showError);',
    'globalThis.core = { commandHandlers, ensureLigandSplit, objectsMeta, queryFromAST, representationParams };'), context);
  function addStructure(name, resns) {
    const data = { units: [{ kind: 0, elements: resns.map(resn => ({ resn })) }] };
    const s = { cell: { transform: { ref: 'structure-' + ++nextRef }, state: {}, obj: { label: name, data } },
      components: [{ cell: { transform: { ref: 'lump-' + ++nextRef, tags: ['structure-component-static-ligand'] }, state: {}, obj: { data } }, representations: [] }] };
    structures.push(s);
    window.molapp.objects[name] = { type: 'structure', structureRef: s };
    return s;
  }
  return { core: context.core, app: window.molapp, plugin, events, addStructure };
}

test('ligand rows and visibility stay attached to their own loaded structure', async () => {
  const { core, app, addStructure } = viewer();
  const first = addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  const second = addStructure('second.pdb', ['ATP', 'ZN']);
  await core.ensureLigandSplit();
  const firstLigands = first.components.filter(c => c.cell.obj.label);
  const secondLigands = second.components.filter(c => c.cell.obj.label);
  assert.equal(firstLigands.length, 2, 'loading another complex must retain the first complex ligands');
  assert.equal(secondLigands.length, 2);
  assert.equal(Object.values(app.objects).filter(o => o.ligandSplit).length, 4);
  await core.commandHandlers.setObjectVisibility({ name: 'first.pdb', isVisible: false });
  for (const component of secondLigands) {
    const row = core.objectsMeta().find(o => o.name === component.cell.obj.label);
    assert.equal(row.isVisible, true, 'hiding the first structure must not hide the second ligand rows');
  }
  await core.commandHandlers.toggleVisibility({ feature: 'ligand', isVisible: false });
  assert.ok([...firstLigands, ...secondLigands].every(c => c.cell.state.isHidden));
  await core.commandHandlers.toggleVisibility({ feature: 'ligand', isVisible: true });
  assert.ok(firstLigands.every(c => c.cell.state.isHidden));
  assert.ok(secondLigands.every(c => !c.cell.state.isHidden));
});

test('split ligands coexist with a second structure containing one unsplit ligand', async () => {
  const { core, addStructure } = viewer();
  addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  const second = addStructure('second.pdb', ['ZN']);
  await core.ensureLigandSplit();
  const lump = second.components[0];
  await core.commandHandlers.toggleVisibility({ feature: 'ligand', isVisible: false });
  assert.equal(lump.cell.state.isHidden, true);
  await core.commandHandlers.toggleVisibility({ feature: 'ligand', isVisible: true });
  assert.equal(lump.cell.state.isHidden, false, 'master ligand toggle must restore unsplit ligands too');
});

test('master ligand toggle does not reveal a hidden structure', async () => {
  const { core, addStructure } = viewer();
  const first = addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  await core.commandHandlers.setObjectVisibility({ name: 'first.pdb', isVisible: false });
  await core.commandHandlers.toggleVisibility({ feature: 'ligand', isVisible: true });
  assert.ok(first.components.every(c => c.cell.state.isHidden), 'all child representations must stay hidden');
});

test('ligand representation survives another structure load or preset rebuild', async () => {
  const { core, app, addStructure } = viewer();
  const first = addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  await core.commandHandlers.setObjectRepresentation({ name: 'ATP', representation: 'sphere' });
  addStructure('second.pdb', ['ZN']);
  await core.ensureLigandSplit();
  const ligand = first.components.find(c => c.cell.obj.label === 'ATP');
  assert.equal(ligand.representations[0].type, 'spacefill');
  assert.equal(app.objects.ATP.representation, 'sphere');
});

test('global and per-object representation changes retain the selected structure color', async () => {
  const { core, addStructure } = viewer();
  const structure = addStructure('first.pdb', []);
  await core.commandHandlers.setObjectColor({ name: 'first.pdb', colorHex: '#CC79A7' });
  for (const command of ['setObjectRepresentation', 'setRepresentation']) {
    await core.commandHandlers[command]({ name: 'first.pdb', representation: 'stick' });
    assert.equal(structure.components[0].theme?.colorParams.value, 0xCC79A7, command);
  }
});

test('invalid selection representations fail before mutation', async () => {
  const { core, app, addStructure } = viewer();
  addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  await assert.rejects(core.commandHandlers.setObjectRepresentation({ name: 'ATP', representation: 'bogus' }),
    /Unknown representation/);
  assert.notEqual(app.objects.ATP.representation, 'bogus');
});

test('numeric AST values require whole integers', () => {
  const { core } = viewer();
  for (const [kind, value] of [['residue', '12oops'], ['model', '1.5']]) {
    assert.throws(() => core.queryFromAST({ kind, value }), /integer/);
  }
});

test('preset changes retain named selections on their original parent', async () => {
  const { core, app, plugin, addStructure } = viewer();
  addStructure('first.pdb', []);
  const parent = addStructure('second.pdb', ['ALA']);
  const bundle = parent.cell.obj.data;
  const comp = await plugin.builders.structure.tryCreateComponent(parent.cell,
    { type: { params: bundle }, label: 'region' }, 'molapp-region');
  app.objects.region = { type: 'selection', loci: bundle, bundle, parentRef: parent.cell.transform.ref,
    componentRef: comp.ref, representation: 'stick', colorHex: '#CC79A7', isHidden: true };
  await core.commandHandlers.setRepresentation({ representation: 'ribbon' });
  const restored = parent.components.find(c => c.cell.obj.label === 'region');
  assert.ok(restored, 'the named selection must survive a structure preset rebuild');
  assert.equal(restored.representations[0].type, 'ball-and-stick');
  assert.equal(restored.representations[0].colorParams.value, 0xCC79A7);
  assert.equal(restored.cell.state.isHidden, true);
});

test('surface potential owns its component and replaces only earlier potential overlays', async () => {
  const { core, app, addStructure } = viewer();
  const structure = addStructure('first.pdb', []);
  await core.commandHandlers.setRepresentation({ representation: 'ribbon' });
  const polymer = structure.components[0];
  polymer.representations.push({ type: 'cartoon' });
  await core.commandHandlers.surfacePotential({});
  assert.equal(polymer.representations.length, 1, 'ESP must not append to the main polymer component');
  assert.equal(structure.components.length, 2);
  app.surfacePotentialRefs = []; // A fresh viewer loading a saved scene has no runtime ref cache.
  await core.commandHandlers.surfacePotential({});
  assert.ok(structure.components.includes(polymer), 're-running ESP must retain the main polymer');
  assert.equal(structure.components.length, 2, 'saved overlays must be replaced too');
});

test('stick uses the size key consumed by the bundled representation builder', () => {
  const { core } = viewer();
  const bundle = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/molstar/molstar.js'), 'utf8');
  // Run the actual string-type parameter adapter with registries returning distinct defaults.
  const source = bundle.slice(bundle.indexOf('function Klt('), bundle.indexOf('function ', bundle.indexOf('function Klt(') + 1));
  assert.ok(source.startsWith('function Klt('), 'update extraction when the bundled Mol* is upgraded');
  const adapt = vm.runInNewContext(source + '; Klt', { aSe: (_, __, value) => value });
  const registry = {
    get: name => ({ name, defaultColorTheme: { name: 'default-color' }, defaultSizeTheme: { name: 'physical' } })
  };
  const plugin = { representation: { structure: { registry, themes: { colorThemeRegistry: registry, sizeThemeRegistry: registry } } } };
  const params = adapt(plugin, {}, core.representationParams('stick'));
  assert.equal(params.size.name, 'uniform');
});

test('parent colors and later ligand overrides survive loads and preset rebuilds', async () => {
  const { core, app, addStructure } = viewer();
  const first = addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  await core.commandHandlers.setObjectColor({ name: 'first.pdb', colorHex: '#CC79A7' });
  addStructure('second.pdb', ['ZN']);
  await core.ensureLigandSplit();
  for (const name of ['ATP', 'MG']) {
    const comp = first.components.find(c => c.cell.obj.label === name);
    assert.equal(comp.representations[0].colorParams?.value, 0xCC79A7, name);
    assert.equal(app.objects[name].colorHex, '#CC79A7');
  }
  await core.commandHandlers.setObjectColor({ name: 'ATP', colorHex: '#009E73' });
  await core.commandHandlers.setObjectRepresentation({ name: 'first.pdb', representation: 'ribbon' });
  assert.equal(first.components.find(c => c.cell.obj.label === 'ATP').representations[0].colorParams.value, 0x009E73);
  assert.equal(first.components.find(c => c.cell.obj.label === 'MG').representations[0].colorParams.value, 0xCC79A7);
});

test('surface potential components cannot replace a same-named user selection', async () => {
  const { core, app, plugin, addStructure } = viewer();
  const parent = addStructure('first.pdb', ['ALA']);
  const bundle = parent.cell.obj.data;
  const comp = await plugin.builders.structure.tryCreateComponent(parent.cell,
    { type: { params: bundle }, label: 'surface-potential' }, 'molapp-surface-potential');
  app.objects['surface-potential'] = { type: 'selection', loci: bundle, bundle,
    parentRef: parent.cell.transform.ref, componentRef: comp.ref, representation: 'stick' };
  await core.commandHandlers.surfacePotential({});
  assert.ok(parent.components.includes(comp), 'a user selection must survive ESP');
  assert.equal(parent.components.filter(c => c.cell.obj.label === 'Surface potential').length, 1);
});

test('recoloring preserves the representation size theme through the actual Mol* manager', async () => {
  const { core, plugin, addStructure } = viewer();
  const bundle = fs.readFileSync(path.join(__dirname, '../MolApp/Resources/molstar/molstar.js'), 'utf8');
  const start = bundle.indexOf('updateRepresentationsTheme(r,n){');
  const end = bundle.indexOf('addRepresentation(r,n){', start);
  assert.ok(start >= 0 && end > start, 'update extraction when the bundled Mol* is upgraded');
  const Manager = vm.runInNewContext('class ComponentManager {' + bundle.slice(start, end) + '}; ComponentManager', {
    AR: () => ({ name: 'uniform' }),
    fW: (_, __, ___, name, params) => ({ name: name || 'physical', params })
  });
  const params = { type: { name: 'ball-and-stick' }, sizeTheme: { name: 'uniform', params: { value: 2 } } };
  const parent = addStructure('first.pdb', []);
  parent.components[0].structure = parent;
  parent.components[0].representations.push({ cell: { transform: { params } } });
  const manager = new Manager();
  manager.plugin = plugin;
  manager.dataState = { build: () => ({ to: () => ({ update: fn => fn(params) }), commit: async () => {} }) };
  plugin.managers.structure.component.updateRepresentationsTheme = manager.updateRepresentationsTheme.bind(manager);
  await core.commandHandlers.setObjectColor({ name: 'first.pdb', colorHex: '#CC79A7' });
  assert.equal(params.sizeTheme.name, 'uniform');
  assert.equal(params.sizeTheme.params.value, 2);
});

test('child color metadata survives hierarchy wrapper replacement during a theme commit', async () => {
  const { core, app, plugin, addStructure } = viewer();
  addStructure('first.pdb', ['ATP', 'MG']);
  await core.ensureLigandSplit();
  const component = plugin.managers.structure.component;
  const applyTheme = component.updateRepresentationsTheme;
  component.updateRepresentationsTheme = async (items, theme) => {
    await applyTheme(items, theme);
    const structures = plugin.managers.structure.hierarchy.current.structures;
    structures.splice(0, structures.length, ...structures.map(s => ({
      ...s, components: s.components.map(c => ({ ...c }))
    })));
  };
  await core.commandHandlers.setObjectColor({ name: 'first.pdb', colorHex: '#CC79A7' });
  assert.equal(app.objects.ATP.colorHex, '#CC79A7');
  assert.equal(app.objects.MG.colorHex, '#CC79A7');
});
