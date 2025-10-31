package main

import (
	"fmt"
	"os"

	"github.com/Songbird-Project/nest/core"
	"github.com/Songbird-Project/nest/subcommands"
	"github.com/alexflint/go-arg"
	"github.com/charmbracelet/lipgloss/v2"
)

var args struct {
	// Subcommands
	Search *subcommands.SearchCmd `arg:"subcommand:search"`
	Info   *subcommands.InfoCmd   `arg:"subcommand:info"`
}

func main() {
	handler, err := core.AlpmInit()
	if err != nil {
		fmt.Printf("%s\n", err)
		os.Exit(1)
	}

	borderStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		Width(70).
		PaddingLeft(1).
		PaddingRight(1)

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
			borderStyle = borderStyle.BorderForeground(core.GetStyleForRepo(repo, repoColors))

			colorisedRepoName := fmt.Sprintf("%s:\n", core.ColoriseByRepo(repo, repoColors))
			formattedPkgList := subcommands.FormatPkgs(pkgs, args.Search.MaxOutput)

			repoPkgsString := colorisedRepoName + formattedPkgList
			fmt.Println(borderStyle.Render(repoPkgsString))
		}
	case args.Info != nil:
		pkgInfo, err := subcommands.PkgInfo(handler, args.Info)
		if err != nil {
			fmt.Printf("%s\n", err)
			os.Exit(1)
		}

		fmt.Println(pkgInfo)
	}
}
