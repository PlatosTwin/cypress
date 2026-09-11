import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  eyebrow,
  facts,
  subtitle,
  terms,
  title,
  treePageModel,
  W1Copy,
  type TreePageInput,
} from '../src/lib/treePage.ts';
import { NYC_DISCLAIMER_REQUIRED, NYC_ID_SPACE } from '../src/lib/obligations.ts';
import { repoFile, swiftStringLet } from './support/sources.ts';

/**
 * W1's page model.
 *
 * The specimens below are **real rows from the published San Francisco pack** — `sf.sqlite` at
 * `s17-r2026-08-22.02-ac7b1ccc`, 82,796,544 bytes, sha256 `15d9521e…`, both verified against
 * `manifest-v2.json`, with `select count(*) from trees` returning 145,964 against the manifest's
 * 145,964 as the control. Copied here rather than queried, because CI has no pack: what they buy
 * is that every branch below is a shape the data actually has, not one somebody imagined it
 * having. `pack-real-seed.test.ts` is the tier that reads a real file; this is the tier that says
 * what the page does with what it finds.
 */

/** `2576 LOMBARD ST` — a Monterey Cypress, the closest real analogue to §W1's own drawn tree. */
const lombard: TreePageInput = {
  idSpace: 'sf',
  uuid: 'eac6cce9-68bf-53c6-aa3c-44d26deb868d',
  status: 'alive',
  address: '2576 LOMBARD ST',
  neighborhoodName: 'Marina',
  cityName: 'San Francisco',
  speciesCommonName: 'Monterey Cypress',
  speciesScientificName: 'Cupressus macrocarpa',
  plantedYear: 1993,
  dbhCityCmMin: 65,
  dbhCityCmMax: 70,
  siteType: 'Sidewalk: Curb side : Cutout',
  externalRef: '13284',
  inventoryName: 'SF Public Works street tree inventory',
  inventoryURL: 'https://services.arcgis.com/…/BUF_Street_Trees/FeatureServer/3',
  inventorySnapshotOn: '2026-08-22',
  inventoryLicense: null,
};

/** `124 COLUMBUS AVE` — a vacant planting site that carries a planted year AND a city bucket. */
const columbus: TreePageInput = {
  ...lombard,
  uuid: '99d67bb8-82aa-5f8c-848d-b9171611fec2',
  status: 'vacant_site',
  address: '124 COLUMBUS AVE',
  neighborhoodName: 'Chinatown',
  speciesCommonName: null,
  speciesScientificName: null,
  plantedYear: 2016,
  dbhCityCmMin: 5,
  dbhCityCmMax: 10,
  externalRef: '4592',
};

/** `1504 DOLORES ST` — a species with a scientific name and **no common name**. 178 of 1,198. */
const dolores: TreePageInput = {
  ...lombard,
  uuid: 'b50cd38d-2d00-5d7a-b390-e3a14f63c1ed',
  address: '1504 DOLORES ST',
  neighborhoodName: 'Noe Valley',
  speciesCommonName: null,
  speciesScientificName: 'Ficus Spp.',
  plantedYear: null,
  dbhCityCmMin: 45,
  dbhCityCmMax: 50,
  externalRef: '707',
};

/** A San Jose row: the id space whose receipt DOES record a license. */
const sanJose: TreePageInput = {
  ...lombard,
  idSpace: 'us-ca-sj',
  uuid: '11111111-1111-4111-8111-111111111111',
  cityName: 'San Jose',
  inventoryName: 'City of San Jose Street Tree inventory',
  inventorySnapshotOn: '2026-08-22',
  inventoryLicense: 'CC-BY',
};

function row(input: TreePageInput, id: string) {
  return facts(input).find((fact) => fact.id === id);
}

describe('the H1', () => {
  it('is the species common name, which is the app’s precedence with its top rung gone', () => {
    assert.equal(title(lombard), 'Monterey Cypress');
  });

  it('falls back to the address when the species has no common name', () => {
    assert.equal(title(dolores), '1504 DOLORES ST');
  });

  it('is the address on a vacant site, never the species — SiteCopy.title', () => {
    assert.equal(title(columbus), '124 COLUMBUS AVE');
    // And still the address even where the record DOES name a species, because "a site has no
    // species to be named after" and a basin labelled with one asserts a tree.
    assert.equal(
      title({ ...columbus, speciesCommonName: 'Monterey Cypress' }),
      '124 COLUMBUS AVE',
    );
  });

  it('uses the app’s own two fallbacks when there is neither', () => {
    assert.equal(
      title({ ...dolores, address: null, speciesScientificName: null }),
      W1Copy.unnamedRecord,
    );
    assert.equal(title({ ...columbus, address: null }), W1Copy.unnamedSite);
  });

  it('and those two fallbacks are the app’s, not this file’s', () => {
    assert.equal(
      W1Copy.unnamedRecord,
      swiftStringLet(repoFile('Cypress/Features/TreeProfile/TreeProfilePresentation.swift'), 'fallbackTitle'),
    );
    assert.equal(
      W1Copy.unnamedSite,
      swiftStringLet(repoFile('Cypress/Features/Site/SitePresentation.swift'), 'fallbackTitle'),
    );
  });

  it('does not take a non-value as a name', () => {
    assert.equal(title({ ...dolores, address: 'N/A', speciesScientificName: null }), W1Copy.unnamedRecord);
  });
});

