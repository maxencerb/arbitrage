import path from "node:path";

const uniV3Core = "node_modules/@uniswap/v3-core";
const uniV3Periphery = "node_modules/@uniswap/v3-periphery";

const files = [
  path.join(
    uniV3Core,
    "artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"
  ),
  path.join(
    uniV3Periphery,
    "artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json"
  ),
  path.join(
    uniV3Periphery,
    "artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"
  ),
];

const outputs = [
  __dirname + "/uni-out/UniswapV3Factory.txt",
  __dirname + "/uni-out/NonfungibleTokenPositionDescriptor.txt",
  __dirname + "/uni-out/NonfungiblePositionManager.txt",
];

async function main() {
  await Promise.all(
    files.map(async (f, i) => {
      const file = Bun.file(f);
      const outputFile = Bun.file(outputs[i]);
      const data = await file.json();
      const bytecode = data.bytecode.replace(
        /__\$[a-fA-F0-9]+\$__/gm,
        "0".repeat(40)
      );
      if (!(await outputFile.exists())) {
      }
      await Bun.write(outputFile, bytecode);
    })
  );
}

main()
  .then(() => console.log("done"))
  .catch(console.error);
