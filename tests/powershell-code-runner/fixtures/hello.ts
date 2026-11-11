// A module-scoped declaration keeps type-checking runners happy without @types/node.
declare const process: { argv: string[]; exit(code: number): never };
const values: string[] = process.argv.slice(2);
console.log("OK:" + values.join("|"));
process.exit(3);
export {};
