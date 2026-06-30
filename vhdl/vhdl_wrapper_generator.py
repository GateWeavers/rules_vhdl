#!/usr/bin/env python3
import sys
import os
import argparse
import subprocess
import xml.etree.ElementTree as ET

def parse_subtype_indication(sub_ind):
    if sub_ind is None:
        return "std_logic"
    kind = sub_ind.attrib.get('kind')
    
    if kind == 'array_subtype_definition':
        type_mark = sub_ind.find('subtype_type_mark')
        type_name = type_mark.attrib.get('identifier') if type_mark is not None else "std_logic_vector"
        
        index_constraints = []
        index_list = sub_ind.find('index_constraint_list')
        if index_list is not None:
            for index_el in index_list.findall('el'):
                range_const = index_el.find('range_constraint')
                if range_const is not None and range_const.attrib.get('kind') == 'range_expression':
                    direction = range_const.attrib.get('direction')
                    left_node = range_const.find('left_limit_expr')
                    right_node = range_const.find('right_limit_expr')
                    if left_node is not None and right_node is not None:
                        left = left_node.attrib.get('value', '').strip()
                        right = right_node.attrib.get('value', '').strip()
                        index_constraints.append(f"{left} {direction} {right}")
                        
        if index_constraints:
            return f"{type_name}({', '.join(index_constraints)})"
        return type_name
        
    identifier = sub_ind.attrib.get('identifier')
    if identifier:
        return identifier
        
    return "std_logic"

def rebuild_selected_name(el):
    if el is None:
        return ""
    kind = el.attrib.get('kind')
    if kind == 'selected_by_all_name':
        prefix = el.find('prefix')
        return rebuild_selected_name(prefix) + ".all"
    elif kind == 'selected_name':
        prefix = el.find('prefix')
        identifier = el.attrib.get('identifier', '')
        if prefix is not None:
            return rebuild_selected_name(prefix) + "." + identifier
        else:
            return identifier
    elif kind == 'simple_name':
        return el.attrib.get('identifier', '')
    return ""

def run_ghdl_commands(ghdl_bin, sources_info, std_flag, library_name):
    # Set GHDL_PREFIX environment variable hermetically
    os.environ["GHDL_PREFIX"] = os.path.abspath(os.path.join(os.path.dirname(ghdl_bin), "..", "lib", "ghdl"))
    
    # 1. Analyze each file in the respective library databases
    for lib, std, path in sources_info:
        subprocess.run([ghdl_bin, "-a", f"--std={std}", f"--work={lib}", path], check=True)
        
    # 2. Run file-to-xml and return stdout
    file_paths = [path for _, _, path in sources_info]
    cmd = [ghdl_bin, "file-to-xml", f"--std={std_flag}", f"--work={library_name}"] + file_paths
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return res.stdout

