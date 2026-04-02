import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerCheckEnvironment } from "./tools/check-environment.ts";
import { registerGenerateConfig } from "./tools/generate-config.ts";
import { registerRunStage } from "./tools/run-stage.ts";
import { registerGetReport } from "./tools/get-report.ts";

const server = new McpServer({
  name: "chipagent-backend",
  version: "0.1.0",
});

registerCheckEnvironment(server);
registerGenerateConfig(server);
registerRunStage(server);
registerGetReport(server);

const transport = new StdioServerTransport();
await server.connect(transport);
