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

"""Helper utilities and constants for VHDL rules and graph inspection."""

load("//vhdl:providers.bzl", "VhdlLibraryInfo", "VhdlNodeInfo")

# Constants for VHDL versioning and library names
VHDL_VERSIONS = ["87", "93", "2008", "2019"]
DEFAULT_VHDL_VERSION = "2008"
RESERVED_LIB_NAMES = ["std", "ieee"]

# Name of the default library as seen by the rules (before sealing).
WORK_LIB = "work"
_WORK = WORK_LIB

_LETTERS = "abcdefghijklmnopqrstuvwxyz"
_DIGITS = "0123456789"

def normalize_library_name(name, label):
    """Validates a library name and returns it normalized.

    VHDL identifiers are case-insensitive, so the name is lower-cased: `Work`
    and `work` are the same library. A basic identifier is required: it starts
    with a letter, then letters, digits and single underscores, and it does not
    end with an underscore.

    Args:
        name: The `library_name` attribute value.
        label: Label of the target, for error messages.

    Returns:
        The lower-case library name.
    """
    lname = name.lower()
    if not lname:
        fail("Target '{}': library_name cannot be empty.".format(label))
    if lname in RESERVED_LIB_NAMES:
        fail("Library name '{}' is reserved and cannot be used (target '{}').".format(name, label))
    if lname[0] not in _LETTERS:
        fail("Target '{}': library name '{}' must start with a letter.".format(label, name))
    previous = ""
    for c in lname.elems():
        if c == "_":
            if previous == "_":
                fail("Target '{}': library name '{}' cannot contain consecutive underscores.".format(label, name))
        elif c not in _LETTERS and c not in _DIGITS:
            fail("Target '{}': library name '{}' contains the invalid character '{}'.".format(label, name, c))
        previous = c
    if lname[-1] == "_":
        fail("Target '{}': library name '{}' cannot end with an underscore.".format(label, name))
    return lname

def module_record(module):
    """Internal representation of a module attached to a VhdlLibraryUnitInfo."""
    return struct(
        entity_name = module.entity_name,
        generics = tuple(sorted(module.generics.items())),
        label = module.label,
    )

def label_str(label):
    """'@repo//package:name' (or '//package:name' in the main repository) from a Label or a string."""
    if type(label) == "string":
        return label
    repo = label.workspace_name
    return "%s//%s:%s" % (("@" + repo) if repo else "", label.package, label.name)

def node_of(info):
    """The graph node of a VhdlLibraryInfo; infos built without one are an empty virtual node."""
    node = getattr(info, "node", None)
    if node != None:
        return node
    return VhdlNodeInfo(label = None, library_name = None, vhdl_version = None, direct_deps = (), srcs = (), data = ())

def as_infos(vhdl_info):
    """Normalizes Target(s) and/or VhdlLibraryInfo value(s) to a list of VhdlLibraryInfo."""
    items = vhdl_info if type(vhdl_info) == "list" else [vhdl_info]
    infos = []
    for item in items:
        if type(item) == "Target":
            if VhdlLibraryInfo not in item:
                fail("Target '{}' does not provide VhdlLibraryInfo".format(item.label))
            infos.append(item[VhdlLibraryInfo])
        elif hasattr(item, "all_libs") and hasattr(item, "transitive_srcs"):
            infos.append(item)
        else:
            fail("Expected a Target providing VhdlLibraryInfo or a VhdlLibraryInfo, got '{}'".format(item))
    return infos

def extract_modules(vhdl_info):
    """The modules (vhdl_module entities) of Target(s) providing VhdlLibraryInfo.

    Each module comes with the library it is compiled into.
    The result is in compile order, and a module reachable through a
    vhdl_library dependency is listed like any other. The entities used by a
    module are the entries before it.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        A list of structs with the fields entity_name, generics (dict),
        label (of the vhdl_module), library_name and vhdl_version.
    """
    units = depset(transitive = [info.all_libs for info in as_infos(vhdl_info)], order = "postorder").to_list()
    return [
        struct(
            entity_name = module.entity_name,
            generics = dict(module.generics),
            label = module.label,
            library_name = unit.library_name,
            vhdl_version = unit.vhdl_version,
        )
        for unit in units
        for module in (getattr(unit, "modules", None) or ())
    ]

def find_module(vhdl_info, entity_name, library_name = None):
    """Finds one module by entity name, optionally in one library.

    VHDL names are case-insensitive. Several modules can share an entity name
    (different generics, or a default-library copy next to a sealed one): the
    lookup fails when it is ambiguous, and the message lists the candidates.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        entity_name: Entity name to look for.
        library_name: Restrict the search to this library.

    Returns:
        A struct as returned by `extract_modules`.
    """
    entity = entity_name.lower()
    library = library_name.lower() if library_name else None
    found = [
        module
        for module in extract_modules(vhdl_info)
        if module.entity_name.lower() == entity and (library == None or module.library_name == library)
    ]
    if not found:
        fail("No module with entity '{}'{} in the VHDL dependencies.".format(
            entity_name,
            " in library '{}'".format(library_name) if library_name else "",
        ))
    if len(found) > 1:
        fail("Entity '{}' is ambiguous: {}. Pass library_name, or depend on one module.".format(
            entity_name,
            ", ".join(["{} (library '{}')".format(m.label, m.library_name) for m in found]),
        ))
    return found[0]
