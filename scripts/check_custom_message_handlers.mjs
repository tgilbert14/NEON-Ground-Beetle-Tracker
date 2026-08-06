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
const activeServer = server
  .split("\n")
  .map((line) => (/^\s*#/.test(line) ? "" : line))
  .join("\n");
const plotOutputs = {
  commBar: "commBar",
  ordPlot: "ordPlot",
  envrank: "envDriverRank",
};

function countMatches(source, pattern) {
  return [...source.matchAll(new RegExp(pattern.source, `${pattern.flags}g`))].length;
}

function plotOutputBlock(outputId) {
  const marker = `output$${outputId} <- renderPlotly({`;
  const start = activeServer.indexOf(marker);
  if (start < 0) throw new Error(`missing renderPlotly output ${outputId}`);
  const end = activeServer.indexOf("\n  output$", start + marker.length);
  return activeServer.slice(start, end < 0 ? activeServer.length : end);
}

for (const [source, outputId] of Object.entries(plotOutputs)) {
  const safeLifecycle = new RegExp(
    String.raw`observeEvent\(\s*session\$rootScope\(\)\$input\[\["plotly_click-${source}"\]\],\s*\{[\s\S]{0,320}?plotly::event_data\("plotly_click",\s*source\s*=\s*"${source}",\s*priority\s*=\s*"event"\)`,
  );
  if (countMatches(activeServer, safeLifecycle) !== 1) {
    throw new Error(
      `${source} must have exactly one raw-click observer before event_data(priority = "event")`,
    );
  }

  const eagerLifecycle = new RegExp(
    String.raw`observeEvent\(\s*(?:plotly::)?event_data\(\s*"plotly_click",\s*source\s*=\s*"${source}"`,
  );
  if (eagerLifecycle.test(activeServer)) {
    throw new Error(`${source} must not call event_data() as its observer trigger`);
  }

  const block = plotOutputBlock(outputId);
  if (!new RegExp(String.raw`source\s*=\s*"${source}"`).test(block)) {
    throw new Error(`${outputId} must retain Plotly source ${source}`);
  }
  if (!/plotly::event_register\(\s*"plotly_click"\s*\)/.test(block)) {
    throw new Error(`${outputId} must register plotly_click before browser events`);
  }
}

console.log("OK: 3 registered Plotly sources reject eager reads and wait for raw browser events.");
