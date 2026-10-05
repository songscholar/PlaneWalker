#!/usr/bin/env node
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ledgerPath = 'data/save/compatibility/actual_content_ledger.json';
const packPath = 'data/content_packs/base/pack.json';
const localizationPath = 'localization/translations.csv';
const cosmeticFiles = [
  'assets/cosmetics/LICENSE.txt', 'assets/cosmetics/contact_sheet.png', 'assets/cosmetics/manifest.json',
  ...['primordial_knight', 'time_guardian', 'time_lord', 'void_walker', 'wanderer'].flatMap(character =>
    ['default', 'return', 'victory'].map(route => `assets/cosmetics/${character}_${route}.png`)),
  'content/cosmetics.json', 'localization/cosmetics.csv',
];
const terminalEncounterFiles = ['content/launch_encounter_extensions.json'];
const allowedAdditions = [cosmeticFiles, [...cosmeticFiles, ...terminalEncounterFiles], terminalEncounterFiles];
const ambushFiles = [
  'assets/rooms/launch/room_event_crossroads.tscn', 'assets/rooms/launch/room_event_mirror_hall.tscn',
  'assets/rooms/launch/room_event_shrine.tscn', 'content/enemies.json', 'content/room_templates.json',
];
const allowedChanges = [[], [localizationPath], ['content/enemies.json'], ['content/enemies.json', localizationPath],
  ambushFiles, [...ambushFiles, localizationPath]];
const digest = value => createHash('sha256').update(value).digest('hex');
const read = value => readFileSync(path.join(projectRoot, value));
const gitRead = (commit, value) => execFileSync('git', ['show', `${commit}:${value}`], { cwd: projectRoot, maxBuffer: 8 * 1024 * 1024 });
const ledger = JSON.parse(read(ledgerPath));
const runtime = read('scripts/save/actual_content_compatibility_ledger.gd').toString();
assert(runtime.includes(`const LEDGER_SHA256 := "${digest(read(ledgerPath))}"`), 'runtime must pin the exact reviewed ledger bytes');
const bindings = new Map();
const currentSchema = JSON.parse(read('data/schemas/save_profile_v4.schema.json'));
assert.deepEqual(currentSchema.properties.payload.properties.cosmetic_collection,
  { $ref: 'planewalker://schemas/cosmetic-collection/1.0.0' }, 'only the reviewed optional cosmetic payload extends Profile v4');
delete currentSchema.properties.payload.properties.cosmetic_collection;
const catalogConstruction = source => {
  const marker = 'static func from_catalogs(';
  const offset = source.indexOf(marker);
  assert(offset >= 0, 'catalog construction entry point exists');
  return source.slice(offset);
};
const metaStateDefinition = source => {
  // e52e705 reserved mode command receipts without changing persisted Meta rules.
  const historical = 'const RESERVED_COMMAND_PREFIXES := ["forge-enchant-unlock:", "legacy-stat:", "training-claim:", "narrative-source:", "onboarding-progress:", "onboarding-watermark:"]';
  const current = historical.slice(0, -1) + ', "mode-reward:", "mode-equip:"]';
  assert(source.includes(historical) || source.includes(current), 'only the exact reviewed mode receipt reservations extend the command boundary');
  return source.replace(current, historical);
};
for (const binding of ledger.bindings) {
  const descriptorPath = binding.descriptor_path.replace(/^res:\/\//, '');
  const descriptor = JSON.parse(read(descriptorPath));
  // Godot's integration test checks its own numeric JSON encoding and canonical fingerprints.
  for (const commit of binding.source_commits) {
    const historical = JSON.parse(gitRead(commit, packPath));
    assert.deepEqual(descriptor, historical, `proof descriptor matches complete committed source: ${commit}`);
    for (const content of [...historical.content_manifest, ...historical.localization_sources, ...historical.asset_manifest]) {
      assert.equal(digest(gitRead(commit, `data/content_packs/base/${content}`)), historical.integrity_hashes[content], `authored source content is authentic: ${commit}:${content}`);
    }
    for (const protectedPath of ['data/content/meta_legacy_references.json', 'scripts/progression/meta_profile_state.gd', 'scripts/progression/meta_progression_catalog.gd', 'data/schemas/meta_profile_state_v1.schema.json']) {
      const historical = gitRead(commit, protectedPath);
      const current = read(protectedPath);
      assert.equal(digest(protectedPath.endsWith('meta_profile_state.gd') ? metaStateDefinition(historical.toString()) : historical),
        digest(protectedPath.endsWith('meta_profile_state.gd') ? metaStateDefinition(current.toString()) : current),
        `Meta definitions and persisted state rules remain identical: ${commit}:${protectedPath}`);
    }
    assert.equal(catalogConstruction(gitRead(commit, 'scripts/progression/meta_catalog_factory.gd').toString()),
      catalogConstruction(read('scripts/progression/meta_catalog_factory.gd').toString()), `catalog construction semantics unchanged: ${commit}`);
    const historicalSchema = JSON.parse(gitRead(commit, 'data/schemas/save_profile_v4.schema.json'));
    delete historicalSchema.properties.payload.properties.cosmetic_collection;
    assert.deepEqual(historicalSchema, currentSchema, `all pre-existing Profile v4 schema rules remain unchanged: ${commit}`);
  }
  bindings.set(binding.id, descriptor);
}
for (const edge of ledger.transitions) {
  assert(allowedChanges.some(allowed => JSON.stringify(allowed) === JSON.stringify(edge.allowed_changed_files)),
    'only previously reviewed exact localization and hostile content changes are admitted');
  assert(allowedAdditions.some(allowed => JSON.stringify(allowed) === JSON.stringify(edge.allowed_added_files)),
    'only exact reviewed cosmetic resources and terminal encounter extension are additive');
  const source = structuredClone(bindings.get(edge.source_id));
  const target = bindings.get(edge.target_id);
  for (const added of edge.allowed_added_files) {
    assert(!Object.hasOwn(source.integrity_hashes, added) && Object.hasOwn(target.integrity_hashes, added), 'reviewed added resource is new and authenticated');
    const manifest = ['content/cosmetics.json', ...terminalEncounterFiles].includes(added) ? 'content_manifest' :
      added === 'localization/cosmetics.csv' ? 'localization_sources' : 'asset_manifest';
    source[manifest].push(added);
    source[manifest].sort();
    source.integrity_hashes[added] = target.integrity_hashes[added];
  }
  for (const changed of edge.allowed_changed_files) {
    assert(Object.hasOwn(source.integrity_hashes, changed) && Object.hasOwn(target.integrity_hashes, changed)
      && source.integrity_hashes[changed] !== target.integrity_hashes[changed], 'reviewed changed file exists and differs');
    source.integrity_hashes[changed] = target.integrity_hashes[changed];
  }
  assert.deepEqual(source, target, `entire descriptor differs only by exact reviewed changes and additions: ${edge.source_id}`);
}
console.log(`PASS: ${ledger.bindings.length} committed descriptor proofs, ${ledger.transitions.length} exact reviewed transitions, identical persisted Meta state and existing Profile v4 schema`);
