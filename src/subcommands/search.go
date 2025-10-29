package subcommands

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/Jguer/go-alpm/v2"
	"github.com/Songbird-Project/nest/core"
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

	packageList := []core.Package{}
	searchMainRepos := exec.Command("pacman", append([]string{"-Ss"}, strings.Split(searchTerms, " ")...)...)
	cmdOutput, err := searchMainRepos.Output()
	if err != nil {
		return packageList, err
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

		if strings.Contains(strings.Join(searchRepos, " "), pkg.Repo) {
			packageList = append(packageList, pkg)
		}
	}

	return packageList, nil
}

func PrintPkgs(pkgs []core.Package, maxOutput int) {
	lim := len(pkgs)
	if maxOutput > 0 && maxOutput < lim {
		lim = maxOutput
	}

	for i := 0; i < lim; i++ {
		fmt.Printf(" - %s\n", pkgs[i].Name)
	}

	if lim < len(pkgs) {
		fmt.Printf("  %d packages have been hidden", len(pkgs)-lim)
	}
}
