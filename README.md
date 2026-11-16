# Caffeinate

Inspired by [Caffeine](https://zhornsoftware.co.uk/caffeine/), made to run where exe files are a no-go. 

## Setup
Just download and extract the project anywhere on your machine (like `%USERPROFILE%\bin\caffeinate` for instance), and add it to the path.

## Usage

```sh
caf start [minutes] [--force]
caf extend <minutes>
caf status
caf logs
caf stop
```

Default duration for `caf start` is 300 minutes. State and logs are stored under `%LOCALAPPDATA%\Caffainate\`.

If `caf start` is run while a session is already active, it asks wether you'd like to extend the current session instead of failing outright. The `--force` flag is made to skip this and force a new session explicitely.

*Caffeinate* works in the background. If you wish to watch what's happening, just run `caf logs`.

## LICENSE
[AGPL 3](./LICENSE)
