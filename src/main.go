package main

import (
	"fmt"
	"os"

	"github.com/Songbird-Project/nest/core"
	"github.com/Songbird-Project/nest/subcommands"
	"github.com/alexflint/go-arg"
	"github.com/charmbracelet/lipgloss/v2"
)

const nestVersion = "0.0.1"

var args struct {
	// Top Level Flags
	Version bool `arg:"-V,--version" help:"print the current nest version and exit"`

	// Subcommands
	Search  *subcommands.SearchCmd  `arg:"subcommand:search" help:"search for a package"`
	Info    *subcommands.InfoCmd    `arg:"subcommand:info" help:"retrieve the info of a package"`
	Add     *subcommands.AddCmd     `arg:"subcommand:add" help:"add the given package to the package list"`
	Install *subcommands.InstallCmd `arg:"subcommand:install" help:"imperatively install the given package"`
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

	if args.Version {
		fmt.Printf("nest v%s\n", nestVersion)
		return
	}

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
	case args.Add != nil:
		return
	}
}
