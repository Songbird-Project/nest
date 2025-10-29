package core

type Package struct {
	// Metadata
	Name        string
	Description string
	Version     string
	Repo        string

	// Package Info
	Maintainer  string
	UpstreamURL string
	LastUpdated string
	Licenses    []string
	OutOfDate   bool

	// Installed
	CurrentBuildLocation string
	Installed            bool
}