def parse_ast_xml(xml_content, entity_name, reverse):
    root = ET.fromstring(xml_content)

    # Build a lookup map of ALL elements by id
    elements = {}
    for el in root.iter():
        el_id = el.attrib.get('id')
        if el_id:
            elements[el_id] = el

    # 1. Extract record definitions
    records = {}
    for el in root.iter():
        if el.attrib.get('kind') == 'type_declaration':
            type_name = el.attrib.get('identifier')
            type_def = el.find('type_definition')
            if type_def is not None and type_def.attrib.get('kind') == 'record_type_definition':
                def_id = type_def.attrib.get('id')
                
                # Trace parent package declaration to get package name
                pkg_name = None
                parent_node = el.find('parent')
                if parent_node is not None:
                    parent_ref = parent_node.attrib.get('ref')
                    parent_el = elements.get(parent_ref)
                    if parent_el is not None and parent_el.attrib.get('kind') == 'package_declaration':
                        pkg_name = parent_el.attrib.get('identifier')
                
                fields = []
                elements_list = type_def.find('elements_declaration_list')
                if elements_list is not None:
                    for field_el in elements_list.findall('el'):
                        if field_el.attrib.get('kind') == 'element_declaration':
                            field_name = field_el.attrib.get('identifier')
                            sub_ind = field_el.find('subtype_indication')
                            field_type_str = parse_subtype_indication(sub_ind)
                            fields.append((field_name, field_type_str))
                records[def_id] = {
                    'name': type_name,
                    'package': pkg_name,
                    'fields': fields
                }

    # 2. Find entity declaration
    entity_el = None
    design_unit_el = None
    for el in root.iter():
        if el.attrib.get('kind') == 'design_unit':
            lu = el.find('library_unit')
            if lu is not None and lu.attrib.get('kind') == 'entity_declaration':
                if lu.attrib.get('identifier', '').lower() == entity_name.lower():
                    entity_el = lu
                    design_unit_el = el
                    break

    if entity_el is None:
        print(f"Error: Entity '{entity_name}' not found in AST XML.", file=sys.stderr)
        sys.exit(1)

    # 3. Extract libraries and use clauses
    context_lines = []
    context_items = design_unit_el.find('context_items')
    if context_items is not None:
        for item in context_items.findall('el'):
            if item.attrib.get('kind') == 'library_clause':
                lib_name = item.attrib.get('identifier')
                if lib_name:
                    context_lines.append(f"library {lib_name};")
            elif item.attrib.get('kind') == 'use_clause':
                sel_name = item.find('selected_name')
                name_str = rebuild_selected_name(sel_name)
                if name_str:
                    context_lines.append(f"use {name_str};")

    # Deduplicate context lines while preserving order
    seen = set()
    unique_context_lines = []
    for line in context_lines:
        if line not in seen:
            seen.add(line)
            unique_context_lines.append(line)

    # 4. Extract generics and ports
    generics = []
    generic_chain = entity_el.find('generic_chain')
    if generic_chain is not None:
        for el in generic_chain.findall('el'):
            if el.attrib.get('kind') == 'interface_constant_declaration':
                g_name = el.attrib.get('identifier')
                if g_name:
                    g_type = parse_subtype_indication(el.find('subtype_indication'))
                    generics.append((g_name, g_type))

    ports = []
    port_chain = entity_el.find('port_chain')
    if port_chain is not None:
        for el in port_chain.findall('el'):
            if el.attrib.get('kind') == 'interface_signal_declaration':
                port_name = el.attrib.get('identifier')
                if port_name:
                    mode = el.attrib.get('mode', 'in')
                    type_ref = None
                    type_node = el.find('type')
                    if type_node is not None:
                        type_ref = type_node.attrib.get('ref')
                    if not type_ref:
                        sub_ind = el.find('subtype_indication')
                        if sub_ind is not None:
                            type_node = sub_ind.find('type')
                            if type_node is not None:
                                type_ref = type_node.attrib.get('ref')

                    is_record = type_ref in records
                    type_name = records[type_ref]['name'] if is_record else parse_subtype_indication(el.find('subtype_indication'))
                    ports.append({
                        'name': port_name,
                        'mode': mode,
                        'type': type_name,
                        'is_record': is_record,
                        'record_def': records.get(type_ref) if is_record else None
                    })

    # If reverse is True, we group flat ports into record ports
    if reverse:
        grouped_ports = []
        used_flat_names = set()
        sorted_record_ids = sorted(records.keys(), key=lambda r: len(records[r]['fields']), reverse=True)
        
        for p in ports:
            if p['name'] in used_flat_names:
                continue
                
            matched = False
            for rec_id in sorted_record_ids:
                rec_info = records[rec_id]
                rec_fields = rec_info['fields']
                
                for f_name, _ in rec_fields:
                    suffix = f"_{f_name}"
                    if p['name'].endswith(suffix):
                        prefix = p['name'][:-len(suffix)]
                        candidate_flat_ports = {}
                        all_fields_exist = True
                        for f_name_check, _ in rec_fields:
                            flat_name = f"{prefix}_{f_name_check}"
                            found_port = None
                            for other_p in ports:
                                if other_p['name'] == flat_name and other_p['mode'] == p['mode']:
                                    found_port = other_p
                                    break
                            if found_port is not None and found_port['name'] not in used_flat_names:
                                candidate_flat_ports[f_name_check] = found_port
                            else:
                                all_fields_exist = False
                                break
                                
                        if all_fields_exist:
                            grouped_ports.append({
                                'name': prefix,
                                'mode': p['mode'],
                                'type': rec_info['name'],
                                'is_record': True,
                                'record_def': rec_info
                            })
                            for fp in candidate_flat_ports.values():
                                used_flat_names.add(fp['name'])
                            matched = True
                            break
                if matched:
                    break
                    
            if not matched:
                grouped_ports.append(p)
                used_flat_names.add(p['name'])
        ports = grouped_ports

    # Add package imports for any record ports used, especially in reverse mode
    for p in ports:
        if p['is_record'] and p['record_def']['package']:
            pkg_use = f"use work.{p['record_def']['package']}.all;"
            if pkg_use not in unique_context_lines:
                unique_context_lines.append(pkg_use)

    return unique_context_lines, generics, ports

