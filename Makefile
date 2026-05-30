WASM_TARGET := wasm32-unknown-unknown
WASM_OUT    := target/$(WASM_TARGET)/release/anchorkit.wasm

.PHONY: build test wasm lint fmt fmt-check fmt-wasm lint-all lint-native lint-wasm check help

# ─────────────────────────────────────────────────────────────────────────────
# Build targets
# ─────────────────────────────────────────────────────────────────────────────

build:
	cargo build --release

test:
	cargo test

wasm:
	cargo build --release --target $(WASM_TARGET) --no-default-features --features wasm
	@ls -lh $(WASM_OUT)

# ─────────────────────────────────────────────────────────────────────────────
# Formatting targets (rustfmt)
# ─────────────────────────────────────────────────────────────────────────────

## fmt: Auto-fix code formatting for all targets
fmt:
	cargo fmt --all

## fmt-check: Check code formatting without modifying files
fmt-check:
	cargo fmt --all -- --check

## fmt-wasm: Auto-fix formatting for WASM-specific code
fmt-wasm:
	cargo fmt -- src/contract.rs src/deterministic_hash.rs

# ─────────────────────────────────────────────────────────────────────────────
# Linting targets (clippy)
# ─────────────────────────────────────────────────────────────────────────────

## lint: Run clippy on all targets with all features (strict mode)
lint: lint-all

## lint-all: Run clippy on all targets with all features
lint-all:
	cargo clippy --all-targets --all-features -- -D warnings

## lint-native: Run clippy on native targets only
lint-native:
	cargo clippy --lib --bins --tests --examples -- -D warnings

## lint-wasm: Run clippy on WASM target
lint-wasm:
	cargo clippy --target $(WASM_TARGET) --no-default-features --features wasm -- -D warnings

# ─────────────────────────────────────────────────────────────────────────────
# Combined validation targets
# ─────────────────────────────────────────────────────────────────────────────

## check: Run all quality checks (fmt-check, lint, test) - run before committing
check: fmt-check lint test
	@echo "✓ All quality checks passed!"

## check-wasm: Run quality checks for WASM target
check-wasm: fmt-check lint-wasm
	@echo "✓ WASM quality checks passed!"

# ─────────────────────────────────────────────────────────────────────────────
# Help target
# ─────────────────────────────────────────────────────────────────────────────

## help: Show this help message
help:
	@echo "AnchorKit Build Targets"
	@echo ""
	@echo "Build:"
	@echo "  make build          Build release binary"
	@echo "  make test           Run all tests"
	@echo "  make wasm           Build WASM target"
	@echo ""
	@echo "Formatting (rustfmt):"
	@echo "  make fmt            Auto-fix code formatting"
	@echo "  make fmt-check      Check formatting without modifying"
	@echo "  make fmt-wasm       Auto-fix WASM-specific code"
	@echo ""
	@echo "Linting (clippy):"
	@echo "  make lint           Run clippy on all targets (strict)"
	@echo "  make lint-all       Run clippy on all targets with all features"
	@echo "  make lint-native    Run clippy on native targets only"
	@echo "  make lint-wasm      Run clippy on WASM target"
	@echo ""
	@echo "Quality Checks:"
	@echo "  make check          Run all checks (fmt-check, lint, test)"
	@echo "  make check-wasm     Run WASM quality checks"
	@echo ""
	@echo "Other:"
	@echo "  make help           Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make check          # Before committing"
	@echo "  make fmt            # Auto-fix formatting issues"
	@echo "  make lint-wasm      # Check WASM-specific code"
