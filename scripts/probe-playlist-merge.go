//go:build ignore

// probe-playlist-merge exercises the public gomobile merge contract without UI.
// It reports typed playlist conflicts before export, or resolves all playlist
// conflicts to either side and exports a result for semantic inspection.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/AndreasSko/go-library-merger/gomobile"
)

type result struct {
	Status           string                    `json:"status"`
	Error            string                    `json:"error,omitempty"`
	Conflicts        []*gomobile.MergeConflict `json:"conflicts,omitempty"`
	InitialConflicts []*gomobile.MergeConflict `json:"initialConflicts,omitempty"`
	Output           string                    `json:"output,omitempty"`
}

func main() {
	if len(os.Args) < 4 || len(os.Args) > 5 {
		fmt.Fprintln(os.Stderr, "usage: go run probe-playlist-merge.go LEFT RIGHT detect|left|right [OUTPUT]")
		os.Exit(2)
	}
	mode := os.Args[3]
	if mode != "detect" && mode != "left" && mode != "right" {
		fmt.Fprintln(os.Stderr, "mode must be detect, left, or right")
		os.Exit(2)
	}
	value, code := run(os.Args[1], os.Args[2], mode, os.Args[4:])
	_ = json.NewEncoder(os.Stdout).Encode(value)
	os.Exit(code)
}

func run(left, right, mode string, outputArgs []string) (result, int) {
	failure := func(stage string, err error) (result, int) {
		return result{Status: "error", Error: stage + ": " + err.Error()}, 1
	}
	tmp, err := os.MkdirTemp("", "playlist-merge-probe-")
	if err != nil {
		return failure("temporary directory", err)
	}
	defer os.RemoveAll(tmp)
	db := &gomobile.DatabaseWrapper{TempDir: tmp}
	defer db.Close()
	if err := db.ImportJWLBackup(left, "leftSide"); err != nil {
		return failure("import left", err)
	}
	if err := db.ImportJWLBackup(right, "rightSide"); err != nil {
		return failure("import right", err)
	}
	db.Init()
	conflicts := &gomobile.MergeConflictsWrapper{}
	conflicts.InitDBWrapper(db)
	steps := []struct {
		name string
		fn   func() error
	}{
		{"locations", db.MergeLocations},
		{"bookmarks", func() error { return db.MergeBookmarks("chooseLeft", &gomobile.MergeConflictsWrapper{}) }},
		{"input fields", func() error { return db.MergeInputFields("chooseLeft", &gomobile.MergeConflictsWrapper{}) }},
		{"tags", db.MergeTags},
		{"markings", func() error { return db.MergeUserMarkAndBlockRange("chooseLeft", &gomobile.MergeConflictsWrapper{}) }},
		{"notes", func() error { return db.MergeNotes("chooseLeft", &gomobile.MergeConflictsWrapper{}) }},
	}
	for _, step := range steps {
		if err := step.fn(); err != nil {
			return failure("merge "+step.name, err)
		}
	}
	resolver := ""
	if mode == "left" {
		resolver = "chooseLeft"
	} else if mode == "right" {
		resolver = "chooseRight"
	}
	if err := db.MergePlaylists(resolver, conflicts); err != nil {
		if mode != "detect" {
			return failure("merge playlists", err)
		}
		// Test the first unresolved phase before simulating later resolutions.
		blocked := filepath.Join(tmp, "must-not-export.jwlibrary")
		if exportErr := db.ExportMerged(blocked); exportErr == nil {
			return failure("conflict export gate", fmt.Errorf("export unexpectedly succeeded"))
		}
		if _, statErr := os.Stat(blocked); !os.IsNotExist(statErr) {
			return failure("conflict export gate", fmt.Errorf("export left an artifact"))
		}
		found := []*gomobile.MergeConflict{}
		initial := []*gomobile.MergeConflict{}
		for phase := 0; ; phase++ {
			if phase >= 1000 {
				return failure("enumerate playlist conflicts", fmt.Errorf("exceeded 1000 solver phases"))
			}
			before := len(found)
			for {
				conflict, nextErr := conflicts.NextConflict()
				if nextErr != nil {
					if nextErr.Error() != "There are no unsolved conflicts" {
						return failure("enumerate playlist conflicts", nextErr)
					}
					break
				}
				found = append(found, conflict)
				if phase == 0 {
					initial = append(initial, conflict)
				}
				if solveErr := conflicts.SolveConflict(conflict.Key, "leftSide"); solveErr != nil {
					return failure("enumerate playlist conflicts", solveErr)
				}
			}
			if len(found) == before {
				return failure("merge playlists", fmt.Errorf("unresolved phase reported no conflicts: %w", err))
			}
			if err = db.MergePlaylists("", conflicts); err == nil {
				break
			}
		}
		// Preserve both serialized sides and the initial phase. Map enumeration
		// order has no meaning; no detection result is exported after solving.
		sort.Slice(found, func(i, j int) bool { return found[i].Key < found[j].Key })
		sort.Slice(initial, func(i, j int) bool { return initial[i].Key < initial[j].Key })
		return result{Status: "conflict", Conflicts: found, InitialConflicts: initial}, 0
	}
	if mode == "detect" {
		resolver = "none"
	}
	if err := db.MergeTagMaps(); err != nil {
		return failure("merge tag maps", err)
	}
	output := ""
	if len(outputArgs) == 1 {
		output, err = filepath.Abs(outputArgs[0])
		if err != nil {
			return failure("output path", err)
		}
		if err := db.ExportMerged(output); err != nil {
			return failure("export", err)
		}
	}
	return result{Status: "success", Output: output}, 0
}
