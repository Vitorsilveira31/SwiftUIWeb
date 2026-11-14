import { cp } from "node:fs/promises";

const bundlePath = `${import.meta.dir}/../.build/browser/BlocklyInteropApp`;
const blocklyMediaPath = `${import.meta.dir}/../node_modules/blockly/media`;
await cp(blocklyMediaPath, `${bundlePath}/media`, { recursive: true, force: true });
