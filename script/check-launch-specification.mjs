#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const launch = JSON.parse(fs.readFileSync(path.join(repositoryRoot, "submissions/bankroll-hook/launch.json"), "utf8"));

function fail(message) {
  throw new Error(`launch specification mismatch: ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function assertExactSet(actual, expected, label) {
  const left = [...actual].sort();
  const right = [...expected].sort();
  assert(JSON.stringify(left) === JSON.stringify(right), `${label}: ${JSON.stringify(left)}`);
}

function sha256(relativePath) {
  const bytes = fs.readFileSync(path.join(repositoryRoot, relativePath));
  return `sha256:${crypto.createHash("sha256").update(bytes).digest("hex")}`;
}

function constructorInputs(contractName, sourceUnitName) {
  const artifactPath = path.join(repositoryRoot, "out", path.basename(sourceUnitName), `${contractName}.json`);
  assert(fs.existsSync(artifactPath), `missing ${path.relative(repositoryRoot, artifactPath)}; run forge build first`);
  const abi = JSON.parse(fs.readFileSync(artifactPath, "utf8")).abi;
  return abi.find((entry) => entry.type === "constructor")?.inputs ?? [];
}

function staticWords(input) {
  if (input.type === "tuple") return input.components.reduce((total, component) => total + staticWords(component), 0);
  assert(!input.type.includes("[") && !["bytes", "string"].includes(input.type), `dynamic constructor type ${input.type}`);
  return 1;
}

function addressOffsets(inputs, baseOffset = 0) {
  const offsets = [];
  let word = baseOffset / 32;
  for (const input of inputs) {
    if (input.type === "address") offsets.push(word * 32);
    if (input.type === "tuple") offsets.push(...addressOffsets(input.components, word * 32));
    word += staticWords(input);
  }
  return offsets;
}

function checkConstructor({ contractName, sourceUnitName, constructor, templateKey = "abiEncodedArguments" }) {
  const inputs = constructorInputs(contractName, sourceUnitName);
  const encoded = constructor[templateKey];
  assert(/^0x(?:[0-9a-f]{2})*$/.test(encoded), `${contractName} constructor template is not lowercase hex`);
  const byteLength = (encoded.length - 2) / 2;
  const expectedLength = inputs.reduce((total, input) => total + staticWords(input) * 32, 0);
  assert(byteLength === expectedLength, `${contractName} constructor byte length ${byteLength}, expected ${expectedLength}`);
  assertExactSet(
    constructor.addressLocators.map(({ byteOffset }) => byteOffset),
    addressOffsets(inputs),
    `${contractName} address offsets`,
  );
  for (const locator of constructor.addressLocators) {
    const placeholder = encoded.slice(2 + locator.byteOffset * 2, 2 + (locator.byteOffset + 32) * 2);
    assert(/^0{64}$/.test(placeholder), `${contractName} locator at byte ${locator.byteOffset} is not a zero ABI word`);
  }
}

const foundry = JSON.parse(execFileSync("forge", ["config", "--json"], { cwd: repositoryRoot, encoding: "utf8" }));
assert(launch.compiler.family === "solc", "compiler family");
assert(launch.compiler.version === foundry.solc, "solc version");
assert(launch.compiler.settings.evmVersion === foundry.evm_version, "EVM version");
assert(launch.compiler.settings.optimizer.enabled === foundry.optimizer, "optimizer enabled state");
assert(launch.compiler.settings.optimizer.runs === foundry.optimizer_runs, "optimizer runs");
assert(launch.compiler.settings.viaIR === foundry.via_ir, "viaIR state");
assert(launch.compiler.settings.metadata.bytecodeHash === foundry.bytecode_hash, "bytecode hash mode");
assert(launch.compiler.settings.metadata.appendCBOR === foundry.cbor_metadata, "CBOR metadata state");

const expectedTargets = [
  "target:bankroll-launch",
  "target:hook-factory",
  "target:router-factory",
  "target:vrf-adapter",
];
const expectedChildren = [
  "child:bankroll-hook",
  "child:bankroll-router",
  "child:launched-token",
  "child:permanent-position-locker",
];
const expectedDependencies = [
  "dependency:pool-manager",
  "dependency:position-manager",
  "dependency:token-factory",
  "dependency:vrf-wrapper",
  "dependency:weth",
];
const expectedComponents = [
  "component:bankroll-hook",
  "component:bankroll-launch",
  "component:bankroll-router",
  "component:hook-factory",
  "component:launched-token",
  "component:permanent-position-locker",
  "component:pool-manager",
  "component:position-manager",
  "component:router-factory",
  "component:token-factory",
  "component:vrf-adapter",
  "component:vrf-wrapper",
  "component:weth",
];
assertExactSet(launch.targets.map(({ targetId }) => targetId), expectedTargets, "target set");
assertExactSet(launch.internalChildDeployments.map(({ childId }) => childId), expectedChildren, "internal child set");
assertExactSet(launch.externalOnchainDependencies.map(({ dependencyId }) => dependencyId), expectedDependencies, "external dependency set");
assertExactSet(launch.components.map(({ componentId }) => componentId), expectedComponents, "component set");
assert(launch.rootTargetId === "target:bankroll-launch" && launch.rootComponentId === "component:bankroll-launch", "root launcher identity");

const targetSet = new Set(expectedTargets);
const childSet = new Set(expectedChildren);
const dependencySet = new Set(expectedDependencies);
for (const target of launch.targets) {
  assert(target.sourceSha256 === sha256(target.sourceUnitName), `${target.targetId} source hash`);
  checkConstructor(target);
  for (const locator of target.constructor.addressLocators) {
    if (locator.kind === "target") assert(targetSet.has(locator.targetId), `${target.targetId} unknown target locator`);
    if (locator.kind === "external-onchain-dependency") {
      assert(dependencySet.has(locator.dependencyId), `${target.targetId} unknown dependency locator`);
    }
  }
}

const childPlans = launch.extensions.internalChildPlans;
assertExactSet(childPlans.map(({ childId }) => childId), expectedChildren, "internal child plan set");
for (const child of childPlans) {
  if (child.sourceUnitName !== null) assert(child.sourceSha256 === sha256(child.sourceUnitName), `${child.childId} source hash`);
  if (child.constructor !== null) {
    checkConstructor({
      contractName: child.contractName,
      sourceUnitName: child.sourceUnitName,
      constructor: child.constructor,
      templateKey: "abiEncodedArgumentsTemplate",
    });
  }
  if (child.deployerTargetId !== undefined) assert(targetSet.has(child.deployerTargetId), `${child.childId} deployer target`);
  if (child.deployerDependencyId !== undefined) {
    assert(dependencySet.has(child.deployerDependencyId), `${child.childId} deployer dependency`);
  }
  for (const locator of child.constructor?.addressLocators ?? []) {
    if (locator.kind === "target") assert(targetSet.has(locator.targetId), `${child.childId} unknown target locator`);
    if (locator.kind === "internal-child") assert(childSet.has(locator.childId), `${child.childId} unknown child locator`);
    if (locator.kind === "external-onchain-dependency") {
      assert(dependencySet.has(locator.dependencyId), `${child.childId} unknown dependency locator`);
    }
  }
}

const hookPlan = childPlans.find(({ childId }) => childId === "child:bankroll-hook");
assertExactSet(hookPlan.declaredHookPermissions, [
  "afterInitialize",
  "afterSwap",
  "afterSwapReturnDelta",
  "beforeInitialize",
  "beforeSwap",
  "beforeSwapReturnDelta",
], "hook permission set");
assertExactSet(
  hookPlan.constructor.dynamicValueBindings.map(({ byteOffset }) => byteOffset),
  [160, 192, 224, 256, 288, 320, 352, 384],
  "hook configuration offsets",
);

const vrfTarget = launch.targets.find(({ targetId }) => targetId === "target:vrf-adapter");
const vrfWords = vrfTarget.constructor.abiEncodedArguments.slice(2).match(/.{64}/g).map((word) => BigInt(`0x${word}`));
assert(vrfWords[1] === BigInt(launch.extensions.vrfAdapterConfiguration.callbackGasLimit), "VRF callback gas limit");
assert(vrfWords[2] === BigInt(launch.extensions.vrfAdapterConfiguration.requestConfirmations), "VRF confirmations");

const dependencyEvidence = JSON.parse(
  fs.readFileSync(path.join(repositoryRoot, "submissions/bankroll-hook/dependency-evidence.json"), "utf8"),
);
const evidenceAddresses = new Map(dependencyEvidence.dependencies.map(({ id, address }) => [id, address.toLowerCase()]));
assertExactSet(
  launch.extensions.externalDependencyBindings.map(({ dependencyId }) => dependencyId),
  expectedDependencies,
  "external binding set",
);
for (const binding of launch.extensions.externalDependencyBindings) {
  assert(binding.address === evidenceAddresses.get(binding.evidenceId), `${binding.dependencyId} evidence address`);
}

const releaseOrder = launch.extensions.releaseDeploymentOrder;
assertExactSet(releaseOrder, expectedTargets, "release deployment order");
const releaseIndex = new Map(releaseOrder.map((targetId, index) => [targetId, index]));
for (const target of launch.targets) {
  for (const locator of target.constructor.addressLocators.filter(({ kind }) => kind === "target")) {
    assert(releaseIndex.get(locator.targetId) < releaseIndex.get(target.targetId), `${target.targetId} release dependency order`);
  }
}

const expectedEdges = [
  "edge:hook-deployed-by-hook-factory",
  "edge:hook-factory-uses-router-factory",
  "edge:hook-uses-launch-registrar",
  "edge:hook-uses-pool-manager",
  "edge:hook-uses-token",
  "edge:hook-uses-vrf-adapter",
  "edge:hook-uses-weth",
  "edge:launch-deploys-locker",
  "edge:launch-initializes-pool",
  "edge:launch-mints-position",
  "edge:launch-uses-hook-factory",
  "edge:launch-uses-pool-manager",
  "edge:launch-uses-position-manager",
  "edge:launch-uses-token-factory",
  "edge:launch-uses-vrf-adapter",
  "edge:launch-uses-weth",
  "edge:locker-uses-position-manager",
  "edge:router-deployed-by-router-factory",
  "edge:router-uses-hook",
  "edge:router-uses-pool-manager",
  "edge:router-uses-token",
  "edge:router-uses-weth",
  "edge:token-deployed-by-token-factory",
  "edge:vrf-adapter-uses-wrapper",
];
assertExactSet(launch.edges.map(({ edgeId }) => edgeId), expectedEdges, "deployment edge set");
assertExactSet(
  launch.extensions.atomicLaunchPlan.steps.map(({ step }) => step),
  [1, 2, 3, 4, 5, 6, 7, 8, 9],
  "atomic launch steps",
);

console.log("launch specification matches the bound compiler profile, ABI constructors, source hashes and deployment graph");
