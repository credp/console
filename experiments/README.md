# Experiments

Create a numbered experiment from the local MiSTer template checkout:

```bash
cd experiments
./new-experiment 003-example-name
```

The script exports only files tracked at the template's current `HEAD`, so the
new directory contains neither `.git` metadata nor local template build output.
It refuses to overwrite an existing experiment.

Each generated experiment gets a small `build.sh` wrapper around
`harness/build-quartus-experiment`. Quartus/Verilator policy therefore lives in
one place while project sources, pin constraints, and the QIP manifest remain
local and reviewable. Environment variables such as `PROJECT_FILE`,
`QUARTUS_ROOTDIR`, `LINT_TOP`, and `LINT_ENTRY` can override harness defaults.

The default template checkout is:

```text
../../vendor/Template_MiSTer
```

From this repository, that resolves to the sibling checkout at
`/home/chris/Projects/vendor/Template_MiSTer`. Update it independently when a
new template version is wanted:

```bash
git -C ../vendor/Template_MiSTer pull --ff-only
```

To use another checkout for one invocation:

```bash
MISTER_TEMPLATE_DIR=/path/to/Template_MiSTer ./new-experiment 003-example-name
```
