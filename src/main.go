package main

import (
	"fmt"
	"os"

	"github.com/Songbird-Project/nest/core"
	"github.com/Songbird-Project/nest/subcommands"
	"github.com/alexflint/go-arg"
)

var args struct {
	// Subcommands
	Search *subcommands.SearchCmd `arg:"subcommand:search"`
}

func main() {
	handler, err := core.AlpmInit()
	if err != nil {
		fmt.Printf("%s\n", err)
		os.Exit(1)
	}

	arg.MustParse(&args)

	switch {
	case args.Search != nil:
		pkgList, err := subcommands.SearchPkg(handler, args.Search)
		if err != nil {
			fmt.Printf("%s\n", err)
			os.Exit(1)
		}

		organisedPkgs := core.OrganisePkgsByRepo(pkgList)
		repoColors := core.GetRepoColors()
		sortedRepos := core.SortRepos(organisedPkgs)

		for _, repo := range sortedRepos {
			pkgs := organisedPkgs[repo]
			fmt.Printf("%s:\n", core.ColoriseByRepo(repo, repoColors))
			subcommands.PrintPkgs(pkgs, args.Search.MaxOutput)
			fmt.Println()
		}
	}
}
