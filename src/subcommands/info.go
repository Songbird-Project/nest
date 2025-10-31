package subcommands

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
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

	if len(pkgList) <= 0 {
		nameStyle := lipgloss.NewStyle().Foreground(lipgloss.Blue)
		return fmt.Sprintf("No packages named %s found", nameStyle.Render(args.Name)), nil
	}

	repoNameStyle := lipgloss.NewStyle().Foreground(lipgloss.Blue)
	descStyle := lipgloss.NewStyle().
		PaddingLeft(1)
	borderStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		PaddingLeft(1).
		PaddingRight(1)

	if len(pkgList) > 1 {
		nameStyle := lipgloss.NewStyle().Foreground(lipgloss.Blue)
		pkgListString := fmt.Sprintf("There is more than one provider for %s:\n", nameStyle.Render(args.Name))
		for i, pkg := range pkgList {
			colorisedRepo := core.ColoriseByRepo(pkg.Repo, core.GetRepoColors())
			pkgListString += fmt.Sprintf("%d) %s", i+1, colorisedRepo)
			if i != len(pkgList)-1 {
				pkgListString += "  |  "
			}
		}

		pkgListString += lipgloss.
			NewStyle().
			Foreground(lipgloss.Blue).
			Render("\n==> ")

		fmt.Print(pkgListString)
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Scan()
		input := scanner.Text()
		if input == "" {
			input = "1"
		}
		selection, err := strconv.Atoi(input)
		if err != nil || selection < 1 || selection > len(pkgList) {
			return "", fmt.Errorf("invalid selection")
		}
		selectedPkg = selection - 1
	}

	pkg := pkgList[selectedPkg]

	pkgRepoPrefix := pkg.Repo

	pkgDesc := descStyle.Render(pkg.Description)
	pkgRepoName := repoNameStyle.Render(fmt.Sprintf("%s/%s - %s", pkgRepoPrefix, pkg.Name, pkg.Version))
	borderStyle = borderStyle.
		BorderForeground(lipgloss.Blue).
		Width(len(pkgDesc) + 1)
	pkgInfo = borderStyle.Render(fmt.Sprintf("%s\n%s", pkgRepoName, pkgDesc))
	return pkgInfo, nil
}
