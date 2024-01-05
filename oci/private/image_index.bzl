"Implementation details for oci_image_index rule"

_DOC = """Build a multi-architecture OCI compatible container image.

It takes number of `oci_image`s  to create a fat multi-architecture image.

Requires `wc` and either `sha256sum` or `shasum` to be installed on the execution machine.

```starlark
oci_image(
    name = "app_linux_amd64"
)

oci_image(
    name = "app_linux_arm64"
)

oci_image_index(
    name = "app",
    images = [
        ":app_linux_amd64",
        ":app_linux_arm64"
    ]
)
```
"""

_attrs = {
    "images": attr.label_list(mandatory = True, doc = "List of labels to oci_image targets."),
    "_image_index_sh": attr.label(default = "image_index.sh", allow_single_file = True),
}

def _expand_image_to_args(image, expander):
    args = [
        "--image={}".format(image.path),
    ]
    for file in expander.expand(image):
        if file.path.find("blobs") != -1:
            args.append("--blob={}".format(file.tree_relative_path))
    return args

def _oci_image_index_impl(ctx):
    yq = ctx.toolchains["@aspect_bazel_lib//lib:yq_toolchain_type"]
    coreutils = ctx.toolchains["@aspect_bazel_lib//lib:coreutils_toolchain_type"]

    output = ctx.actions.declare_directory(ctx.label.name)

    args = ctx.actions.args()
    args.add(output.path, format = "--output=%s")
    args.add_all(ctx.files.images, map_each = _expand_image_to_args, expand_directories = False)

    action_env = {
        "YQ": yq.yqinfo.bin.path,
        "COREUTILS": coreutils.coreutils_info.bin.path,
    }

    ctx.actions.run(
        inputs = ctx.files.images,
        arguments = [args],
        outputs = [output],
        env = action_env,
        executable = ctx.file._image_index_sh,
        tools = [yq.yqinfo.bin, coreutils.coreutils_info.bin],
        mnemonic = "OCIIndex",
        progress_message = "OCI Index %{label}",
    )

    return DefaultInfo(files = depset([output]))

oci_image_index = rule(
    implementation = _oci_image_index_impl,
    attrs = _attrs,
    doc = _DOC,
    toolchains = [
        "@aspect_bazel_lib//lib:yq_toolchain_type",
        "@aspect_bazel_lib//lib:coreutils_toolchain_type",
    ],
)
