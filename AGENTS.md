# Resource limits on this VPS

- This shared VPS has about 8 GB RAM and no swap. Preserve memory for its running services.
- Do not run Android APK/release builds on this VPS. Use CI or another build machine.
- Run analyzers, tests and standalone compiler checks one at a time in a container with explicit limits: at most 1536 MB RAM, the same memory-plus-swap limit (no swap), one CPU and 192 PIDs. Never launch unrestricted build containers or parallel validation jobs.
- Check available memory before validation. If a capped check runs out of memory, report it or move it to CI; do not increase the cap or retry without limits.
- Keep Gradle workers at one and compile Kotlin in process; do not restore the old 8 GB JVM heaps.
