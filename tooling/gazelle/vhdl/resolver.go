//     Copyright 2026 Nocilis
//     Licensed under the Apache License, Version 2.0 (the "License");
//     you may not use this file except in compliance with the License.
//     You may obtain a copy of the License at
//         http://www.apache.org/licenses/LICENSE-2.0
//     Unless required by applicable law or agreed to in writing, software
//     distributed under the License is distributed on an "AS IS" BASIS,
//     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//     See the License for the specific language governing permissions and
//     limitations under the License.

package vhdl

import (
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// Imports returns a list of symbols provided by this rule.
func (*vhdlLang) Imports(c *config.Config, r *rule.Rule, f *rule.File) []resolve.ImportSpec {
	var specs []resolve.ImportSpec
	
	// We index based on the VHDL library name and the units provided.
	libName := r.AttrString("library_name")
	if libName == "" {
		libName = "work"
	}

	return specs
}

// Resolve maps VHDL imports to Bazel labels.
func (*vhdlLang) Resolve(c *config.Config, ix *resolve.RuleIndex, rc *repo.RemoteCache, r *rule.Rule, imports interface{}, from label.Label) {
	if imports == nil {
		return
	}

	metaList := imports.([]*VhdlFileMetadata)
	var deps []string

	for _, meta := range metaList {
		// 1. Resolve 'library' clauses
		for _, lib := range meta.Libraries {
			if lib == "ieee" || lib == "std" {
				continue
			}
			// Look for a rule that provides this library
		}

		// 2. Resolve 'use' clauses
		for _, imp := range meta.Imports {
			// imp is "lib.package"
			if strings.HasPrefix(imp, "ieee.") || strings.HasPrefix(imp, "std.") {
				continue
			}
		}
	}

	if r.Kind() == "vunit_sim" {
		var vhdlLib string
		for _, meta := range metaList {
			for _, lib := range meta.Libraries {
				// Ignore standard and support libraries
				if lib != "ieee" && lib != "std" && lib != "vunit_lib" && lib != "osvvm" {
					vhdlLib = lib
					break
				}
			}
		}

		if strings.Contains(from.Pkg, "/test") && vhdlLib != "" {
			parentPkg := strings.TrimSuffix(from.Pkg, "/test")
			r.SetAttr("dut", "//"+parentPkg+":"+vhdlLib)
		}
	}

	if len(deps) > 0 {
		r.SetAttr("deps", deps)
	}
}

func filepathBase(path string) string {
	parts := strings.Split(path, "/")
	return parts[len(parts)-1]
}
