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

type Repo struct {
	Server   string
	SigLevel string
	Include  string
}

type NestConfig struct {
	// Style
	Color bool

	// Generation
	CompressOld bool

	// Other (more categorisation with more options)
	Repos []*Repo
}
