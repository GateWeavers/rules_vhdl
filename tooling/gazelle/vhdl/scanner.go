package vhdl

import (
	"bufio"
	"os"
	"regexp"
	"strings"
)

// VhdlFileMetadata stores information extracted from a VHDL source file.
type VhdlFileMetadata struct {
	FilePath  string
	Libraries []string
	Imports   []string // lib.package
	Entities  []string
	Packages  []string
}

var (
	entityRegex  = regexp.MustCompile(`(?i)^\s*entity\s+([a-zA-Z0-9_]+)\s+is`)
	packageRegex = regexp.MustCompile(`(?i)^\s*package\s+(?:body\s+)?([a-zA-Z0-9_]+)\s+is`)
	libraryRegex       = regexp.MustCompile(`(?i)^\s*library\s+([a-zA-Z0-9_]+)\s*;`)
	useRegex           = regexp.MustCompile(`(?i)^\s*use\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`)
	instantiationRegex = regexp.MustCompile(`(?i)entity\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)`)
)

// ScanFile reads a VHDL file and extracts its metadata.
func ScanFile(path string) (*VhdlFileMetadata, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	meta := &VhdlFileMetadata{FilePath: path}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		
		// Strip comments
		if idx := strings.Index(line, "--"); idx != -1 {
			line = line[:idx]
		}
		
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Detect declarations
		if m := entityRegex.FindStringSubmatch(line); m != nil {
			meta.Entities = append(meta.Entities, strings.ToLower(m[1]))
		}
		if m := packageRegex.FindStringSubmatch(line); m != nil {
			meta.Packages = append(meta.Packages, strings.ToLower(m[1]))
		}
		
		// Detect dependencies
		if m := libraryRegex.FindStringSubmatch(line); m != nil {
			lib := strings.ToLower(m[1])
			if !contains(meta.Libraries, lib) {
				meta.Libraries = append(meta.Libraries, lib)
			}
		}
		if m := useRegex.FindStringSubmatch(line); m != nil {
			lib := strings.ToLower(m[1])
			pkg := strings.ToLower(m[2])
			if !contains(meta.Libraries, lib) {
				meta.Libraries = append(meta.Libraries, lib)
			}
			imp := lib + "." + pkg
			if !contains(meta.Imports, imp) {
				meta.Imports = append(meta.Imports, imp)
			}
		}
		if m := instantiationRegex.FindStringSubmatch(line); m != nil {
			lib := strings.ToLower(m[1])
			ent := strings.ToLower(m[2])
			if !contains(meta.Libraries, lib) {
				meta.Libraries = append(meta.Libraries, lib)
			}
			imp := lib + "." + ent
			if !contains(meta.Imports, imp) {
				meta.Imports = append(meta.Imports, imp)
			}
		}
	}

	return meta, scanner.Err()
}

func contains(slice []string, s string) bool {
	for _, v := range slice {
		if v == s {
			return true
		}
	}
	return false
}
