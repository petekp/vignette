# Rendered files are immutable results

A copied or dragged rendering has one unique file beside its source. Its PNG, TIFF, file URL, and terminal path refer to that same result. Completed files remain until the person deletes them because another application or agent may read them after clipboard replacement or app restart.

The filename is `<source>-<result-id>-annotated.png`. Keeping one unique output avoids the competing ownership rules of a mutable latest file plus a separate backing file. Consumers use the returned path. Automatic cleanup covers only incomplete writes.
