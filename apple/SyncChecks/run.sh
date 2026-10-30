#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ -n "${DEVELOPER_DIR:-}" ]]; then export DEVELOPER_DIR; fi
checks_dir=$(mktemp -d "${TMPDIR:-/tmp}/SATHI-Checks.XXXXXX")
compile() { xcrun swiftc -module-cache-path "$checks_dir/Modules" "$@"; }
compile SWIFT/SyncSnapshot.swift SyncChecks/main.swift -o "$checks_dir/merge"
"$checks_dir/merge"
compile SWIFT/ActivityJournal.swift SyncChecks/Journal/check.swift -o "$checks_dir/journal"
"$checks_dir/journal"
compile SWIFT/AccountStorage.swift SWIFT/ActivityJournal.swift SWIFT/SyncSnapshot.swift SyncChecks/Accounts/check.swift -o "$checks_dir/accounts"
"$checks_dir/accounts"
compile SWIFT/TimetableModels.swift SWIFT/StudyDomain.swift SyncChecks/Study/check.swift -o "$checks_dir/study"
"$checks_dir/study"

compile SWIFT/SharedSurfaces.swift SWIFT/SyncSnapshot.swift SyncChecks/Widgets/check.swift -o "$checks_dir/widgets"
"$checks_dir/widgets"

compile SWIFT/NotebookModels.swift SWIFT/TimetableModels.swift SWIFT/StudyDomain.swift SWIFT/SharedSurfaces.swift SWIFT/EventPresentation.swift SyncChecks/Notebook/check.swift -o "$checks_dir/notebook"
"$checks_dir/notebook"

compile SWIFT/TimetableCellClassifier.swift SyncChecks/Classifier/check.swift -o "$checks_dir/classifier"
"$checks_dir/classifier" SWIFT/TimetableCellRole.json
