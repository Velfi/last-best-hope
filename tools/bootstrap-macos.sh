#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: tools/bootstrap-macos.sh only supports macOS" >&2
	exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
	echo "error: Homebrew is required: https://brew.sh" >&2
	exit 1
fi

# toolchain.mk contains shell-compatible assignments.
# shellcheck disable=SC1091
. "$ROOT/toolchain.mk"

echo "Installing native build dependencies..."
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install pkg-config harfbuzz freetype odinfmt "$LLVM_HOMEBREW_FORMULA"

case "$(uname -m)" in
	arm64)
		ODIN_ARCHIVE=$ODIN_MACOS_ARM64_ARCHIVE
		ODIN_SHA256=$ODIN_MACOS_ARM64_SHA256
		SLANG_ARCHIVE=$SLANG_MACOS_ARM64_ARCHIVE
		SLANG_SHA256=$SLANG_MACOS_ARM64_SHA256
		;;
	x86_64)
		ODIN_ARCHIVE=$ODIN_MACOS_AMD64_ARCHIVE
		ODIN_SHA256=$ODIN_MACOS_AMD64_SHA256
		SLANG_ARCHIVE=$SLANG_MACOS_AMD64_ARCHIVE
		SLANG_SHA256=$SLANG_MACOS_AMD64_SHA256
		;;
	*)
		echo "error: unsupported macOS architecture: $(uname -m)" >&2
		exit 1
		;;
esac

TOOLS_DIR="$ROOT/.tools"
ODIN_DIR="$TOOLS_DIR/odin/$ODIN_VERSION"
SLANG_DIR="$TOOLS_DIR/slang/$SLANG_VERSION"
DOWNLOAD_DIR="$TOOLS_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

verify_sha256() {
	archive=$1
	expected=$2
	actual=$(shasum -a 256 "$archive" | awk '{print $1}')
	if [ "$actual" != "$expected" ]; then
		echo "error: checksum mismatch for $archive" >&2
		echo "expected: $expected" >&2
		echo "actual:   $actual" >&2
		exit 1
	fi
}

if [ ! -x "$ODIN_DIR/odin" ]; then
	archive_path="$DOWNLOAD_DIR/$ODIN_ARCHIVE"
	url="https://github.com/odin-lang/Odin/releases/download/$ODIN_VERSION/$ODIN_ARCHIVE"
	echo "Downloading Odin $ODIN_VERSION..."
	curl -fL --retry 3 -o "$archive_path" "$url"
	verify_sha256 "$archive_path" "$ODIN_SHA256"
	stage=$(mktemp -d "${TMPDIR:-/tmp}/last-best-hope-odin.XXXXXX")
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	tar -xzf "$archive_path" -C "$stage"
	extracted=$(find "$stage" -type f -name odin -perm -111 | head -1)
	if [ -z "$extracted" ]; then
		echo "error: Odin archive did not contain an executable" >&2
		exit 1
	fi
	extracted_root=$(dirname "$extracted")
	mkdir -p "$(dirname "$ODIN_DIR")"
	rm -rf "$ODIN_DIR"
	mv "$extracted_root" "$ODIN_DIR"
	rm -rf "$stage"
	trap - EXIT HUP INT TERM
else
	echo "Odin $ODIN_VERSION is already installed."
fi

if [ ! -x "$SLANG_DIR/slangc" ]; then
	archive_path="$DOWNLOAD_DIR/$SLANG_ARCHIVE"
	url="https://github.com/shader-slang/slang/releases/download/$SLANG_VERSION/$SLANG_ARCHIVE"
	echo "Downloading Slang $SLANG_VERSION..."
	curl -fL --retry 3 -o "$archive_path" "$url"
	verify_sha256 "$archive_path" "$SLANG_SHA256"
	stage=$(mktemp -d "${TMPDIR:-/tmp}/last-best-hope-slang.XXXXXX")
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	unzip -q "$archive_path" -d "$stage"
	extracted=$(find "$stage" -type f -name slangc -perm -111 | head -1)
	if [ -z "$extracted" ]; then
		echo "error: Slang archive did not contain slangc" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$SLANG_DIR")"
	rm -rf "$SLANG_DIR"
	mv "$stage" "$SLANG_DIR"
	trap - EXIT HUP INT TERM
else
	echo "Slang $SLANG_VERSION is already installed."
fi

echo "Bootstrap complete."
echo "Run: make doctor"
