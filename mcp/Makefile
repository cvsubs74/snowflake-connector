# mcp/Makefile — helpers for authoring + packaging project MCP servers.
#
# Conventions:
#   mcp/servers/<name>/         source
#   mcp/dist/<name>.mcpb        packaged artifact

DIST := dist
SERVERS_DIR := servers

.PHONY: help init pack pack-all clean

help:
	@echo "make init NAME=<server-name>       # scaffold a new MCP server"
	@echo "make pack NAME=<server-name>       # package one server as .mcpb"
	@echo "make pack-all                      # package all servers in $(SERVERS_DIR)/"
	@echo "make clean                         # remove $(DIST)/"

init:
	@test -n "$(NAME)" || (echo "ERROR: NAME=<server-name> required"; exit 2)
	@mkdir -p $(SERVERS_DIR)/$(NAME)
	@cd $(SERVERS_DIR)/$(NAME) && npx -y @anthropic-ai/mcpb init

pack:
	@test -n "$(NAME)" || (echo "ERROR: NAME=<server-name> required"; exit 2)
	@mkdir -p $(DIST)
	@cd $(SERVERS_DIR)/$(NAME) && npx -y @anthropic-ai/mcpb pack -o ../../$(DIST)/$(NAME).mcpb

pack-all:
	@mkdir -p $(DIST)
	@for dir in $(SERVERS_DIR)/*/; do \
	  name=$$(basename $$dir); \
	  echo "→ packing $$name"; \
	  cd $$dir && npx -y @anthropic-ai/mcpb pack -o ../../$(DIST)/$$name.mcpb && cd ../..; \
	done

clean:
	@rm -rf $(DIST)/
