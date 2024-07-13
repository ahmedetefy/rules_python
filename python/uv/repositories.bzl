# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
EXPERIMENTAL: This is experimental and may be removed without notice

Create repositories for uv toolchain dependencies
"""

load("//python/uv/private:toolchain_types.bzl", "UV_TOOLCHAIN_TYPE")
load("//python/uv/private:toolchains_repo.bzl", "uv_toolchains_repo")
load("//python/uv/private:versions.bzl", "UV_PLATFORMS", "UV_TOOL_VERSIONS")

UV_BUILD_TMPL = """\
# Generated by repositories.bzl
load("@rules_python//python/uv:toolchain.bzl", "uv_toolchain")

uv_toolchain(
    name = "uv_toolchain",
    uv = "{binary}",
    version = "{version}",
)
"""

def _uv_repo_impl(repository_ctx):
    platform = repository_ctx.attr.platform
    uv_version = repository_ctx.attr.uv_version

    is_windows = "windows" in platform

    suffix = ".zip" if is_windows else ".tar.gz"
    filename = "uv-{platform}{suffix}".format(
        platform = platform,
        suffix = suffix,
    )
    url = "https://github.com/astral-sh/uv/releases/download/{version}/{filename}".format(
        version = uv_version,
        filename = filename,
    )
    if filename.endswith(".tar.gz"):
        strip_prefix = filename[:-len(".tar.gz")]
    else:
        strip_prefix = ""

    repository_ctx.download_and_extract(
        url = url,
        sha256 = UV_TOOL_VERSIONS[repository_ctx.attr.uv_version][repository_ctx.attr.platform].sha256,
        stripPrefix = strip_prefix,
    )

    binary = "uv.exe" if is_windows else "uv"
    repository_ctx.file(
        "BUILD.bazel",
        UV_BUILD_TMPL.format(
            binary = binary,
            version = uv_version,
        ),
    )

uv_repository = repository_rule(
    _uv_repo_impl,
    doc = "Fetch external tools needed for uv toolchain",
    attrs = {
        "platform": attr.string(mandatory = True, values = UV_PLATFORMS.keys()),
        "uv_version": attr.string(mandatory = True, values = UV_TOOL_VERSIONS.keys()),
    },
)

# buildifier: disable=unnamed-macro
def uv_register_toolchains(uv_version = None, register_toolchains = True):
    """Convenience macro which does typical toolchain setup

    Skip this macro if you need more control over the toolchain setup.

    Args:
        uv_version: The uv toolchain version to download.
        register_toolchains: If true, repositories will be generated to produce and register `uv_toolchain` targets.
    """
    if not uv_version:
        fail("uv_version is required")

    toolchain_names = []
    toolchain_labels_by_toolchain = {}
    toolchain_compatible_with_by_toolchain = {}

    for platform in UV_PLATFORMS.keys():
        uv_repository_name = UV_PLATFORMS[platform].default_repo_name

        uv_repository(
            name = uv_repository_name,
            uv_version = uv_version,
            platform = platform,
        )

        toolchain_name = uv_repository_name + "_toolchain"
        toolchain_names.append(toolchain_name)
        toolchain_labels_by_toolchain[toolchain_name] = "@{}//:uv_toolchain".format(uv_repository_name)
        toolchain_compatible_with_by_toolchain[toolchain_name] = UV_PLATFORMS[platform].compatible_with

    uv_toolchains_repo(
        name = "uv_toolchains",
        toolchain_type = str(UV_TOOLCHAIN_TYPE),
        toolchain_names = toolchain_names,
        toolchain_labels = toolchain_labels_by_toolchain,
        toolchain_compatible_with = toolchain_compatible_with_by_toolchain,
    )

    if register_toolchains:
        native.register_toolchains("@uv_toolchains//:all")
