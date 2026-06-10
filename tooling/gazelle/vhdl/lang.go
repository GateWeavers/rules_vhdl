package vhdl

import (
	"log"
	"path/filepath"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

const VhdlName = "vhdl"

type vhdlConfig struct {
	enabled bool
	libName string
}

type vhdlLang struct {
	language.BaseLang
}

// NewLanguage returns a new instance of the VHDL language extension.
func NewLanguage() language.Language {
	return &vhdlLang{}
}

func (*vhdlLang) Name() string { return VhdlName }

func (l *vhdlLang) Configure(c *config.Config, rel string, f *rule.File) {
	cfg := &vhdlConfig{enabled: true}
	if old, ok := c.Exts[VhdlName]; ok {
		*cfg = *old.(*vhdlConfig)
	}
	
	if f != nil {
		for _, d := range f.Directives {
			if d.Key == "vhdl_enabled" {
				cfg.enabled = (d.Value == "true")
			} else if d.Key == "vhdl_library_name" {
				cfg.libName = d.Value
			}
		}
	}
	c.Exts[VhdlName] = cfg
}

func (*vhdlLang) Kinds() map[string]rule.KindInfo {
	return map[string]rule.KindInfo{
		"vhdl_library": {
			NonEmptyAttrs:  map[string]bool{"srcs": true},
			MergeableAttrs: map[string]bool{"srcs": true},
			ResolveAttrs:   map[string]bool{"deps": true},
		},
		"vunit_sim": {
			NonEmptyAttrs:  map[string]bool{"srcs": true},
			MergeableAttrs: map[string]bool{"srcs": true},
			ResolveAttrs:   map[string]bool{"deps": true},
		},
	}
}

func (*vhdlLang) Loads() []rule.LoadInfo {
	return []rule.LoadInfo{
		{
			Name:    "@gateweaver_rules_vhdl//vhdl:vhdl.bzl",
			Symbols: []string{"vhdl_library"},
		},
		{
			Name:    "@gateweaver_rules_vhdl//sim:vunit_rules.bzl",
			Symbols: []string{"vunit_sim"},
		},
	}
}

func (*vhdlLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	cfg := args.Config.Exts[VhdlName].(*vhdlConfig)
	if !cfg.enabled {
		return language.GenerateResult{}
	}

	var rules []*rule.Rule
	var imports []interface{}

	var vhdlFiles []string
	var vhdlMetas []*VhdlFileMetadata
	
	var testbenchFiles []string
	var testbenchMetas []*VhdlFileMetadata

	for _, f := range args.RegularFiles {
		if strings.HasSuffix(f, ".vhd") || strings.HasSuffix(f, ".vhdl") {
			meta, err := ScanFile(filepath.Join(args.Dir, f))
			if err != nil {
				log.Printf("VHDL scanner error for %s: %v", f, err)
				continue
			}

			// Heuristic: if it has an entity ending in _tb or starting with tb_, it's a testbench
			isTb := false
			for _, ent := range meta.Entities {
				if strings.HasPrefix(ent, "tb_") || strings.HasSuffix(ent, "tb") {
					isTb = true
					break
				}
			}

			if isTb {
				testbenchFiles = append(testbenchFiles, f)
				testbenchMetas = append(testbenchMetas, meta)
			} else {
				vhdlFiles = append(vhdlFiles, f)
				vhdlMetas = append(vhdlMetas, meta)
			}
		}
	}

	// Generate vhdl_library for implementation files
	if len(vhdlFiles) > 0 {
		libName := filepath.Base(args.Rel)
		if libName == "." {
			libName = "root_lib"
		} else {
			libName = libName + "_lib"
		}
		
		vhdlLibName := strings.TrimSuffix(libName, "_lib")
		if cfg.libName != "" {
			vhdlLibName = cfg.libName
			libName = cfg.libName
		}

		r := rule.NewRule("vhdl_library", libName)
		r.SetAttr("srcs", vhdlFiles)
		r.SetAttr("library_name", vhdlLibName)
		r.SetAttr("visibility", []string{"//visibility:public"})
		rules = append(rules, r)
		
		// For the library, we return all metas for its files
		imports = append(imports, vhdlMetas)
	}

	// Generate vunit_sim for each testbench
	for i, tb := range testbenchFiles {
		name := strings.TrimSuffix(strings.TrimSuffix(tb, ".vhd"), ".vhdl")
		r := rule.NewRule("vunit_sim", name)
		r.SetAttr("srcs", []string{tb})
		r.SetAttr("visibility", []string{"//visibility:public"})
		rules = append(rules, r)
		
		// For a testbench, we return a slice containing its single meta
		imports = append(imports, []*VhdlFileMetadata{testbenchMetas[i]})
	}

	return language.GenerateResult{
		Gen:   rules,
		Imports:   imports,
		Empty:     nil,
	}
}
