# Settings persistence

Settings should distinguish an applied change from a saved change. The current runtime writer logs changed UI values and advances its saved comparison before checking whether the atomic write succeeded. Its caller ignores the returned failure. A failed write can therefore look saved and suppress the next useful diagnostic.

Keep the existing immediate application and coalesced disk write. Slider movement should remain fluid. Add a persistence outcome to `Settings`: saved, pending, or failed with the actual write reason. Advance the last saved bytes and values only after a successful write. A new change or explicit retry writes the current validated value. Normal quit flushes the pending value and reports the result.

Use the existing General-tab notice for an unsaved settings failure. Read-only configuration from a newer version remains a distinct condition. A successful later write clears the failure. Do not add one alert for each slider event.

Apply the same validation at load, external reload, and app update. `update` currently applies its changed value directly. Validation should normalize the candidate before effects and encoding, so the file and running app agree. Preserve settings that intentionally keep an unrecognized raw value for a supported fallback; trace each existing validator before changing that behavior.

Read failure is also distinct from absence. `Settings.load` currently maps any failed `Data(contentsOf:)` to missing. Bootstrap must create first-run settings only for a confirmed missing file. An existing unreadable file should remain intact and produce a read-only launch notice. It must not be treated as a first launch. Setup currently reads the fallback `setup=unasked` directly, so it needs an explicit unresolved-startup outcome before making first-launch changes. This matters at the permission and filesystem boundary, even when no JSON parse occurred.

After an unreadable launch, permission recovery must reread the original file before allowing a write. Fallback defaults are not an intended replacement. Keep any later user changes separate until the file can be reread, and reconcile only those explicit changes. A known runtime write failure may retry its current applied value directly.

Implementation remains in `Settings`, setup admission, and the General-tab notice consumer. Publish the runtime persistence outcome; the current immutable startup notice and read-only flag cannot represent recovery. A persistence helper can accept a URL for scratch verification if it removes singleton dependence from a real production operation. Avoid adding a second settings owner or a general transaction layer.

Verification extends the existing bootstrap and validation tests. Use an existing unreadable file, a real atomic-write refusal, a successful retry, and a candidate that needs clamping. Assert preserved file contents, the running value, and the saved value. Native verification changes only scratch settings, confirms the notice and recovery, and then restarts that copy to read the saved result.

State: bounded plan ready. Runtime persistence and unreadable-file behavior remain unchanged.
