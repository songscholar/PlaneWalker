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
const digest = value => createHash('sha256').update(value).digest('hex');
const read = value => readFileSync(path.join(projectRoot, value));
const gitRead = (commit, value) => execFileSync('git', ['show', `${commit}:${value}`], { cwd: projectRoot, maxBuffer: 8 * 1024 * 1024 });
const ledger = JSON.parse(read(ledgerPath));
const runtime = read('scripts/save/actual_content_compatibility_ledger.gd').toString();
assert(runtime.includes(`const LEDGER_SHA256 := "${digest(read(ledgerPath))}"`), 'runtime must pin the exact reviewed ledger bytes');
const bindings = new Map();
for (const binding of ledger.bindings) {
  const descriptorPath = binding.descriptor_path.replace(/^res:\/\//, '');
  const descriptor = JSON.parse(read(descriptorPath));
  // Godot's integration test checks its own numeric JSON encoding and canonical fingerprints.
  for (const commit of binding.source_commits) {
    const historical = JSON.parse(gitRead(commit, packPath));
    assert.deepEqual(descriptor, historical, `proof descriptor matches complete committed source: ${commit}`);
    for (const content of historical.content_manifest) {
      assert.equal(digest(gitRead(commit, `data/content_packs/base/${content}`)), historical.integrity_hashes[content], `authored source content is authentic: ${commit}:${content}`);
    }
    for (const protectedPath of ['data/content/meta_legacy_references.json', 'scripts/progression/meta_profile_state.gd', 'scripts/progression/meta_progression_catalog.gd', 'scripts/progression/meta_catalog_factory.gd', 'scripts/save/save_envelope.gd']) {
      assert.equal(digest(gitRead(commit, protectedPath)), digest(read(protectedPath)), `Meta semantics and Profile schema unchanged: ${commit}:${protectedPath}`);
    }
  }
  bindings.set(binding.id, descriptor);
}
for (const edge of ledger.transitions) {
  assert.deepEqual(edge.allowed_changed_files, [localizationPath], 'only explicitly reviewed localization changes are admitted');
  const source = structuredClone(bindings.get(edge.source_id));
  const target = bindings.get(edge.target_id);
  source.integrity_hashes[localizationPath] = target.integrity_hashes[localizationPath];
  assert.deepEqual(source, target, `entire descriptor differs only by admitted file: ${edge.source_id}`);
}
console.log(`PASS: ${ledger.bindings.length} committed descriptor proofs, ${ledger.transitions.length} exact localization-only transitions, identical Meta semantics and Profile v4 schema`);