describe('the serif line under it', () => {
  it('names what the H1 did not, then where the record came from', () => {
    assert.deepEqual(subtitle(lombard), [
      { text: 'Cupressus macrocarpa', italic: true },
      { text: 'SF Public Works street tree inventory', italic: false },
    ]);
  });

  it('sets the scientific name italic and nothing else', () => {
    const italics = subtitle(lombard).filter((part) => part.italic).map((part) => part.text);
    assert.deepEqual(italics, ['Cupressus macrocarpa']);
  });

  it('does not repeat the H1 when the address is the H1 and the scientific name is the species', () => {
    assert.deepEqual(subtitle(dolores).map((part) => part.text), [
      'Ficus Spp.',
      'SF Public Works street tree inventory',
    ]);
  });

  it('says what a vacant record IS, in SiteCopy’s own words', () => {
    assert.deepEqual(subtitle(columbus).map((part) => part.text), [
      'Vacant planting site',
      'SF Public Works street tree inventory',
    ]);
    assert.equal(
      'Vacant planting site',
      swiftStringLet(repoFile('Cypress/Features/Site/SitePresentation.swift'), 'kind'),
    );
  });

  it('still names the inventory when the H1 is the fallback noun — provenance is not optional', () => {
    // BUILD-PLAN §5: no UI-only provenance. The H1 has said nothing identifying, which is exactly
    // when the reader most needs to know whose record this is.
    const parts = subtitle({ ...columbus, address: null });
    assert.deepEqual(parts.map((part) => part.text), ['SF Public Works street tree inventory']);
  });
});

describe('the eyebrow', () => {
  it('is §W1’s own `‹address› · ‹city›`', () => {
    assert.equal(eyebrow(lombard), '2576 LOMBARD ST · San Francisco');
  });

  it('becomes the neighborhood when the address has been promoted to the H1', () => {
    assert.equal(eyebrow(columbus), 'Chinatown · San Francisco');
    assert.equal(eyebrow(dolores), 'Noe Valley · San Francisco');
  });

  it('never invents a city a pre-generation-16 pack cannot name', () => {
    assert.equal(eyebrow({ ...lombard, cityName: null }), '2576 LOMBARD ST');
    assert.equal(eyebrow({ ...lombard, cityName: null, address: null, neighborhoodName: null }), null);
  });
});

describe('the fact column', () => {
  it('draws §W1’s rows in §W1’s order, with the contributed ones absent', () => {
    assert.deepEqual(facts(lombard).map((fact) => fact.id), [
      'status', 'dbh', 'planted', 'site', 'cityRecord',
    ]);
  });

  it('never draws a Height row, because a measured height is contributed', () => {
    // Asserted as a fact about the model rather than as absence of a string: there is no input
    // this function takes that could produce one, and this is the row §W1 draws that v1 cannot.
    for (const specimen of [lombard, columbus, dolores, sanJose]) {
      assert.equal(row(specimen, 'height'), undefined);
      assert.equal(row(specimen, 'vitality'), undefined);
    }
  });

  it('gives the status row C30’s emphasis and nothing else', () => {
    const emphasized = facts(lombard).filter((fact) => fact.emphasized).map((fact) => fact.id);
    assert.deepEqual(emphasized, ['status']);
    assert.equal(row(lombard, 'status')?.value, 'Alive');
  });

  it('badges the DBH bucket so it cannot be read as a reading', () => {
    assert.equal(row(lombard, 'dbh')?.value, '65–70 cm');
    assert.equal(row(lombard, 'dbh')?.badge, 'city record');
    // And it is the only badged row: a badge on `Planted` or `City record` would be claiming a
    // method for a fact that has none.
    assert.deepEqual(facts(lombard).filter((fact) => fact.badge !== null).map((fact) => fact.id), ['dbh']);
  });

  it('labels the planting year `Planted`, which is what the column holds', () => {
    assert.equal(row(lombard, 'planted')?.label, 'Planted');
    assert.equal(row(lombard, 'planted')?.value, '1993');
    assert.equal(row(dolores, 'planted'), undefined);
  });

  it('drops a site type the city populated with a non-value', () => {
    assert.equal(row({ ...lombard, siteType: 'N/A' }, 'site'), undefined);
    assert.equal(row({ ...lombard, siteType: ':' }, 'site'), undefined);
  });

  it('draws a vacant site the way SitePresentation does — no Planted, no measurement', () => {
    // The specimen carries BOTH: 124 COLUMBUS AVE is `vacant_site` with planted_year 2016 and a
    // 5–10 cm bucket in the shipped pack. If the rule were absent they would render.
    assert.notEqual(columbus.plantedYear, null);
    assert.notEqual(columbus.dbhCityCmMin, null);
    assert.deepEqual(facts(columbus).map((fact) => fact.id), [
      'status', 'site', 'cityRecord', 'neighborhood',
    ]);
    assert.equal(row(columbus, 'status')?.value, 'Vacant site');
    assert.equal(row(columbus, 'neighborhood')?.value, 'Chinatown');
  });

  it('draws no Neighborhood row on a tree, where no mock has one', () => {
    assert.equal(row(lombard, 'neighborhood'), undefined);
  });
});

