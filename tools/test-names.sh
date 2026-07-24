#!/bin/sh
# Print the Odin @(test) procedure names found in the supplied source files as
# the comma-separated selector accepted by core:testing.
perl -ne '
	if (/^\s*package\s+([A-Za-z_][A-Za-z0-9_]*)/) {
		$package = $1;
	}
	if (/\@\(test\)/) {
		$pending = 1;
		next;
	}
	if ($pending && /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*::\s*proc\b/) {
		push @names, ($package ? "$package.$1" : $1);
		$pending = 0;
	}
	END {
		print join(",", @names), "\n";
	}
' "$@"
