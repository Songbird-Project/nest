package subcommands

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/Jguer/go-alpm/v2"
	"github.com/Songbird-Project/nest/core"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/mikkeloscar/aur"
)

// Search:
// Find packages on the AUR and main repos

type SearchCmd struct {
	Name      string   `arg:"positional"`
	Repos     []string `arg:"--repos" help:"only search in the given repos"`
	MaxOutput int      `arg:"-m,--max-out" help:"max number of packages to list for each repo"`
}

func SearchPkg(alpmHandle *alpm.Handle, args *SearchCmd) ([]core.Package, error) {
	searchTerms := args.Name
	searchRepos := args.Repos

	pkgList := []core.Package{}
	searchMainRepos := exec.Command("pacman", append([]string{"-Ss"}, strings.Split(searchTerms, " ")...)...)
	cmdOutput, err := searchMainRepos.Output()
	if err != nil {
		return pkgList, err
	}

	pkgInfo := strings.Split(string(cmdOutput), "\n")
	for i := 0; i < len(pkgInfo)-1; i += 2 {
		info := pkgInfo[i]
		description := pkgInfo[i+1]
		repoNameVersion := strings.Split(info, "/")
		if len(repoNameVersion) < 2 {
			continue
		}

		repo := repoNameVersion[0]

		nameVersion := strings.Fields(repoNameVersion[1])
		if len(nameVersion) < 2 {
			continue
		}

		name := nameVersion[0]
		version := nameVersion[1]
		desc := strings.TrimSpace(description)

		pkg := core.Package{
			Name:        name,
			Repo:        repo,
			Description: desc,
			Version:     version,
		}

		if strings.Contains(strings.Join(searchRepos, " "), pkg.Repo) || len(searchRepos) == 0 {
			pkgList = append(pkgList, pkg)
		}
	}

	aurQuery := strings.Split(strings.ToLower(searchTerms), " ")
	aurPkgs := []aur.Pkg{}

	aurSearch, err := aur.Search(searchTerms)
	if err == nil {
		// aurConcatSearch, err := aur.Search(strings.ReplaceAll(searchTerms, " ", "-"))
		// if err == nil {
		// aurSearch = append(aurSearch, aurConcatSearch...)
		// }

		seen := map[string]bool{}
		for _, pack := range aurSearch {
			matched := true
			for _, q := range aurQuery {
				if !((strings.Contains(strings.ToLower(pack.Name), q) ||
					strings.Contains(strings.ToLower(pack.Description), q)) &&
					matched) {
					matched = false
				}
			}
			if matched && !seen[pack.Name] {
				seen[pack.Name] = true
				aurPkgs = append(aurPkgs, pack)
			}
		}
	}

	for _, pkgInfo := range aurPkgs {
		pkg := core.Package{
			Name:        pkgInfo.Name,
			Repo:        "aur",
			Description: pkgInfo.Description,
			Version:     pkgInfo.Version,
		}

		if strings.Contains(strings.Join(searchRepos, " "), "aur") || len(searchRepos) == 0 {
			pkgList = append(pkgList, pkg)
		}
	}

	return pkgList, nil
}

func FormatPkgs(pkgs []core.Package, maxOutput int) string {
	lim := len(pkgs)
	if maxOutput > 0 && maxOutput < lim {
		lim = maxOutput
	}

	maxNumberWidth := len(fmt.Sprintf("%d.", lim))

	infoString := ""
	for i := 0; i < lim; i++ {
		repoColor := core.GetStyleForRepo(pkgs[i].Repo, core.GetRepoColors())

		pkgNumber := fmt.Sprintf("%d.", i+1)
		paddedPkg := fmt.Sprintf("%-*s", maxNumberWidth, pkgNumber)
		repoStyle := lipgloss.NewStyle().Foreground(repoColor)
		formattedPkgNumber := repoStyle.Render(paddedPkg)

		infoString += fmt.Sprintf("%s %s", formattedPkgNumber, pkgs[i].Name)
		if i != lim-1 {
			infoString += "\n"
		}
	}

	if lim < len(pkgs) {
		subtext := lipgloss.NewStyle().Foreground(lipgloss.BrightBlack)
		pkgsHiddenText := fmt.Sprintf("\n%d packages have been hidden", len(pkgs)-lim)
		infoString += subtext.Render(pkgsHiddenText)
	}

	return infoString
}
