#
# From: http://www.gnu.org/software/make/manual/make.html
#

SRC_DIR=src
BIN_DIR=bin
LIB_DIR=lib
TEST_DIR=test

CLIENT_SOURCES:=$(wildcard $(SRC_DIR)/*.coffee)
TEST_SOURCES:=$(wildcard $(TEST_DIR)/*.coffee)

CLIENT_OBJECTS:=$(patsubst $(SRC_DIR)/%.coffee,$(LIB_DIR)/%.js,$(CLIENT_SOURCES))
TEST_OBJECTS:=$(patsubst $(TEST_DIR)/%.coffee,$(LIB_DIR)/%.js,$(TEST_SOURCES))

TEST_RUNNERS_SOURCES:=$(wildcard $(TEST_DIR)/*-test.coffee)
TEST_RUNNERS:=$(patsubst $(TEST_DIR)/%-test.coffee,$(LIB_DIR)/%-test.js,$(TEST_RUNNERS_SOURCES))

BIN_OBJECTS=$(BIN_DIR)/mock-http-proxy

# Detect if we're running Windows
ifdef SystemRoot
# If so, set the file & folder deletion commands:
	RM = del /Q /F
	FixPath = $(subst /,\,$1)
else
# Otherwise, assume we're running *N*X:
	RM = rm -f
	FixPath = $1
endif

all: build

.PHONY: build
build: modules $(CLIENT_OBJECTS) $(BIN_OBJECTS)


.PHONY: build_test
build_test: build $(TEST_OBJECTS)

.PHONY: build_test_runners
build_test_runners: build_test $(TEST_RUNNERS)

.PHONY: test
test: build_test_runners
	rm test/fixtures/*.response
	vows --spec $(TEST_RUNNERS)

.PHONY: clean
clean:
	$(RM) $(call FixPath,$(BIN_DIR)/*)
	$(RM) $(call FixPath,$(LIB_DIR)/*.js)

.PHONY: pristine
pristine: clean
	$(RM) -r node_modules

.PHONY: modules
modules: node_modules

node_modules:
	npm install -d

.PHONY: debug
debug: build
	echo 'Make sure to start node-inspector!'
	nodemon --debug-brk server.js

.PHONY: watch
watch:
	coffee --watch -o $(LIB_DIR) -c $(SRC_DIR) $(TEST_DIR)

$(BIN_DIR)/mock-http-proxy: $(CLIENT_OBJECTS)
	echo "#!/usr/bin/env node" > $(BIN_DIR)/mock-http-proxy
	cat $(LIB_DIR)/app.js >> $(BIN_DIR)/mock-http-proxy
	chmod ug+x $(BIN_DIR)/mock-http-proxy

$(LIB_DIR)/%.js: $(SRC_DIR)/%.coffee
	coffee -o $(LIB_DIR) -c $<

$(LIB_DIR)/%.js: $(TEST_DIR)/%.coffee
	coffee -o $(LIB_DIR) -c $<
