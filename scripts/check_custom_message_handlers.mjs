import fs from "node:fs";

const files = ["ui.R", "www/pincards.js"];
const handlerPattern = /Shiny\.addCustomMessageHandler\(\s*["'][^"']+["']\s*,\s*function\s*\(([^)]*)\)/g;
let seen = 0;
const invalid = [];

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  for (const match of source.matchAll(handlerPattern)) {
    seen += 1;
    const params = match[1]
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    if (params.length !== 1) invalid.push(`${file}: ${match[0]}`);
  }
}

if (seen !== 4) {
  throw new Error(`expected 4 Shiny custom message handlers, found ${seen}`);
}
if (invalid.length) {
  throw new Error(
    `Shiny custom message handlers must accept exactly one payload argument:\n${invalid.join("\n")}`,
  );
}

console.log(`OK: ${seen} Shiny custom message handlers accept exactly one payload argument.`);

const server = fs.readFileSync("server.R", "utf8");
for (const source of ["commBar", "ordPlot", "envrank"]) {
  const safeLifecycle = new RegExp(
    String.raw`observeEvent\(\s*session\$rootScope\(\)\$input\[\["plotly_click-${source}"\]\],\s*\{[\s\S]{0,320}?plotly::event_data\("plotly_click",\s*source\s*=\s*"${source}",\s*priority\s*=\s*"event"\)`,
  );
  if (!safeLifecycle.test(server)) {
    throw new Error(
      `${source} must wait for its raw Plotly click before reading event_data(priority = "event")`,
    );
  }
}

console.log("OK: 3 Plotly click handlers wait for registered raw browser events.");
