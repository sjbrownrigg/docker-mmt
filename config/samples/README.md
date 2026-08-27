# samples/

Reference copies of every configurable file, refreshed from the image each time
the container starts. They track the installed version, so they are the right
thing to diff against after an upgrade.

**These files are never loaded at runtime and editing them has no effect.**
Copy one up a level and edit the copy.

That is deliberate. Defaults used to be read from a sample file loaded
underneath your own config, which meant a setting could take effect without
appearing anywhere in the file you were reading. Defaults now live in
`discogstagger/config_schema.py`, and these samples document them.
