package subcommands

import (
	"os/exec"
	"strings"

	"github.com/Jguer/go-alpm/v2"
	"github.com/Songbird-Project/nest/core"
)

// Search:
// Find packages on the AUR and main repos

type SearchCmd struct {
	Name      string `arg:"positional"`
	MaxOutput int    `arg:"-m,--max-out" help:"max number of packages to list"`
}

func SearchPkg(alpmHandle *alpm.Handle, searchTerms string) ([]core.Package, error) {
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
		packageList = append(packageList, pkg)
	}

	return packageList, nil
}
