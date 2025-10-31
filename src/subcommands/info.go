package subcommands

import (
	"fmt"
	"strings"

	"github.com/Jguer/go-alpm/v2"
	"github.com/Songbird-Project/nest/core"
	"github.com/charmbracelet/lipgloss/v2"
)

type InfoCmd struct {
	Name  string   `arg:"positional"`
	Repos []string `arg:"--repos" help:"only search in the given repos"`
}

func PkgInfo(alpmHandle *alpm.Handle, args *InfoCmd) (string, error) {
	cmd := &SearchCmd{
		Name:      args.Name,
		Repos:     args.Repos,
		MaxOutput: 1,
	}
	pkgs, err := SearchPkg(alpmHandle, cmd)
	if err != nil {
		return "", err
	}

	pkgList := []core.Package{}
	pkgInfo := ""
	selectedPkg := 0

	for _, pkg := range pkgs {
		if strings.EqualFold(pkg.Name, args.Name) {
			pkgList = append(pkgList, pkg)
		}
	}

	repoNameStyle := lipgloss.NewStyle().Foreground(lipgloss.Blue)
	borderStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		Width(70).
		PaddingLeft(1).
		PaddingRight(1)

	if len(pkgList) > 1 {
		// TODO: Add user choice on which to view
	} else if len(pkgList) <= 0 {
		return fmt.Sprintf("No packages named %s found", repoNameStyle.Render(args.Name)), nil
	}

	pkg := pkgList[selectedPkg]
	// repoColor := core.GetStyleForRepo(pkg.Repo, core.GetRepoColors())
	// borderStyle = borderStyle.BorderForeground(repoColor)
	// repoNameStyle := lipgloss.NewStyle().Foreground(repoColor)
	borderStyle = borderStyle.BorderForeground(lipgloss.Blue)
	pkgRepoName := repoNameStyle.Render(fmt.Sprintf("%s/%s - %s", pkg.Repo, pkg.Name, pkg.Version))

	pkgInfo = borderStyle.Render(fmt.Sprintf("%s\n %s", pkgRepoName, pkg.Description))

	return pkgInfo, nil
}
