#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const packageDirectory = path.join(repositoryRoot, "submissions/bankroll-hook");
const legacyPath = path.join(packageDirectory, "submission.json");
const outputPath = path.join(packageDirectory, "submission.v1.5.json");
const submission = JSON.parse(fs.readFileSync(legacyPath, "utf8"));

submission.$schema = "urn:programmable:v4-hook-submission:1.5.0";
submission.standardVersion = "1.5.0";
submission.builderTemplate = {
  schemaVersion: "1.0.0",
  source: "manual",
  templateSelection: null,
};
submission.publicMetadata.localDiscoveryTags = ["bankroll", "fixed-odds", "gaming"];

submission.programmableFee.policyVersion = "1.1.0";
submission.programmableFee.collection.status = "implemented";
submission.programmableFee.accounting.roundingPolicy =
  "cumulative-independent-platform-project-remainders";
submission.programmableFee.accounting.remainderScope = "canonical-pool-lifetime";
submission.programmableFee.accounting.claimResetsRemainders = false;
submission.programmableFee.accounting.minimumGrossQuoteUnits = 1000;
submission.programmableFee.accounting.fragmentationResistant = true;
for (const quadrant of Object.values(submission.hook.feeMechanism.swapQuadrants)) {
  quadrant.rounding = "down";
}
submission.integration.sdkSafetyProfile = {
  packageRootImportsOnly: null,
  hookedQuoteSource: null,
  localHookedPoolMathDisabled: null,
  hookDataParity: null,
  multiHopHookDataMode: null,
  perHopPriceBounds: null,
  slippageSemantics: null,
  deprecatedLiquidityActionsDisabled: null,
};

const exception =
  "Builder 1.5 standard profile requires a positive gross quote below 1,000 units to revert. The reviewed custom-hook change request instead requires 1,000 successful 999 wei swaps to accrue 999 wei. The source implements the requested cumulative custom profile; maintainers must resolve this one architecture exception before standard-profile conformance can be claimed.";
if (!submission.disclosures.includes(exception)) submission.disclosures.push(exception);
submission.unresolved = [exception];

fs.writeFileSync(outputPath, `${JSON.stringify(submission, null, 2)}\n`);
