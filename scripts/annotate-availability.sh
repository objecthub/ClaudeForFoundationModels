#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# LispKit fork: marks every top-level declaration in this package as available
# only on the OS 27 releases, so that the package builds for older deployment
# targets (see Package.swift) while exposing its API only where Foundation
# Models supports server-side language models.
#
# Swift Testing rejects `@available` on `@Suite` types, so in test files the
# members of a suite are annotated one by one instead of the suite itself.
#
# The script is idempotent. Re-run it after merging a new upstream release:
#
#   scripts/annotate-availability.sh
#
set -e
cd "$(dirname "$0")/.."
ATTR='@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)'
find Sources Tests Examples -name '*.swift' | while read -r file; do
  ATTR="$ATTR" perl -i -ne '
    BEGIN {
      $attr = $ENV{ATTR};
      $prev = "";
      $suite = 0;
      $decl = qr/(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|package|final|nonisolated|static|mutating)\s+)*(?:struct|class|enum|protocol|extension|func|actor|typealias|init|var\s+\w+:[^=]*\{)/;
    }
    if (/^\}/) { $suite = 0; }
    if (/^(?:\@Suite\b.*\s)?(?:\@Suite\b|(?:struct|extension)\s)/ && ($_ =~ /\@Suite\b/ || $prev =~ /^\@Suite\b/)) {
      # A suite type: do not annotate it, annotate its members instead.
      $suite = 1;
    } elsif (/^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|package|final|nonisolated)\s+)*(?:struct|class|enum|protocol|extension|func|actor|typealias|let|var)\b/
        && $prev !~ /^\@Suite\b/ && $prev !~ m{^// lispkit: no-availability}
        && $prev !~ /^\s*\Q$attr\E$/) {
      print "$attr\n";
    } elsif ($suite && /^(  )(?:\@Test\b|$decl)/ && $prev !~ /^\s*\Q$attr\E$/ && $prev !~ /^  \@Test\b/) {
      print "  $attr\n";
    }
    print;
    chomp($prev = $_);
  ' "$file"
done
