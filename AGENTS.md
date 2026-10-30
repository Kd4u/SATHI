# SATHI contributor guidance

Read `CONTRIBUTING.md`, `docs/SETUP.md` and `docs/ARCHITECTURE.md` before changing behaviour.
Preserve source JSON formats, stable IDs, offline data, account isolation and conflict handling.
Keep Apple and Android feature status honest; a build or unit test is not proof of real sign-in/sync.
Do not commit personal Firebase configuration, signing files, local paths, device identifiers or account data.
Do not add chat or language-model dependencies. Preserve the explicitly authorized offline timetable cell-role classifier, its fitted JSON weights and training/evaluation checks. Run the relevant platform checks for substantive changes.
