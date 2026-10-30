# Stats for iOS

Terms for the Mac companion and iPhone app that share Mac activity.

## Language

**Companion**:
The Mac app that gathers activity and makes it available to authorized iPhones.
_Avoid_: server app, host app

**Passcode**:
A short, human-readable code used during pairing. It is not the sole secret protecting activity.
_Avoid_: setup key, password

**Pairing session**:
A temporary opportunity for one new phone to pair with the companion using a passcode.
_Avoid_: permanent pairing code

**Paired phone**:
An iPhone the companion has authorized and remembers for future access.
_Avoid_: connected phone

**Phone credential**:
A secret issued to one paired phone for future access to the companion.
_Avoid_: shared setup key

**Connected phone**:
A paired phone that has successfully fetched activity recently.
_Avoid_: paired phone
