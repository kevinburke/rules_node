_js_filetype = FileType([".js"])
_modules_filetype = FileType(["node_modules"])

BASH_TEMPLATE = """
#!/usr/bin/env bash
set -e

# Resolve to 'this' node instance if other scripts
# have '/usr/bin/env node' shebangs
export PATH={node_bin_path}:$PATH

# Used by NPM
export NODE_PATH={node_paths}

# Run it
"{node_bin}" "{script_path}" $@
"""


def _get_node_modules_dir_from_package_json(file):
    filename = str(file)
    parts = filename.split("]")
    prefix = parts[0][len("Artifact:[["):]
    middle = parts[1]
    suffix = parts[2].split("/")
    d = "/".join([prefix, middle] + suffix[0:-3] + ["node_modules"])
    return d



def _get_node_modules_dir_from_sourcefile(file):
    bin = str(file)
    parts = bin.partition("[source]]")
    prefix = parts[0][len("Artifact:["):]
    suffix_parts = parts[2].split("/")
    return "/".join([prefix] + suffix_parts)


def node_binary_impl(ctx):
    inputs = []
    srcs = []
    node_paths = []
    script = ctx.file.main

    for file in ctx.files.modules:
        if not file.basename.endswith("node_modules"):
            fail("npm_dependency should be a path to a node_modules/ directory.")
        node_paths += [_get_node_modules_dir_from_sourcefile(file)]

    for dep in ctx.attr.deps:
        lib = dep.node_library
        srcs += lib.transitive_srcs
        inputs += [lib.package_json]
        inputs += [lib.npm_package_json]
        node_paths += [_get_node_modules_dir_from_package_json(lib.package_json)]

    node_paths = list(set(node_paths))
    node = ctx.file._node

    ctx.file_action(
        output = ctx.outputs.executable,
        executable = True,
        content = BASH_TEMPLATE.format(
            node_bin = node.short_path,
            script_path = script.short_path,
            node_bin_path = node.dirname,
            node_paths = ":".join(node_paths),
        ),
    )

    #print("node_paths %s" % "\n".join(node_paths))

    runfiles = [node, script] + inputs + srcs

    return struct(
        runfiles = ctx.runfiles(
            files = runfiles,
        ),
    )

node_binary = rule(
    node_binary_impl,
    attrs = {
        "main": attr.label(
            single_file = True,
            allow_files = _js_filetype,
        ),
        "data": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            providers = ["node_library"],
        ),
        "modules": attr.label_list(
            allow_files = _modules_filetype,
        ),
        "_node": attr.label(
            default = Label("@org_pubref_rules_node_toolchain//:node_tool"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
    executable = True,
)
