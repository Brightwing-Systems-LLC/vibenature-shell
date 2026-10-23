#!/bin/sh
# Builds the macOS window extension when its source is newer than the library.
set -e
cd "$(dirname "$0")"
[ "$(uname)" = "Darwin" ] || exit 0
lib=bin/libvibenature_macos_windows.dylib
if [ ! -f "$lib" ] || [ macos_windows.m -nt "$lib" ]; then
	mkdir -p bin
	clang -fno-objc-arc -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
		-framework Cocoa -framework CoreGraphics -weak_framework ServiceManagement -O2 -Wall -Wno-deprecated-declarations -o "$lib" macos_windows.m
fi
