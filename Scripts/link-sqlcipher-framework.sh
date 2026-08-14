#!/bin/sh
# SwiftPM ne copie pas automatiquement un binaryTarget référencé seulement de façon transitive
# (notre dépendance directe est GRDB, qui dépend lui-même de SQLCipher.swift) dans le dossier
# `PackageFrameworks` que les bundles de test/exécution recherchent au runtime (DRO-51). Sans ce
# lien, `swift test` et `swift run` échouent avec « Library not loaded: @rpath/SQLCipher.framework ».
# À relancer après tout `swift package clean`/suppression de `.build`.
set -eu

build_dir="$(dirname "$0")/../.build/out/Products/Debug"
framework="$build_dir/SQLCipher.framework"
link_dir="$build_dir/PackageFrameworks"

if [ ! -d "$framework" ]; then
    echo "SQLCipher.framework introuvable dans $build_dir — lancez d'abord 'swift build'." >&2
    exit 1
fi

mkdir -p "$link_dir"
ln -sf "../SQLCipher.framework" "$link_dir/SQLCipher.framework"
echo "Lien créé : $link_dir/SQLCipher.framework -> ../SQLCipher.framework"
