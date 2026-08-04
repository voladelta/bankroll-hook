#!/usr/bin/env node

import fs from "node:fs";

const contracts = [
  ["BankrollHook", "out/BankrollHook.sol/BankrollHook.json"],
  ["BankrollHookFactory", "out/BankrollHookFactory.sol/BankrollHookFactory.json"],
  ["BankrollRouter", "out/BankrollRouter.sol/BankrollRouter.json"],
  ["BankrollRouterFactory", "out/BankrollHookFactory.sol/BankrollRouterFactory.json"],
  ["BankrollLaunchV1", "out/BankrollLaunchV1.sol/BankrollLaunchV1.json"],
  ["PermanentPositionLocker", "out/PermanentPositionLocker.sol/PermanentPositionLocker.json"],
  ["ChainlinkVrfV25Adapter", "out/ChainlinkVrfV25Adapter.sol/ChainlinkVrfV25Adapter.json"],
];
const runtimeLimit = 24_576;
const initcodeLimit = 49_152;
let failed = false;

const sizeOf = (object) => object.replace(/^0x/, "").length / 2;

for (const [name, path] of contracts) {
  const artifact = JSON.parse(fs.readFileSync(new URL(`../${path}`, import.meta.url), "utf8"));
  const runtime = sizeOf(artifact.deployedBytecode.object);
  const initcode = sizeOf(artifact.bytecode.object);
  console.log(`${name}: runtime ${runtime}/${runtimeLimit} bytes; initcode ${initcode}/${initcodeLimit} bytes`);
  failed ||= runtime > runtimeLimit || initcode > initcodeLimit;
}

if (failed) process.exitCode = 1;
