package core

import (
	"sort"
	"strings"

	"github.com/Jguer/go-alpm/v2"
	"github.com/fatih/color"
)

func AlpmInit() (*alpm.Handle, error) {
	handler, err := alpm.Initialize("/", "/var/lib/pacman")
	if err != nil {
		return nil, err
	}

	return handler, nil
}

func OrganisePkgsByRepo(packages []Package) map[string][]Package {
	repoMap := make(map[string][]Package)

	for _, pkg := range packages {
		repoMap[pkg.Repo] = append(repoMap[pkg.Repo], pkg)
	}

	return repoMap
}

func GetRepoColors() map[string]func(...any) string {
	return map[string]func(...any) string{
		"core":     color.New(color.FgGreen).SprintFunc(),
		"extra":    color.New(color.FgYellow).SprintFunc(),
		"multilib": color.New(color.FgBlue).SprintFunc(),
		"testing":  color.New(color.FgRed).SprintFunc(),
		"aur":      color.New(color.FgCyan).SprintFunc(),
	}
}

func ColoriseByRepo(repo string, repoColors map[string]func(...any) string) string {
	repoLower := strings.ToLower(repo)

	if repoLower == "aur" {
		return repoColors["aur"](repo)
	}

	for key, colorFunc := range repoColors {
		if key != "aur" && strings.Contains(repoLower, key) {
			return colorFunc(repo)
		}
	}

	return color.New(color.FgMagenta).SprintFunc()(repo)
}

func SortRepos(organisedPkgs map[string][]Package) []string {
	order := []string{"core", "extra", "multilib", "testing", "aur"}
	result := []string{}
	seen := make(map[string]bool)

	for _, repoName := range order {
		for repo := range organisedPkgs {
			if strings.ToLower(repo) == repoName {
				result = append(result, repo)
				seen[repo] = true
			}
		}
	}

	remainingRepos := []string{}
	for repo := range organisedPkgs {
		if !seen[repo] {
			remainingRepos = append(remainingRepos, repo)
		}
	}

	sort.Strings(remainingRepos)

	result = append(result, remainingRepos...)

	return result
}
