# Security

This project is an MVP and has not received an independent security audit.

Do not post authentication tokens, signing keys, account exports, personal notebook pages or exploitable account-isolation details in public issues. Use GitHub's private vulnerability reporting, if enabled, or contact the maintainer privately through the contact methods they choose to publish on their GitHub profile. If neither is available, open a minimal issue requesting a private contact channel without revealing the vulnerability.

For development, use your own Firebase project and synthetic test accounts. The rules in `firebase/firestore.rules` restrict each account to its own `users/{uid}` tree. Never replace them with public read/write rules to fix a setup issue. The project does not include admin SDK credentials or client-side privileged access.

Client Firebase configuration is not a service-account key, but production client configuration is excluded here so forks do not accidentally use the maintainer's backend. APK releases necessarily contain the Firebase client configuration they were built with; access protection must come from authentication, appropriate API restrictions and server-side rules.

Account caches and unsynced changes live on the device. Do not uninstall or clear storage as a troubleshooting step without a backup. Confirm save/restore and conflicting-device behaviour when changing persistence or sync code.
