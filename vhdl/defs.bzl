#    Copyright 2026 Nocilis
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

"""Public API for VHDL rules, providers, and graph visualization."""

load(
    "//vhdl:providers.bzl",
    _VhdlConfigInfo = "VhdlConfigInfo",
    _VhdlLibraryInfo = "VhdlLibraryInfo",
    _VhdlLibraryUnitInfo = "VhdlLibraryUnitInfo",
    _VhdlModuleInfo = "VhdlModuleInfo",
    _VhdlNodeInfo = "VhdlNodeInfo",
)
load(
    "//vhdl:graph.bzl",
    _extract_graph = "extract_graph",
    _graph_dot = "graph_dot",
    _graph_tree = "graph_tree",
    _vhdl_graph = "vhdl_graph",
)
load(
    "//vhdl:utils.bzl",
    _DEFAULT_VHDL_VERSION = "DEFAULT_VHDL_VERSION",
    _RESERVED_LIB_NAMES = "RESERVED_LIB_NAMES",
    _VHDL_VERSIONS = "VHDL_VERSIONS",
    _WORK_LIB = "WORK_LIB",
    _extract_modules = "extract_modules",
    _find_module = "find_module",
)
load(
    "//vhdl:vhdl.bzl",
    _extract_data = "extract_data",
    _extract_sources = "extract_sources",
    _extract_srcs = "extract_srcs",
    _group_segments = "group_segments",
    _merge_vhdl_library_infos = "merge_vhdl_library_infos",
    _ordered_segments = "ordered_segments",
    _vhdl_flag = "vhdl_flag",
    _vhdl_library = "vhdl_library",
    _vhdl_library_info = "vhdl_library_info",
    _vhdl_module = "vhdl_module",
)
load(
    "//vhdl:translation.bzl",
    _vhdl_translate = "vhdl_translate",
    _vhdl_translate_and_verify = "vhdl_translate_and_verify",
    _vhdl_wrapper = "vhdl_wrapper",
)

# Providers
VhdlConfigInfo = _VhdlConfigInfo
VhdlLibraryInfo = _VhdlLibraryInfo
VhdlLibraryUnitInfo = _VhdlLibraryUnitInfo
VhdlModuleInfo = _VhdlModuleInfo
VhdlNodeInfo = _VhdlNodeInfo

# Core rules and flags
vhdl_library = _vhdl_library
vhdl_module = _vhdl_module
vhdl_flag = _vhdl_flag
vhdl_library_info = _vhdl_library_info
merge_vhdl_library_infos = _merge_vhdl_library_infos

# Graph rules and utilities
vhdl_graph = _vhdl_graph
extract_graph = _extract_graph
graph_dot = _graph_dot
graph_tree = _graph_tree

# Source extraction and ordering
ordered_segments = _ordered_segments
extract_sources = _extract_sources
group_segments = _group_segments
extract_modules = _extract_modules
find_module = _find_module
extract_srcs = _extract_srcs
extract_data = _extract_data

# Translation rules
vhdl_translate = _vhdl_translate
vhdl_wrapper = _vhdl_wrapper
vhdl_translate_and_verify = _vhdl_translate_and_verify

# Constants
VHDL_VERSIONS = _VHDL_VERSIONS
DEFAULT_VHDL_VERSION = _DEFAULT_VHDL_VERSION
RESERVED_LIB_NAMES = _RESERVED_LIB_NAMES
WORK_LIB = _WORK_LIB