describe('the Data row, under the web round’s fourth owner ruling', () => {
  it('states the license the receipt records, verbatim', () => {
    assert.deepEqual(terms(sanJose), { label: 'Data', value: 'CC-BY', note: null });
  });

  it('reproduces a long obligation rather than summarizing it', () => {
    const nyc = 'NYC Open Data / Data Mine terms; notification + verbatim disclaimer required';
    assert.equal(terms({ ...sanJose, inventoryLicense: nyc }).value, nyc);
  });

  it('says nothing, and says why, where the receipt carries nothing', () => {
    // San Francisco: the largest and oldest source, and the receipt records no license for either
    // of its two inventories. The ruling: state what the receipt records, say less where it does
    // not — and the page says why, because the empty row otherwise reads as a defect.
    assert.deepEqual(terms(lombard), {
      label: 'Data',
      value: W1Copy.noLicenseRecorded,
      note: W1Copy.noLicenseNote,
    });
  });

  it('never claims ODbL over a city row', () => {
    // §W1 transcribes `ODbL · CSV / GeoJSON`. ODbL is the license CONTRIBUTORS grant at signup;
    // v1 publishes no contributions, so claiming it over the city record would assert a license
    // this project does not hold the rights to give.
    for (const specimen of [lombard, columbus, dolores, sanJose]) {
      assert.ok(!terms(specimen).value.includes('ODbL'));
    }
  });
});

describe('the whole model', () => {
  it('is the path every share card the app has produced already points at', () => {
    const model = treePageModel(lombard);
    assert.equal(model.path, '/sf/tree/eac6cce9-68bf-53c6-aa3c-44d26deb868d');
  });

  it('carries the provenance sentence, dated from the receipt', () => {
    assert.equal(
      treePageModel(lombard).provenance,
      'From the SF Public Works street tree inventory, August 22, 2026.',
    );
  });

  it('has no provenance sentence when the pack cannot date the snapshot', () => {
    assert.equal(treePageModel({ ...lombard, inventorySnapshotOn: null }).provenance, null);
    assert.equal(treePageModel({ ...lombard, inventoryName: null }).provenance, null);
  });

  it('carries the source\u2019s obligation onto the model, so the page cannot omit it', () => {
    // R36 consequence (b) and R78 ruling 3: a page serving New York's data renders the City's
    // disclaimer, and the manifest's machine-readable `attribution` array does not discharge it.
    // The obligation is a value on the model rather than a condition in the template so that
    // "does this page carry it" is answerable here. `obligations.test.ts` checks the text itself
    // against the app's; this checks that a New York tree gets one and a San Francisco tree
    // does not.
    assert.equal(treePageModel(lombard).obligation, null);
    const newYork = treePageModel({ ...lombard, idSpace: NYC_ID_SPACE });
    assert.notEqual(newYork.obligation, null);
    assert.equal(newYork.obligation?.paragraphs[0], NYC_DISCLAIMER_REQUIRED);
  });

  it('describes the tree in facts, and in facts the page also shows', () => {
    const model = treePageModel(lombard);
    assert.equal(
      model.description,
      'Monterey Cypress · Cupressus macrocarpa — 2576 LOMBARD ST · San Francisco. '
        + '#13284 in the SF Public Works street tree inventory.',
    );
    assert.equal(model.documentTitle, 'Monterey Cypress · San Francisco');
  });

  it('degrades to the H1 alone when the pack names no city', () => {
    assert.equal(treePageModel({ ...lombard, cityName: null }).documentTitle, 'Monterey Cypress');
  });
});