def generate_normal_wrapper(entity_name, context_lines, generics, ports, library_name):
    wrapper_name = f"{entity_name}_wrapper"
    lines = []
    lines.append("-- Generated by vhdl_wrapper_generator.py (normal mode)")
    lines.extend(context_lines)
    lines.append("")
    lines.append(f"entity {wrapper_name} is")

    if generics:
        lines.append("  generic (")
        gen_decls = []
        for g_name, g_type in generics:
            gen_decls.append(f"    {g_name} : {g_type}")
        lines.append(";\n".join(gen_decls))
        lines.append("  );")

    lines.append("  port (")
    port_decls = []
    for p in ports:
        if p['is_record']:
            for f_name, f_type in p['record_def']['fields']:
                port_decls.append(f"    {p['name']}_{f_name} : {p['mode']} {f_type}")
        else:
            port_decls.append(f"    {p['name']} : {p['mode']} {p['type']}")
    lines.append(";\n".join(port_decls))
    lines.append("  );")
    lines.append(f"end entity {wrapper_name};")
    lines.append("")

    lines.append(f"architecture arch of {wrapper_name} is")
    for p in ports:
        if p['is_record']:
            lines.append(f"  signal sig_{p['name']} : {p['type']};")
    lines.append("begin")

    for p in ports:
        if p['is_record']:
            for f_name, _ in p['record_def']['fields']:
                if p['mode'] == 'in':
                    lines.append(f"  sig_{p['name']}.{f_name} <= {p['name']}_{f_name};")
                else:
                    lines.append(f"  {p['name']}_{f_name} <= sig_{p['name']}.{f_name};")

    lines.append("")
    lines.append(f"  u_dut : entity {library_name}.{entity_name}")
    if generics:
        lines.append("    generic map (")
        lines.append(",\n".join(f"      {g_name} => {g_name}" for g_name, _ in generics))
        lines.append("    )")
    lines.append("    port map (")
    port_maps = []
    for p in ports:
        if p['is_record']:
            port_maps.append(f"      {p['name']} => sig_{p['name']}")
        else:
            port_maps.append(f"      {p['name']} => {p['name']}")
    lines.append(",\n".join(port_maps))
    lines.append("    );")

    lines.append(f"end architecture arch;")
    lines.append("")
    return "\n".join(lines)

def generate_reverse_wrapper(entity_name, context_lines, generics, ports, library_name):
    wrapper_name = f"{entity_name}_wrapper"
    lines = []
    lines.append("-- Generated by vhdl_wrapper_generator.py (reverse mode)")
    lines.extend(context_lines)
    lines.append("")
    lines.append(f"entity {wrapper_name} is")

    if generics:
        lines.append("  generic (")
        gen_decls = []
        for g_name, g_type in generics:
            gen_decls.append(f"    {g_name} : {g_type}")
        lines.append(";\n".join(gen_decls))
        lines.append("  );")

    lines.append("  port (")
    port_decls = []
    for p in ports:
        port_decls.append(f"    {p['name']} : {p['mode']} {p['type']}")
    lines.append(";\n".join(port_decls))
    lines.append("  );")
    lines.append(f"end entity {wrapper_name};")
    lines.append("")

    lines.append(f"architecture arch of {wrapper_name} is")
    lines.append("begin")

    lines.append("")
    lines.append(f"  u_dut : entity {library_name}.{entity_name}")
    if generics:
        lines.append("    generic map (")
        lines.append(",\n".join(f"      {g_name} => {g_name}" for g_name, _ in generics))
        lines.append("    )")
    lines.append("    port map (")
    port_maps = []
    for p in ports:
        if p['is_record']:
            for f_name, _ in p['record_def']['fields']:
                port_maps.append(f"      {p['name']}_{f_name} => {p['name']}.{f_name}")
        else:
            port_maps.append(f"      {p['name']} => {p['name']}")
    lines.append(",\n".join(port_maps))
    lines.append("    );")

    lines.append(f"end architecture arch;")
    lines.append("")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Generate VHDL wrapper using GHDL AST XML")
    parser.add_argument("--ghdl", required=True, help="Path to GHDL binary")
    parser.add_argument("--entity", required=True, help="Name of entity to wrap")
    parser.add_argument("--out", required=True, help="Path to output wrapper VHDL file")
    parser.add_argument("--reverse", action="store_true", help="Generate reverse wrapper (record-to-flat)")
    parser.add_argument("--library", default="work", help="Library name for inner entity")
    parser.add_argument("--std", default="08", help="VHDL standard flag for primary target")
    parser.add_argument("--source", action="append", dest="sources", required=True,
                        help="Transitive source in the format library:std:file_path")
    args = parser.parse_args()

    # Parse sources list
    sources_info = []
    for src_str in args.sources:
        parts = src_str.split(":", 2)
        if len(parts) == 3:
            lib, std, path = parts
            sources_info.append((lib, std, path))

    # Run GHDL analysis and xml generation via subprocesses
    xml_content = run_ghdl_commands(args.ghdl, sources_info, args.std, args.library)

    # Parse interface and types
    context_lines, generics, ports = parse_ast_xml(xml_content, args.entity, args.reverse)

    # Generate code
    if not args.reverse:
        wrapper_code = generate_normal_wrapper(args.entity, context_lines, generics, ports, args.library)
    else:
        wrapper_code = generate_reverse_wrapper(args.entity, context_lines, generics, ports, args.library)

    # Write wrapper file
    with open(args.out, "w") as f:
        f.write(wrapper_code)

if __name__ == "__main__":
    main()
